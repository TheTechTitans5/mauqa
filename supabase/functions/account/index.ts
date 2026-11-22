// POST /functions/v1/account  { "action": "export" }                       → JSON copy of all personal data
// POST /functions/v1/account  { "action": "delete", "confirm": "DELETE" }  → permanently deletes account + files
import { bearer, handle, HttpError, json, RateLimiter, readJson } from '../_shared/http.ts';
import { Rest } from '../_shared/rest.ts';
import { deleteAccount, exportUserData } from '../_shared/services.ts';

const limiter = new RateLimiter(5, 60_000);

Deno.serve(handle(async (req) => {
  if (req.method !== 'POST') throw new HttpError(405, 'Use POST', 'method_not_allowed');
  const user = await Rest.user(bearer(req)).authUser();
  limiter.check(user.id);
  const body = await readJson<{ action?: string; confirm?: string }>(req);
  const service = Rest.service();
  if (body.action === 'export') {
    return json(await exportUserData(service, user.id), 200, {
      'Content-Disposition': `attachment; filename="mauqa-data-${new Date().toISOString().slice(0, 10)}.json"`,
    });
  }
  if (body.action === 'delete') {
    if (body.confirm !== 'DELETE') throw new HttpError(422, 'Type DELETE to confirm account deletion', 'validation');
    return json({ deleted: true, ...(await deleteAccount(service, user.id)) });
  }
  throw new HttpError(422, 'action must be "export" or "delete"', 'validation');
}));
