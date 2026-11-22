// Mauqa REST API facade: https://<project>.supabase.co/functions/v1/api/<route>
// See docs/API.md for the route list. All routes require a signed-in user's JWT.
import { bearer, handle, json, RateLimiter, readJson } from '../_shared/http.ts';
import { Rest } from '../_shared/rest.ts';
import { apiPath, dispatchApi } from '../_shared/apiRouter.ts';

const limiter = new RateLimiter(120, 60_000);

Deno.serve(handle(async (req) => {
  const token = bearer(req);
  limiter.check(token.slice(-24));
  const url = new URL(req.url);
  const result = await dispatchApi(
    { method: req.method, path: apiPath(req.url), query: url.searchParams, body: await readJson(req), token },
    {
      user: Rest.user(token),
      service: () => Rest.service(),
      ctx: { fetch: (i, init) => fetch(i, init), sleep: (ms) => new Promise((r) => setTimeout(r, ms)), log: console.log, now: () => new Date() },
    },
  );
  return json(result);
}));
