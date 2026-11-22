// Cautious link and text checks. Produces warnings — never a claim that something IS fraudulent.

export type SafetyLevel = 'ok' | 'caution' | 'warning';
export interface SafetyReport { level: SafetyLevel; flags: string[] }

const SHORTENERS = new Set(['bit.ly', 'tinyurl.com', 'goo.gl', 't.co', 'cutt.ly', 'rb.gy', 'shorturl.at', 'is.gd', 'ow.ly', 'buff.ly', 'tiny.cc', 'rebrand.ly']);
const MESSAGING = ['wa.me', 'chat.whatsapp.com', 't.me', 'api.whatsapp.com'];
const FREE_HOSTS = ['blogspot.com', 'wordpress.com', 'wixsite.com', 'weebly.com', 'sites.google.com', 'forms.gle', 'docs.google.com', 'netlify.app', 'vercel.app'];
const PAYMENT_PATTERNS: Array<[RegExp, string]> = [
  [/\b(processing|registration|application|verification|security)\s+(fee|charges?)\b/i, 'Mentions an application or processing fee'],
  [/\b(jazz\s?cash|easy\s?paisa|sadapay|nayapay)\b/i, 'Asks for payment through a mobile wallet'],
  [/\b(send|transfer|deposit)\s+(rs\.?|pkr|rupees|money|amount)/i, 'Asks you to send money'],
  [/\bguarantee(d)?\s+(selection|job|admission|visa|scholarship)\b/i, 'Promises guaranteed selection'],
  [/\b(pin|otp|password)\b.{0,30}\b(share|send|provide)\b|\b(share|send|provide)\b.{0,30}\b(pin|otp|password)\b/i, 'Asks for a PIN, OTP or password'],
];

export function hostOf(url: string): string | null {
  try { return new URL(url).hostname.toLowerCase().replace(/^www\./, ''); } catch { return null; }
}

export function domainMatches(host: string, domain: string): boolean {
  const d = domain.toLowerCase().replace(/^www\./, '');
  return host === d || host.endsWith('.' + d);
}

function levenshtein(a: string, b: string): number {
  const dp = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) dp[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      dp[i][j] = Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
  }
  return dp[a.length][b.length];
}

export function analyzeLink(url: string | null | undefined, officialDomains: string[] = []): SafetyReport {
  const flags: string[] = [];
  if (!url) return { level: 'caution', flags: ['No official link provided'] };
  let u: URL;
  try { u = new URL(url); } catch { return { level: 'warning', flags: ['Link is not a valid web address'] }; }
  const host = u.hostname.toLowerCase().replace(/^www\./, '');
  if (u.protocol !== 'https:') flags.push('Link is not secure (no HTTPS)');
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.includes(':')) flags.push('Link uses a raw IP address');
  if (host.split('.').some((p) => p.startsWith('xn--'))) flags.push('Link uses look-alike (punycode) characters');
  if (SHORTENERS.has(host)) flags.push('Shortened link hides the real destination');
  if (MESSAGING.some((m) => domainMatches(host, m))) flags.push('Link opens a messaging chat instead of an official website');
  if (FREE_HOSTS.some((f) => domainMatches(host, f))) flags.push('Hosted on a free website or form builder');
  if (u.username || u.password) flags.push('Link contains embedded credentials');

  if (officialDomains.length) {
    const official = officialDomains.some((d) => domainMatches(host, d));
    if (!official) {
      flags.push('Destination is not on the organisation\'s official domain');
      const base = host.split('.').slice(-3).join('.');
      if (officialDomains.some((d) => { const dist = levenshtein(base, d.toLowerCase()); return dist > 0 && dist <= 2; })) {
        flags.push('Domain looks similar to the official domain');
      }
    }
  }
  const severe = flags.some((f) => /look-alike|similar|raw IP|credentials|messaging|not a valid/.test(f));
  return { level: severe ? 'warning' : flags.length ? 'caution' : 'ok', flags };
}

export function analyzeText(text: string | null | undefined): SafetyReport {
  const flags = PAYMENT_PATTERNS.filter(([re]) => re.test(text ?? '')).map(([, f]) => f);
  return { level: flags.length >= 2 ? 'warning' : flags.length ? 'caution' : 'ok', flags };
}

export function isGovOrEduDomain(host: string): boolean {
  return /\.(gov|edu)\.pk$/.test(host) || host.endsWith('.gop.pk');
}
