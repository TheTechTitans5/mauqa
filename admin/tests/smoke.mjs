// Headless browser smoke test for the admin dashboard against a mock Supabase API.
// Run: node admin/tests/smoke.mjs   (requires `playwright` with Chromium installed)
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require('/opt/npm-tools/node_modules/playwright')); }

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
let roles = ['admin'];
const calls = [];
const opp = { id: '11111111-1111-4111-8111-111111111111', title: '[DEMO] Indus Scholarship', deadline: '2026-12-15T18:59:00Z', verification_status: 'pending_verification',
  approval_status: 'pending_review', is_published: false, is_featured: false, is_demo: true, is_reported: false, organizations: { name: '[DEMO] Indus Future Foundation', official_domains: ['example.org'] },
  organization_id: 'o1', category_id: 'c1', source_url: 'https://example.org/s', official_application_url: 'https://example.org/apply', provinces: [], cities: [],
  education_levels: ['bachelor'], fields_of_study: [], required_skills: [], tags: [], funding_type: 'fully_funded', work_mode: 'not_applicable', gender_eligibility: 'any',
  is_nationwide: true, status: 'open', has_application_fee: false };

function api(req, res, body) {
  const url = new URL(req.url, 'http://x');
  calls.push(`${req.method} ${url.pathname}`);
  const json = (v, status = 200) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(v)); };
  if (url.pathname === '/auth/v1/token') {
    const b = JSON.parse(body || '{}');
    if (b.password !== 'correct-horse') return json({ error_description: 'Invalid login credentials' }, 400);
    return json({ access_token: 'jwt', refresh_token: 'r', expires_in: 3600, user: { id: 'admin-1', email: b.email } });
  }
  if (req.headers.authorization !== 'Bearer jwt') return json({ message: 'JWT required' }, 401);
  const rpc = url.pathname.replace('/rest/v1/rpc/', '');
  if (rpc === 'my_roles') return json(roles);
  if (rpc === 'admin_dashboard_stats') return json({ total_users: 42, verified: 3, pending: 2, reported: 1, sources: [{ name: 'HEC scholarship announcements', status: 'awaiting_authorization', enabled: false, failures: 0 }], recent_activity: [] });
  if (rpc === 'admin_analytics') return json({ users_by_category: { student: 30, graduate: 12 }, popular_categories: [{ category: 'scholarships', views: 9 }], most_viewed: [{ title: 'X', count: 3 }], source_reliability: [], applications_by_status: {}, verification: { verified: 3 }, signups_by_week: [] });
  const table = url.pathname.replace('/rest/v1/', '');
  if (table === 'opportunities') return json([opp]);
  if (table === 'data_sources') return json([{ id: 's1', name: 'HEC scholarship announcements', source_type: 'web_monitor', integration_status: 'awaiting_authorization', is_enabled: false, config: {}, authorization_notes: 'No public API confirmed', sync_interval_minutes: 1440, rate_limit_per_minute: 6, consecutive_failures: 0 }]);
  if (table === 'profiles') return json([{ id: 'u1', full_name: 'Test User', email: 't@example.com', is_suspended: false, created_at: '2026-11-01T00:00:00Z' }]);
  if (table === 'user_roles') return json([{ user_id: 'u1', role: 'user' }]);
  if (table === 'opportunity_categories') return json([{ id: 'c1', slug: 'scholarships', name_en: 'Scholarships', name_ur: 'وظائف', sort_order: 1 }]);
  if (table === 'organizations') return json([{ id: 'o1', name: '[DEMO] Indus Future Foundation', official_domains: ['example.org'], org_type: 'ngo' }]);
  return json([]);
}

const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    if (req.url.startsWith('/auth/') || req.url.startsWith('/rest/') || req.url.startsWith('/functions/')) return api(req, res, body);
    const p = req.url === '/' ? '/index.html' : req.url.split('?')[0];
    if (p === '/config.js') {
      res.writeHead(200, { 'Content-Type': 'text/javascript' });
      return res.end(`window.MAUQA_ADMIN_CONFIG = { supabaseUrl: 'http://127.0.0.1:${server.address().port}', anonKey: 'anon' };`);
    }
    const file = path.join(root, p);
    if (!file.startsWith(root) || !fs.existsSync(file)) { res.writeHead(404); return res.end(); }
    const type = file.endsWith('.js') ? 'text/javascript' : file.endsWith('.css') ? 'text/css' : 'text/html';
    res.writeHead(200, { 'Content-Type': type });
    fs.createReadStream(file).pipe(res);
  });
});

await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch();
const errors = [];
let failures = 0;
const check = (cond, msg) => { if (!cond) { failures++; console.error('FAIL:', msg); } else console.log('ok  ', msg); };

try {
  const page = await browser.newPage();
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !/401|400/.test(m.text())) errors.push(m.text()); });
  await page.goto(base);
  await page.fill('input[type=email]', 'admin@example.com');
  await page.fill('input[type=password]', 'wrong');
  await page.click('button[type=submit]');
  await page.waitForSelector('.toast.error');
  check((await page.textContent('.toast.error')).includes('Invalid login'), 'wrong password shows an error');
  await page.fill('input[type=password]', 'correct-horse');
  await page.click('button[type=submit]');
  await page.waitForSelector('.stats');
  check((await page.textContent('main')).includes('42'), 'dashboard shows stats from admin_dashboard_stats');
  for (const [hash, expected] of [['opportunities', 'Indus Scholarship'], ['review', 'awaiting verification'], ['sources', 'No public API confirmed'],
    ['moderation', 'scam reports'], ['users', 'Test User'], ['content', 'Organisations'], ['analytics', 'Users by category']]) {
    await page.goto(`${base}#/${hash}`);
    await page.waitForFunction((t) => document.querySelector('main')?.textContent?.includes(t), expected, { timeout: 5000 }).catch(() => {});
    check((await page.textContent('main')).includes(expected), `#/${hash} renders "${expected}"`);
  }
  await page.goto(`${base}#/opportunities`);
  await page.waitForSelector('text=Edit');
  await page.click('text=Edit');
  await page.waitForSelector('.modal');
  check(await page.isVisible('text=Eligibility rules'), 'opportunity editor opens with rules/docs/verify actions');
  await page.click('.modal button:has-text("Eligibility rules")');
  await page.waitForSelector('text=Save rules');
  check(await page.isVisible('text=+ condition'), 'rule editor renders');
  const xss = await page.evaluate(() => document.querySelectorAll('script:not([src])').length);
  check(xss === 0, 'no inline scripts injected');

  // non-staff users are refused
  roles = ['user'];
  const p2 = await browser.newPage();
  await p2.goto(base);
  await p2.fill('input[type=email]', 'user@example.com');
  await p2.fill('input[type=password]', 'correct-horse');
  await p2.click('button[type=submit]');
  await p2.waitForSelector('.toast.error');
  check((await p2.textContent('.toast.error')).includes('staff access'), 'non-staff account is rejected');
  check(!(await p2.isVisible('nav')), 'no admin navigation for non-staff');
} finally {
  await browser.close();
  server.close();
}
check(errors.length === 0, `no JavaScript errors (${errors.join(' | ')})`);
console.log(failures ? `\n${failures} smoke check(s) failed` : '\nADMIN SMOKE TEST PASSED');
process.exit(failures ? 1 : 0);
