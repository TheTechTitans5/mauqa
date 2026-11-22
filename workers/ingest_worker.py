"""
Mauqa ingestion worker (optional).

Edge Functions cannot run OCR or heavy HTML parsing, so this small worker provides:

  POST /extract-pdf      body: raw PDF bytes   headers: X-Worker-Token, X-OCR: 1|0
                         → {"text": "...", "pages": N, "ocr_used": bool}
  GET  /health

It also exposes `monitor_page()` for sites that need BeautifulSoup parsing; it honours robots.txt,
identifies itself, rate-limits, and refuses login/CAPTCHA pages. It never bypasses access controls.

Run:   PDF_EXTRACT_TOKEN=... python3 workers/ingest_worker.py --port 8787
Deploy anywhere that can run Python 3.11+ (a small VM, Cloud Run, Fly.io). Set PDF_EXTRACT_URL and
PDF_EXTRACT_TOKEN as Supabase secrets so the pdf connector can call it.

Requirements: pdfminer.six, beautifulsoup4, requests; optional OCR: pytesseract + pdf2image + tesseract-ocr (with urd language data).
"""
from __future__ import annotations

import argparse
import hmac
import io
import json
import os
import re
import time
import urllib.robotparser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urljoin, urlparse

MAX_PDF_BYTES = 15 * 1024 * 1024
USER_AGENT = f"MauqaBot/1.0 (opportunity verification; contact: {os.environ.get('BOT_CONTACT', 'not-configured')})"


class BlockedError(Exception):
    """Raised when a page must not be fetched (robots.txt, login wall, CAPTCHA, 401/403)."""


def extract_pdf_text(data: bytes, ocr: bool = False) -> dict:
    if not data.startswith(b"%PDF"):
        raise ValueError("Not a PDF file")
    if len(data) > MAX_PDF_BYTES:
        raise ValueError("PDF too large")
    from pdfminer.high_level import extract_text
    from pdfminer.pdfpage import PDFPage

    pages = sum(1 for _ in PDFPage.get_pages(io.BytesIO(data)))
    text = extract_text(io.BytesIO(data)) or ""
    ocr_used = False
    # Scanned announcements have (almost) no text layer → OCR if requested and available.
    if ocr and len(text.strip()) < 40 * max(pages, 1):
        try:
            import pytesseract  # type: ignore
            from pdf2image import convert_from_bytes  # type: ignore

            images = convert_from_bytes(data, dpi=200, first_page=1, last_page=min(pages, 10))
            text = "\n".join(pytesseract.image_to_string(img, lang="eng+urd") for img in images)
            ocr_used = True
        except ImportError:
            pass  # OCR libraries not installed: return what we have; reviewer extracts manually
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return {"text": text, "pages": pages, "ocr_used": ocr_used}


class PoliteSession:
    def __init__(self, rate_per_minute: int = 6):
        import requests

        self.s = requests.Session()
        self.s.headers["User-Agent"] = USER_AGENT
        self.gap = 60.0 / max(1, rate_per_minute)
        self.last = 0.0
        self.robots: dict[str, urllib.robotparser.RobotFileParser] = {}

    def allowed(self, url: str) -> bool:
        origin = "{0.scheme}://{0.netloc}".format(urlparse(url))
        if origin not in self.robots:
            rp = urllib.robotparser.RobotFileParser()
            try:
                r = self.s.get(origin + "/robots.txt", timeout=15)
                if r.status_code >= 500:
                    raise BlockedError(f"robots.txt unavailable for {origin}; not fetching")
                rp.parse(r.text.splitlines() if r.ok else [])
            except BlockedError:
                raise
            except Exception as e:  # network failure → fail closed
                raise BlockedError(f"robots.txt could not be read for {origin}: {e}") from e
            self.robots[origin] = rp
        return self.robots[origin].can_fetch(USER_AGENT, url)

    def get(self, url: str) -> str:
        if not url.startswith("https://"):
            raise BlockedError("Only HTTPS sources are monitored")
        if not self.allowed(url):
            raise BlockedError(f"robots.txt disallows {url}")
        wait = self.last + self.gap - time.time()
        if wait > 0:
            time.sleep(wait)
        self.last = time.time()
        r = self.s.get(url, timeout=30)
        if r.status_code in (401, 403):
            raise BlockedError(f"Access denied ({r.status_code}) — authorisation required")
        r.raise_for_status()
        html = r.text
        assert_not_gated(html, url)
        return html


def assert_not_gated(html: str, url: str) -> None:
    if re.search(r"g-recaptcha|hcaptcha|cf-challenge|captcha-container", html, re.I):
        raise BlockedError(f"CAPTCHA detected at {url}")
    if re.search(r"<input[^>]+type=[\"']password[\"']", html, re.I) and len(html) < 20000:
        raise BlockedError(f"Login form detected at {url}")


def monitor_page(html: str, base_url: str, link_include: list[str], selector: str | None = None) -> list[dict]:
    """Extracts candidate announcement links from an already-fetched list page."""
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html, "html.parser")
    scope = soup.select(selector) if selector else [soup]
    seen, out = set(), []
    host = urlparse(base_url).netloc
    for root in scope:
        for a in root.find_all("a", href=True):
            href = urljoin(base_url, a["href"])
            text = " ".join(a.get_text(" ").split())
            if href in seen or urlparse(href).netloc != host:
                continue
            if not any(s.lower() in href.lower() or s.lower() in text.lower() for s in link_include):
                continue
            seen.add(href)
            out.append({"url": href, "title": text[:240], "is_pdf": href.lower().split("?")[0].endswith(".pdf")})
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "MauqaWorker/1.0"

    def _json(self, code: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):  # noqa: N802
        if self.path == "/health":
            return self._json(200, {"ok": True})
        return self._json(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        if self.path != "/extract-pdf":
            return self._json(404, {"error": "not found"})
        expected = os.environ.get("PDF_EXTRACT_TOKEN", "")
        if not expected or not hmac.compare_digest(self.headers.get("X-Worker-Token", ""), expected):
            return self._json(401, {"error": "invalid token"})
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_PDF_BYTES:
            return self._json(413, {"error": "missing or too large body"})
        try:
            result = extract_pdf_text(self.rfile.read(length), ocr=self.headers.get("X-OCR") == "1")
            return self._json(200, result)
        except ValueError as e:
            return self._json(422, {"error": str(e)})

    def log_message(self, fmt, *args):  # keep logs free of document contents
        print("worker:", fmt % args)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8787")))
    args = p.parse_args()
    if not os.environ.get("PDF_EXTRACT_TOKEN"):
        raise SystemExit("Set PDF_EXTRACT_TOKEN before starting the worker")
    ThreadingHTTPServer(("0.0.0.0", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
