// robots.txt support: connectors must check this before fetching any page.

import { env } from './env.ts';

/** Identifies the bot honestly. Set BOT_CONTACT (an email or URL you control) before enabling any monitor. */
export function userAgent(): string {
  return `MauqaBot/1.0 (opportunity verification; contact: ${env('BOT_CONTACT') ?? 'not-configured'})`;
}

interface Group { agents: string[]; allow: string[]; disallow: string[]; crawlDelay?: number }

export function parseRobots(txt: string): Group[] {
  const groups: Group[] = [];
  let cur: Group | null = null;
  let lastWasAgent = false;
  for (const rawLine of txt.split(/\r?\n/)) {
    const line = rawLine.replace(/#.*$/, '').trim();
    if (!line) continue;
    const idx = line.indexOf(':');
    if (idx < 0) continue;
    const key = line.slice(0, idx).trim().toLowerCase();
    const val = line.slice(idx + 1).trim();
    if (key === 'user-agent') {
      if (!cur || !lastWasAgent) { cur = { agents: [], allow: [], disallow: [] }; groups.push(cur); }
      cur.agents.push(val.toLowerCase());
      lastWasAgent = true;
      continue;
    }
    lastWasAgent = false;
    if (!cur) continue;
    if (key === 'allow') cur.allow.push(val);
    else if (key === 'disallow') cur.disallow.push(val);
    else if (key === 'crawl-delay') cur.crawlDelay = Number(val) || undefined;
  }
  return groups;
}

function ruleMatch(rule: string, path: string): number {
  if (!rule) return -1;
  const anchored = rule.endsWith('$');
  const pattern = '^' + rule.replace(/\$$/, '').split('*').map((s) => s.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('.*') + (anchored ? '$' : '');
  return new RegExp(pattern).test(path) ? rule.length : -1;
}

export function isAllowed(groups: Group[], url: string, agent = 'mauqabot'): { allowed: boolean; crawlDelay?: number } {
  const u = new URL(url);
  const path = u.pathname + u.search;
  const a = agent.toLowerCase();
  const g = groups.find((x) => x.agents.some((n) => n !== '*' && a.includes(n))) ?? groups.find((x) => x.agents.includes('*'));
  if (!g) return { allowed: true };
  const bestAllow = Math.max(-1, ...g.allow.map((r) => ruleMatch(r, path)));
  const bestDis = Math.max(-1, ...g.disallow.map((r) => ruleMatch(r, path)));
  return { allowed: bestAllow >= bestDis, crawlDelay: g.crawlDelay };
}
