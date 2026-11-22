// POST /functions/v1/eligibility-check  { "opportunity_id": uuid } | { "opportunity_ids": uuid[], "force"?: boolean }
// Deterministic eligibility for the signed-in user. Results are stored in eligibility_checks.
import { bearer, handle, HttpError, isUuid, json, RateLimiter, readJson } from '../_shared/http.ts';
import { Rest } from '../_shared/rest.ts';
import { checkEligibility } from '../_shared/services.ts';

const limiter = new RateLimiter(60, 60_000);

Deno.serve(handle(async (req) => {
  if (req.method !== 'POST') throw new HttpError(405, 'Use POST', 'method_not_allowed');
  const token = bearer(req);
  const userDb = Rest.user(token);
  const user = await userDb.authUser();
  limiter.check(user.id);
  const body = await readJson<{ opportunity_id?: unknown; opportunity_ids?: unknown; force?: unknown }>(req);
  const ids = Array.isArray(body.opportunity_ids) ? body.opportunity_ids : body.opportunity_id ? [body.opportunity_id] : [];
  if (ids.length === 0 || !ids.every(isUuid)) throw new HttpError(422, 'Provide opportunity_id or opportunity_ids (UUIDs)', 'validation');
  const results = await checkEligibility(userDb, Rest.service(), user.id, ids as string[], { force: body.force === true });
  return json({ results });
}));
