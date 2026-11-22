// RSS, authorised website monitoring, official PDF and manual connectors.
import { findAmountPkr, findDeadline, htmlToText, extractLinks, parseFeed } from '../textExtract.ts';
import { PoliteFetcher } from './politeFetch.ts';
import type { Connector, DataSourceRow, RawItem } from './types.ts';
import { ConnectorConfigError } from './types.ts';
import { env } from '../env.ts';

function requireHttps(u: unknown, field: string): string {
  if (typeof u !== 'string' || !u) throw new ConnectorConfigError(`config.${field} is required`);
  const url = new URL(u);
  if (url.protocol !== 'https:') throw new ConnectorConfigError(`config.${field} must use HTTPS`);
  return url.toString();
}

function assertAuthorised(source: DataSourceRow) {
  if (!source.terms_reviewed_at) {
    throw new ConnectorConfigError('Website terms of use have not been reviewed. Record terms_reviewed_at before enabling monitoring.');
  }
}

export const rssConnector: Connector = {
  validateConfig(source) {
    requireHttps((source.config as { feed_url?: string }).feed_url, 'feed_url');
  },
  async fetchItems(source, ctx) {
    this.validateConfig(source);
    const feedUrl = (source.config as { feed_url: string }).feed_url;
    const http = new PoliteFetcher(ctx, { ratePerMinute: source.rate_limit_per_minute, respectRobots: true });
    const xml = await (await http.get(feedUrl, 'application/rss+xml,application/atom+xml,application/xml,text/xml')).text();
    const entries = parseFeed(xml);
    return entries.map((e): RawItem => {
      const text = `${e.title}\n${e.summary}`;
      return {
        externalId: e.id || e.link,
        url: e.link || null,
        raw: { ...e },
        draft: {
          title: e.title,
          summary: e.summary.slice(0, 500) || null,
          description: e.summary || null,
          source_url: e.link || null,
          official_application_url: null, // must be confirmed by a reviewer
          deadline: findDeadline(text),
          amount_min_pkr: findAmountPkr(text),
        },
      };
    });
  },
};

interface WebConfig {
  list_url: string;
  link_include?: string[];        // substrings a detail link must contain (e.g. "/scholarship")
  link_text_include?: string[];   // keywords in anchor text
  same_host_only?: boolean;
  fetch_details?: boolean;
  max_items?: number;
}

export const webMonitorConnector: Connector = {
  validateConfig(source) {
    assertAuthorised(source);
    const c = source.config as Partial<WebConfig>;
    requireHttps(c.list_url, 'list_url');
    if (!c.link_include?.length && !c.link_text_include?.length) {
      throw new ConnectorConfigError('Configure link_include or link_text_include so only relevant announcement links are followed.');
    }
    if (!env('BOT_CONTACT')) throw new ConnectorConfigError('Set BOT_CONTACT so site owners can identify and contact the monitor.');
  },
  async fetchItems(source, ctx) {
    this.validateConfig(source);
    const c = source.config as unknown as WebConfig;
    const http = new PoliteFetcher(ctx, { ratePerMinute: Math.min(source.rate_limit_per_minute, 10), respectRobots: true });
    const listHtml = await (await http.get(c.list_url)).text();
    PoliteFetcher.assertNotGated(listHtml, c.list_url);
    const listHost = new URL(c.list_url).hostname;
    const seen = new Set<string>();
    const links = extractLinks(listHtml, c.list_url).filter((l) => {
      if (seen.has(l.href)) return false;
      seen.add(l.href);
      if ((c.same_host_only ?? true) && new URL(l.href).hostname !== listHost) return false;
      const byHref = c.link_include?.some((s) => l.href.toLowerCase().includes(s.toLowerCase())) ?? false;
      const byText = c.link_text_include?.some((s) => l.text.toLowerCase().includes(s.toLowerCase())) ?? false;
      return byHref || byText;
    }).slice(0, Math.min(c.max_items ?? 25, 100));

    const items: RawItem[] = [];
    for (const l of links) {
      let text = l.text;
      let isPdf = /\.pdf($|\?)/i.test(l.href);
      if (c.fetch_details && !isPdf) {
        const res = await http.get(l.href);
        isPdf = (res.headers.get('content-type') ?? '').includes('pdf');
        if (!isPdf) {
          const html = await res.text();
          PoliteFetcher.assertNotGated(html, l.href);
          text = htmlToText(html).slice(0, 20_000);
        }
      }
      items.push({
        externalId: l.href,
        url: l.href,
        raw: { anchor_text: l.text, is_pdf: isPdf, excerpt: text.slice(0, 2000) },
        draft: {
          title: l.text.slice(0, 240),
          description: text !== l.text ? text.slice(0, 8000) : null,
          source_url: l.href,
          official_application_url: null,
          deadline: findDeadline(text),
          amount_min_pkr: findAmountPkr(text),
        },
      });
    }
    ctx.log(`web: ${items.length} candidate links from ${source.name}`);
    return items;
  },
};

/**
 * Official PDF announcements. Edge Functions do not run OCR, so text extraction is delegated to the
 * optional Python worker (workers/ingest_worker.py) when PDF_EXTRACT_URL is configured. Without it, the PDF is
 * still tracked (hash/change detection) and queued for manual extraction by a reviewer.
 */
export const pdfConnector: Connector = {
  validateConfig(source) {
    const urls = (source.config as { pdf_urls?: unknown }).pdf_urls;
    if (!Array.isArray(urls) || urls.length === 0) throw new ConnectorConfigError('config.pdf_urls must list official PDF URLs');
    urls.forEach((u, i) => requireHttps(u, `pdf_urls[${i}]`));
  },
  async fetchItems(source, ctx) {
    this.validateConfig(source);
    const urls = (source.config as { pdf_urls: string[]; ocr?: boolean }).pdf_urls;
    const ocr = Boolean((source.config as { ocr?: boolean }).ocr);
    const http = new PoliteFetcher(ctx, { ratePerMinute: source.rate_limit_per_minute, respectRobots: true });
    const worker = env('PDF_EXTRACT_URL');
    const items: RawItem[] = [];
    for (const url of urls) {
      const res = await http.get(url, 'application/pdf');
      const bytes = new Uint8Array(await res.arrayBuffer());
      const digest = await crypto.subtle.digest('SHA-256', bytes);
      const sha = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
      let text = '';
      if (worker) {
        const r = await ctx.fetch(worker, {
          method: 'POST',
          headers: { 'Content-Type': 'application/pdf', 'X-Worker-Token': env('PDF_EXTRACT_TOKEN') ?? '', 'X-OCR': ocr ? '1' : '0' },
          body: bytes,
        });
        if (r.ok) text = ((await r.json()) as { text?: string }).text ?? '';
        else ctx.log(`pdf worker failed for ${url}: ${r.status}`);
      }
      const firstLine = text.split('\n').map((s) => s.trim()).find((s) => s.length > 10) ?? decodeURIComponent(url.split('/').pop() ?? 'PDF announcement');
      items.push({
        externalId: url,
        url,
        raw: { sha256: sha, bytes: bytes.length, extracted: Boolean(text), excerpt: text.slice(0, 3000) },
        draft: {
          title: firstLine.slice(0, 240),
          description: text ? text.slice(0, 8000) : null,
          source_url: url,
          official_application_url: null,
          deadline: text ? findDeadline(text) : null,
          amount_min_pkr: text ? findAmountPkr(text) : null,
        },
      });
    }
    return items;
  },
};

export const manualConnector: Connector = {
  validateConfig() { /* nothing to configure */ },
  async fetchItems() { return []; },
};
