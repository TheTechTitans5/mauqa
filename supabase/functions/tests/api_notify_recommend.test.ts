import { test } from 'node:test';
import assert from 'node:assert/strict';
import { apiPath, dispatchApi, matchRoute } from '../_shared/apiRouter.ts';
import { HttpError, RateLimiter, safeEqual } from '../_shared/http.ts';
import { Rest } from '../_shared/rest.ts';
import { channelsFor, EmailChannel, FcmChannel, inQuietHours, signServiceAccountJwt, type Prefs } from '../_shared/notify.ts';
import { recommend } from '../_shared/recommend.ts';
import { checkEligibility } from '../_shared/services.ts';
import { readSecretRef } from '../_shared/env.ts';
import type { FeedRow, UserFacts } from '../_shared/types.ts';

const OPP = '0f0e0d0c-0b0a-4908-8706-050403020100';

test('API routing', () => {
  assert.equal(apiPath('https://x.supabase.co/functions/v1/api/opportunities/closing-soon'), '/opportunities/closing-soon');
  assert.equal(apiPath('http://localhost/api/'), '/');
  assert.ok(matchRoute('GET', '/opportunities'));
  assert.deepEqual(matchRoute('POST', `/opportunities/${OPP}/save`)?.params, { id: OPP });
  assert.ok(matchRoute('GET', '/opportunities/recommended'));
  assert.throws(() => matchRoute('PUT', '/applications'), (e: unknown) => e instanceof HttpError && e.status === 405);
  assert.equal(matchRoute('GET', '/nope'), null);
});

/** Fake Supabase: records calls and answers from fixtures. */
function fakeSupabase(fixtures: Record<string, unknown>, calls: Array<{ method: string; url: string; auth: string; body?: string }>) {
  return async (url: string, init?: RequestInit) => {
    const auth = (init?.headers as Record<string, string>)?.Authorization ?? '';
    calls.push({ method: init?.method ?? 'GET', url, auth, body: init?.body as string | undefined });
    if (url.endsWith('/auth/v1/user')) return auth.includes('bad') ? new Response('', { status: 401 }) : Response.json({ id: 'user-1' });
    const key = Object.keys(fixtures).find((k) => url.includes(k));
    return Response.json(key ? fixtures[key] : []);
  };
}

test('API: invalid session → 401; validation errors → 422', async () => {
  const calls: never[] = [];
  const mk = (token: string) => new Rest({ url: 'https://p.supabase.co', apiKey: 'anon', token, fetch: fakeSupabase({}, calls) });
  const deps = (t: string) => ({ user: mk(t), service: () => mk('service'), ctx: { fetch, sleep: async () => {}, log: () => {}, now: () => new Date() } });
  await assert.rejects(dispatchApi({ method: 'GET', path: '/applications', query: new URLSearchParams(), body: {}, token: 'bad' }, deps('bad')),
    (e: unknown) => e instanceof HttpError && e.status === 401);
  await assert.rejects(dispatchApi({ method: 'POST', path: '/applications', query: new URLSearchParams(), body: { status: 'hacked', custom_title: 'x' }, token: 't' }, deps('t')),
    (e: unknown) => e instanceof HttpError && e.status === 422);
  await assert.rejects(dispatchApi({ method: 'PATCH', path: `/notifications/${OPP}`, query: new URLSearchParams(), body: { is_read: 'yes' }, token: 't' }, deps('t')),
    (e: unknown) => e instanceof HttpError && e.status === 422);
});

test('API: save uses the caller token (RLS) and forces user_id to the caller', async () => {
  const calls: Array<{ method: string; url: string; auth: string; body?: string }> = [];
  const user = new Rest({ url: 'https://p.supabase.co', apiKey: 'anon', token: 'user-jwt', fetch: fakeSupabase({ saved_opportunities: [{ ok: 1 }] }, calls) });
  await dispatchApi({ method: 'POST', path: `/opportunities/${OPP}/save`, query: new URLSearchParams(), body: { user_id: 'someone-else' }, token: 'user-jwt' },
    { user, service: () => { throw new Error('service role must not be used'); }, ctx: { fetch, sleep: async () => {}, log: () => {}, now: () => new Date() } });
  const write = calls.find((c) => c.method === 'POST' && c.url.includes('saved_opportunities'))!;
  assert.equal(write.auth, 'Bearer user-jwt');
  assert.equal(JSON.parse(write.body!).user_id, 'user-1');
});

test('eligibility service: visibility checked with user token, result written with service role', async () => {
  const calls: Array<{ method: string; url: string; auth: string; body?: string }> = [];
  const fixtures = {
    'opportunity_feed': [{ id: OPP, deadline: null }],
    'opportunities?select=id,rules_version': [{ id: OPP, rules_version: 2 }],
    'opportunity_eligibility_rules': [{ id: 'r1', opportunity_id: OPP, parent_id: null, node_type: 'criterion', criterion_type: 'cgpa_min', params: { min: 3 }, label: 'CGPA 3+', is_mandatory: true, sort_order: 1 }],
    'eligibility_checks?select': [],
  };
  const f = fakeSupabase(fixtures, calls);
  const user = new Rest({ url: 'https://p', apiKey: 'anon', token: 'user-jwt', fetch: f });
  const service = new Rest({ url: 'https://p', apiKey: 'svc', token: 'svc', fetch: f });
  const facts: UserFacts = { userId: 'user-1', profileVersion: 4, shareSensitive: false, skills: [], interests: [], experiences: [], documentCategories: [],
    education: [{ level: 'bachelor', scoreType: 'cgpa', scoreValue: 3.4, scoreMax: 4, isCurrent: true }] };
  const [r] = await checkEligibility(user, service, 'user-1', [OPP], { facts });
  assert.equal(r.result.outcome, 'eligible');
  assert.equal(calls.find((c) => c.url.includes('opportunity_feed'))!.auth, 'Bearer user-jwt');
  const write = calls.find((c) => c.method === 'POST' && c.url.includes('eligibility_checks'))!;
  assert.equal(write.auth, 'Bearer svc');
  assert.match(write.url, /on_conflict=user_id%2Copportunity_id/);
  const body = JSON.parse(write.body!)[0];
  assert.deepEqual([body.profile_version, body.rules_version, body.is_stale], [4, 2, false]);
});

test('notification policy: quiet hours in PKT, channel selection', () => {
  const p: Prefs = { push_enabled: true, email_enabled: true, sms_enabled: false, whatsapp_enabled: false, quiet_hours_start: 22, quiet_hours_end: 7 };
  assert.equal(inQuietHours(p, new Date('2026-11-21T18:30:00Z')), true);   // 23:30 PKT
  assert.equal(inQuietHours(p, new Date('2026-11-21T04:00:00Z')), false);  // 09:00 PKT
  assert.equal(channelsFor('closing_soon', p, new Date('2026-11-21T04:00:00Z')).email, true);
  assert.equal(channelsFor('matching_opportunity', p, new Date('2026-11-21T04:00:00Z')).email, false);
  assert.equal(channelsFor('interview_reminder', p, new Date('2026-11-21T18:30:00Z')).deferPush, false, 'interviews are never deferred');
  assert.equal(channelsFor('closing_soon', { ...p, sms_enabled: true }, new Date()).sms, true);
});

test('unconfigured channels are skipped, never reported as sent', async () => {
  delete process.env.FCM_SERVICE_ACCOUNT_JSON; delete process.env.RESEND_API_KEY;
  assert.equal(new FcmChannel().configured(), false);
  assert.deepEqual(await new EmailChannel().send('a@b.c', { title: 't', body: 'b' }), { ok: false, skipped: true, error: 'Email not configured' });
});

test('FCM service-account JWT is a valid RS256 signature', async () => {
  const kp = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', kp.privateKey)).toString('base64');
  const pem = `-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g)!.join('\n')}\n-----END PRIVATE KEY-----\n`;
  const jwt = await signServiceAccountJwt({ client_email: 'svc@p.iam.gserviceaccount.com', private_key: pem, project_id: 'p' }, 'scope', 1000);
  const [h, c, s] = jwt.split('.');
  const sig = Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  assert.ok(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', kp.publicKey, sig, new TextEncoder().encode(`${h}.${c}`)));
  assert.equal(JSON.parse(Buffer.from(c, 'base64').toString()).exp, 4600);
});

test('security helpers', () => {
  assert.equal(safeEqual('abc', 'abc'), true);
  assert.equal(safeEqual('abc', 'abd'), false);
  const rl = new RateLimiter(2, 1000);
  rl.check('k', 0); rl.check('k', 1);
  assert.throws(() => rl.check('k', 2), (e: unknown) => e instanceof HttpError && e.status === 429);
  rl.check('k', 1500);
  assert.throws(() => readSecretRef('SUPABASE_SERVICE_ROLE_KEY'), /platform secrets/);
  assert.throws(() => readSecretRef('lower-case'), /Invalid/);
});

const feedRow = (over: Partial<FeedRow>): FeedRow => ({ id: 'x', title: 't', organization_name: 'o', category_slug: 'scholarships', tags: [],
  education_levels: [], fields_of_study: [], required_skills: [], provinces: [], cities: [], is_nationwide: true, work_mode: 'not_applicable',
  deadline: '2026-12-30T00:00:00Z', effective_status: 'open', verification_status: 'verified', is_featured: false, is_demo: false, is_reported: false,
  gender_eligibility: 'any', created_at: '2026-10-01T00:00:00Z', ...over });

test('recommendations: closed and ineligible never recommended; reasons shown', () => {
  const now = new Date('2026-11-21T00:00:00Z');
  const u: UserFacts = { userId: 'u', profileVersion: 1, shareSensitive: false, province: 'Sindh', gender: 'male', interests: ['internships'],
    skills: ['Python'], experiences: [], documentCategories: [], education: [{ level: 'bachelor', fieldOfStudy: 'Computer Science', isCurrent: true }] };
  const feed = [
    feedRow({ id: 'closed', effective_status: 'closed' }),
    feedRow({ id: 'past', deadline: '2026-11-01T00:00:00Z' }),
    feedRow({ id: 'inel' }),
    feedRow({ id: 'women', gender_eligibility: 'female' }),
    feedRow({ id: 'good', category_slug: 'internships', education_levels: ['bachelor'], fields_of_study: ['Computer Science'], required_skills: ['Python'], deadline: '2026-11-25T00:00:00Z' }),
    feedRow({ id: 'punjab', is_nationwide: false, provinces: ['Punjab'] }),
  ];
  const elig = new Map([['inel', 'not_eligible' as const], ['good', 'eligible' as const]]);
  const recs = recommend(feed, u, elig, {}, 10, now);
  const ids = recs.map((r) => r.opportunityId);
  assert.equal(ids[0], 'good');
  ['closed', 'past', 'inel', 'women'].forEach((x) => assert.ok(!ids.includes(x), x));
  assert.ok(recs[0].reasons.includes('You meet the main eligibility requirements'));
  assert.equal(recs[0].reasons.length, 3);
  assert.ok(recommend(feed, u, elig, { verified_only: true, excluded_categories: ['internships'] }, 10, now).every((r) => r.opportunityId !== 'good'));
});
