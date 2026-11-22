// Dependency-free extraction helpers used by RSS / website / PDF connectors.
// Output is always a *suggestion* that goes to the human review queue.

const ENTITIES: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '–', mdash: '—', rsquo: '’', lsquo: '‘' };

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e: string) => {
    if (e[0] === '#') {
      const code = e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : m;
    }
    return ENTITIES[e.toLowerCase()] ?? m;
  });
}

export function htmlToText(html: string): string {
  return decodeEntities(
    html.replace(/<(script|style|noscript)[\s\S]*?<\/\1>/gi, ' ')
      .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
      .replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h[1-6]|tr)>/gi, '\n')
      .replace(/<[^>]+>/g, ' '),
  ).replace(/[ \t\f\v]+/g, ' ').replace(/\s*\n\s*/g, '\n').trim();
}

export interface ExtractedLink { href: string; text: string }

export function extractLinks(html: string, baseUrl: string): ExtractedLink[] {
  const out: ExtractedLink[] = [];
  const re = /<a\b[^>]*?href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>([\s\S]*?)<\/a>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html))) {
    const raw = decodeEntities((m[1] ?? m[2] ?? m[3] ?? '').trim());
    if (!raw || raw.startsWith('#') || /^(javascript|mailto|tel):/i.test(raw)) continue;
    try { out.push({ href: new URL(raw, baseUrl).toString(), text: htmlToText(m[4]).replace(/\s+/g, ' ').trim() }); } catch { /* skip */ }
  }
  return out;
}

export interface FeedEntry { id: string; title: string; link: string; published?: string; summary: string }

function tag(xml: string, name: string): string | null {
  const m = new RegExp(`<${name}\\b[^>]*>([\\s\\S]*?)<\\/${name}>`, 'i').exec(xml);
  return m ? m[1].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').trim() : null;
}

/** Parses RSS 2.0 <item> and Atom <entry> elements. */
export function parseFeed(xml: string): FeedEntry[] {
  const blocks = xml.match(/<item\b[\s\S]*?<\/item>/gi) ?? xml.match(/<entry\b[\s\S]*?<\/entry>/gi) ?? [];
  return blocks.map((b) => {
    const atomLink = /<link\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*\/?>/i.exec(b)?.[1];
    const link = decodeEntities(tag(b, 'link') || atomLink || '');
    const title = htmlToText(decodeEntities(tag(b, 'title') ?? ''));
    const id = decodeEntities(tag(b, 'guid') ?? tag(b, 'id') ?? link ?? title);
    const summary = htmlToText(decodeEntities(tag(b, 'description') ?? tag(b, 'summary') ?? tag(b, 'content') ?? ''));
    const published = tag(b, 'pubDate') ?? tag(b, 'published') ?? tag(b, 'updated') ?? undefined;
    return { id, title, link, published, summary };
  }).filter((e) => e.title || e.link);
}

const MONTHS: Record<string, number> = {
  jan: 0, january: 0, feb: 1, february: 1, mar: 2, march: 2, apr: 3, april: 3, may: 4, jun: 5, june: 5,
  jul: 6, july: 6, aug: 7, august: 7, sep: 8, sept: 8, september: 8, oct: 9, october: 9, nov: 10, november: 10, dec: 11, december: 11,
};

/** Builds an ISO timestamp for 23:59 Pakistan time (UTC+5) on the given calendar date. */
function pktEndOfDay(y: number, m: number, d: number): string | null {
  if (y < 2000 || y > 2100 || m < 0 || m > 11 || d < 1 || d > 31) return null;
  const dt = new Date(Date.UTC(y, m, d, 23 - 5, 59, 0));
  return dt.getUTCDate() === d || dt.getUTCDate() === d ? dt.toISOString() : null;
}

/** Parses common Pakistani announcement date formats; returns ISO (23:59 PKT) or null. */
export function parseLooseDate(s: string): string | null {
  const t = s.trim().replace(/(\d)(st|nd|rd|th)\b/gi, '$1').replace(/,/g, ' ').replace(/\s+/g, ' ');
  let m = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(t);
  if (m) return pktEndOfDay(+m[1], +m[2] - 1, +m[3]);
  m = /^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$/.exec(t); // day-first, as used in Pakistan
  if (m) return pktEndOfDay(+m[3], +m[2] - 1, +m[1]);
  m = /^(\d{1,2})[ -]([a-z]+)[ -](\d{4})$/i.exec(t);
  if (m && MONTHS[m[2].toLowerCase()] !== undefined) return pktEndOfDay(+m[3], MONTHS[m[2].toLowerCase()], +m[1]);
  m = /^([a-z]+) (\d{1,2}) (\d{4})$/i.exec(t);
  if (m && MONTHS[m[1].toLowerCase()] !== undefined) return pktEndOfDay(+m[3], MONTHS[m[1].toLowerCase()], +m[2]);
  return null;
}

const DATE_RE = '(\\d{4}-\\d{1,2}-\\d{1,2}|\\d{1,2}[./-]\\d{1,2}[./-]\\d{4}|\\d{1,2}(?:st|nd|rd|th)?[ -](?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*,?[ -]\\d{4}|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]* \\d{1,2}(?:st|nd|rd|th)?,? \\d{4})';

/** Finds a deadline introduced by typical phrasing ("Last date", "Deadline", "Apply by", "Closing date"). */
export function findDeadline(text: string): string | null {
  const re = new RegExp(`(?:last\\s+date(?:\\s+(?:to|for)\\s+(?:apply|submission|applications?))?|deadline|apply\\s+(?:by|before)|closing\\s+date|due\\s+date)\\s*(?:is|:|-|–)?\\s*(?:on\\s+)?${DATE_RE}`, 'i');
  const m = re.exec(text);
  return m ? parseLooseDate(m[1]) : null;
}

export function findAmountPkr(text: string): number | null {
  const m = /(?:rs\.?|pkr)\s*([\d,]{3,12})(?:\s*\/-)?/i.exec(text);
  if (!m) return null;
  const n = Number(m[1].replace(/,/g, ''));
  return Number.isFinite(n) ? n : null;
}
