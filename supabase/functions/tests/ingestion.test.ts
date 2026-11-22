import { test } from 'node:test';
import assert from 'node:assert/strict';
import { contentHash, diffDrafts, duplicateScore, findDuplicate } from '../_shared/dedupe.ts';
import { findAmountPkr, findDeadline, extractLinks, htmlToText, parseFeed, parseLooseDate } from '../_shared/textExtract.ts';
import { analyzeLink, analyzeText } from '../_shared/linkSafety.ts';
import { isAllowed, parseRobots } from '../_shared/robots.ts';
import { validateDraft, hasBlockingIssue } from '../_shared/validate.ts';

test('deadline phrases common in Pakistani announcements', () => {
  // 23:59 PKT = 18:59 UTC
  assert.equal(findDeadline('Last date to apply: 15 December 2026'), '2026-12-15T18:59:00.000Z');
  assert.equal(findDeadline('The deadline is 05-01-2027.'), '2027-01-05T18:59:00.000Z');
  assert.equal(findDeadline('Apply by Jan 31st, 2027 via the portal'), '2027-01-31T18:59:00.000Z');
  assert.equal(findDeadline('Closing date – 2027-02-28'), '2027-02-28T18:59:00.000Z');
  assert.equal(findDeadline('No date mentioned here'), null);
  assert.equal(parseLooseDate('31-02-2027'), null, 'invalid calendar date rejected');
});

test('amount extraction', () => {
  assert.equal(findAmountPkr('Monthly stipend of Rs. 25,000/- will be paid'), 25000);
  assert.equal(findAmountPkr('PKR 1,500,000 grant'), 1500000);
  assert.equal(findAmountPkr('no money'), null);
});

test('RSS and Atom parsing', () => {
  const rss = `<?xml version="1.0"?><rss><channel><item><title><![CDATA[Fall Scholarship &amp; Grant]]></title>
    <link>https://www.example.gov.pk/a</link><guid>a-1</guid><description>&lt;p&gt;Last date: 10 Jan 2027&lt;/p&gt;</description>
    <pubDate>Mon, 02 Nov 2026 10:00:00 GMT</pubDate></item></channel></rss>`;
  const [e] = parseFeed(rss);
  assert.equal(e.title, 'Fall Scholarship & Grant');
  assert.equal(e.id, 'a-1');
  assert.match(e.summary, /Last date: 10 Jan 2027/);
  const atom = `<feed><entry><title>Atom item</title><link href="https://x.edu.pk/b"/><id>tag:b</id><summary>Hello</summary></entry></feed>`;
  assert.deepEqual(parseFeed(atom).map((x) => [x.title, x.link, x.id]), [['Atom item', 'https://x.edu.pk/b', 'tag:b']]);
});

test('HTML helpers', () => {
  const html = `<html><script>evil()</script><h1>Title</h1><p>One&nbsp;two</p><a href="/s/1">Scholarship 1</a><a href="mailto:x@y">mail</a><a href='https://other.org/x'>Other</a></html>`;
  assert.equal(htmlToText(html), 'Title\nOne two\nScholarship 1 mail Other');
  assert.deepEqual(extractLinks(html, 'https://site.gov.pk/list').map((l) => l.href), ['https://site.gov.pk/s/1', 'https://other.org/x']);
});

test('duplicate detection', () => {
  const a = { title: 'HEC Need Based Scholarship 2026', organization_id: 'o1', deadline: '2026-12-15T18:59:00Z' };
  const b = { title: 'Need-based scholarship (HEC) – applications invited', organization_id: 'o1', deadline: '2026-12-15T18:59:00Z' };
  const c = { title: 'Summer internship programme', organization_id: 'o1', deadline: '2026-12-15T18:59:00Z' };
  assert.ok(duplicateScore(a, b) >= 0.8, `similar listings should match (${duplicateScore(a, b)})`);
  assert.ok(duplicateScore(a, c) < 0.5);
  assert.equal(duplicateScore({ title: 'x', official_application_url: 'https://www.a.pk/apply?utm_source=fb' }, { title: 'y', official_application_url: 'https://a.pk/apply/' }), 1);
  assert.equal(findDuplicate(a, [{ id: '1', ...c }, { id: '2', ...b }])?.match.id, '2');
});

test('content hash is stable and whitespace-insensitive; diff lists changed fields', async () => {
  const h1 = await contentHash({ title: 'A  title', deadline: '2026-12-01' });
  const h2 = await contentHash({ title: 'A title', deadline: '2026-12-01' });
  const h3 = await contentHash({ title: 'A title', deadline: '2026-12-02' });
  assert.equal(h1, h2);
  assert.notEqual(h1, h3);
  assert.deepEqual(Object.keys(diffDrafts({ title: 'A', deadline: '1' }, { title: 'A', deadline: '2' })), ['deadline']);
});

test('link safety flags but does not accuse', () => {
  assert.equal(analyzeLink('https://www.hec.gov.pk/apply', ['hec.gov.pk']).level, 'ok');
  assert.equal(analyzeLink('https://portal.hec.gov.pk/x', ['hec.gov.pk']).level, 'ok');
  assert.equal(analyzeLink('https://hec-gov.pk.example.com/x', ['hec.gov.pk']).level, 'caution');
  assert.equal(analyzeLink('https://hecc.gov.pk/x', ['hec.gov.pk']).level, 'warning');
  assert.equal(analyzeLink('https://bit.ly/abc').level, 'caution');
  assert.equal(analyzeLink('https://wa.me/923001234567').level, 'warning');
  assert.equal(analyzeLink('http://193.1.1.1/apply').level, 'warning');
  assert.equal(analyzeLink(null).level, 'caution');
  assert.equal(analyzeText('Pay registration fee via JazzCash to guarantee selection').level, 'warning');
  assert.equal(analyzeText('Fully funded, no fee').level, 'ok');
});

test('robots.txt', () => {
  const g = parseRobots('User-agent: *\nDisallow: /admin\nAllow: /admin/public\n\nUser-agent: MauqaBot\nDisallow: /private\nCrawl-delay: 5');
  assert.equal(isAllowed(g, 'https://x.pk/private/a').allowed, false);
  assert.equal(isAllowed(g, 'https://x.pk/admin').allowed, true, 'specific group overrides *');
  assert.equal(isAllowed(g, 'https://x.pk/admin', 'otherbot').allowed, false);
  assert.equal(isAllowed(g, 'https://x.pk/admin/public/p', 'otherbot').allowed, true, 'longest match wins');
  assert.equal(isAllowed(g, 'https://x.pk/a').crawlDelay, 5);
  assert.equal(isAllowed(parseRobots('User-agent: *\nDisallow: /*.pdf$'), 'https://x.pk/a/b.pdf').allowed, false);
});

test('validation of drafts', () => {
  const now = new Date('2026-11-21T00:00:00Z');
  const good = validateDraft({ title: 'Merit scholarship', source_url: 'https://www.hec.gov.pk/s', official_application_url: 'https://portal.hec.gov.pk/a',
    deadline: '2026-12-20T18:59:00Z', eligibility_summary: 'x' }, ['hec.gov.pk'], now);
  assert.equal(hasBlockingIssue(good), false);
  const bad = validateDraft({ title: 'x', source_url: 'https://random.blogspot.com/p', official_application_url: 'https://bit.ly/1',
    deadline: '2026-01-01T00:00:00Z', description: 'send money via easypaisa processing fee' }, ['hec.gov.pk'], now);
  const codes = bad.map((i) => i.code);
  ['title_missing', 'source_not_official', 'apply_link_flag', 'deadline_past', 'payment_language'].forEach((c) => assert.ok(codes.includes(c), c));
  assert.equal(hasBlockingIssue(bad), true);
});
