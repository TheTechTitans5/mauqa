// GET|POST /functions/v1/recommendations?limit=20
// Rule-based recommendations with human-readable reasons. Closed listings are never returned.
import { bearer, handle, json, RateLimiter } from '../_shared/http.ts';
import { Rest } from '../_shared/rest.ts';
import { recommendationsFor } from '../_shared/services.ts';

const limiter = new RateLimiter(20, 60_000);

Deno.serve(handle(async (req) => {
  const userDb = Rest.user(bearer(req));
  const user = await userDb.authUser();
  limiter.check(user.id);
  const limit = Number(new URL(req.url).searchParams.get('limit') ?? '20') || 20;
  const items = await recommendationsFor(userDb, Rest.service(), user.id, limit);
  return json({ items, generated_at: new Date().toISOString() });
}));
