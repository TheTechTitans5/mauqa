"""Tests for the ingestion worker. Run: python3 -m unittest workers/test_ingest_worker.py"""
import json
import os
import sys
import threading
import unittest
import urllib.request
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(__file__))
import ingest_worker as w  # noqa: E402


def make_pdf(text: str) -> bytes:
    """Builds a tiny valid one-page PDF with a text layer (correct xref offsets)."""
    stream = f"BT /F1 12 Tf 72 720 Td ({text}) Tj ET".encode()
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, body in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer << /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)


class WorkerTests(unittest.TestCase):
    def test_pdf_text_extraction(self):
        r = w.extract_pdf_text(make_pdf("Merit Scholarship. Last date: 15 December 2026"))
        self.assertEqual(r["pages"], 1)
        self.assertIn("Last date: 15 December 2026", r["text"])
        self.assertFalse(r["ocr_used"])

    def test_rejects_non_pdf(self):
        with self.assertRaises(ValueError):
            w.extract_pdf_text(b"<html>not a pdf</html>")

    def test_gating_detection(self):
        with self.assertRaises(w.BlockedError):
            w.assert_not_gated('<div class="g-recaptcha"></div>', "https://x")
        with self.assertRaises(w.BlockedError):
            w.assert_not_gated('<form><input type="password" name="p"></form>', "https://x")
        w.assert_not_gated("<p>Public announcement</p>", "https://x")

    def test_monitor_page_filters_links(self):
        html = """<ul id="news"><li><a href="/sch/fall-2026">Fall Scholarship</a></li>
                  <li><a href="/about">About</a></li><li><a href="https://elsewhere.com/sch/x">External</a></li>
                  <li><a href="/files/ad.pdf">Scholarship advertisement (PDF)</a></li></ul>"""
        links = w.monitor_page(html, "https://www.example.gov.pk/list", ["/sch/", "scholarship"], "#news")
        self.assertEqual([l["url"] for l in links], ["https://www.example.gov.pk/sch/fall-2026", "https://www.example.gov.pk/files/ad.pdf"])
        self.assertTrue(links[1]["is_pdf"])

    def test_http_requires_token(self):
        os.environ["PDF_EXTRACT_TOKEN"] = "t0k3n"
        srv = ThreadingHTTPServer(("127.0.0.1", 0), w.Handler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{srv.server_address[1]}/extract-pdf"
        pdf = make_pdf("Deadline: 01-02-2027")
        try:
            bad = urllib.request.Request(url, data=pdf, headers={"X-Worker-Token": "nope"}, method="POST")
            with self.assertRaises(urllib.error.HTTPError) as cm:
                urllib.request.urlopen(bad)
            self.assertEqual(cm.exception.code, 401)
            ok = urllib.request.Request(url, data=pdf, headers={"X-Worker-Token": "t0k3n"}, method="POST")
            body = json.loads(urllib.request.urlopen(ok).read())
            self.assertIn("01-02-2027", body["text"])
        finally:
            srv.shutdown()


if __name__ == "__main__":
    unittest.main()
