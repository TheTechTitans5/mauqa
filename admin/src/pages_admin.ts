// Dashboard, data sources, moderation, users, content and analytics pages.
import { Api, enc } from './api.ts';
import { badge, clear, download, field, fmtDate, guarded, h, modal, table, toast } from './dom.ts';
import { isHttpsUrl, slugify, toCsv } from './lib.ts';

export async function dashboardPage(api: Api, root: HTMLElement) {
  const s = await api.rpc<Record<string, unknown>>('admin_dashboard_stats');
  const card = (label: string, key: string, kind = '') => h('div', { class: `stat ${kind}` }, h('div', { class: 'n' }, String(s[key] ?? 0)), h('div', {}, label));
  const sources = (s.sources as Array<Record<string, unknown>>) ?? [];
  const recent = (s.recent_activity as Array<Record<string, unknown>>) ?? [];
  root.append(
    h('h2', {}, 'Dashboard'),
    h('div', { class: 'stats' },
      card('Total users', 'total_users'), card('Active users (30d)', 'active_users_30d'), card('Opportunities', 'total_opportunities'),
      card('Verified', 'verified', 'ok'), card('Pending verification', 'pending', 'warn'), card('Expired / closed', 'expired', 'muted'),
      card('Open reports', 'reported', 'bad'), card('Ingested items to review', 'pending_source_items', 'warn'),
      card('Submissions', 'pending_submissions'), card('Stories to moderate', 'pending_stories'), card('Corrections', 'pending_corrections')),
    h('h3', {}, 'Data synchronisation'),
    table(['Source', 'Integration', 'Enabled', 'Last success', 'Failures'], sources.map((x) => [String(x.name),
      badge(String(x.status).replace(/_/g, ' '), x.status === 'active' ? 'ok' : x.status === 'error' ? 'bad' : 'warn'),
      x.enabled ? 'yes' : 'no', fmtDate(x.last_success_at as string | null), String(x.failures)])),
    h('h3', {}, 'Recent activity'),
    table(['When', 'Action', 'Table', 'Record'], recent.map((a) => [fmtDate(a.created_at as string), String(a.action), String(a.table_name), String(a.record_id ?? '')])),
  );
}

interface Source {
  id: string; name: string; organization_id: string | null; source_type: string; base_url: string | null; config: Record<string, unknown>;
  auth_method: string; secret_ref: string | null; integration_status: string; authorization_notes: string | null; terms_reviewed_at: string | null;
  sync_interval_minutes: number; rate_limit_per_minute: number; is_enabled: boolean; last_sync_at: string | null; last_success_at: string | null;
  next_sync_at: string | null; consecutive_failures: number;
}

export async function sourcesPage(api: Api, root: HTMLElement) {
  const box = h('div');
  const load = async () => {
    clear(box);
    const rows = await api.select<Source>('data_sources', 'select=*&order=name');
    box.append(table(['Source', 'Type', 'Integration', 'Enabled', 'Last sync', 'Next', ''], rows.map((s) => [
      h('div', {}, h('strong', {}, s.name), s.authorization_notes ? h('div', { class: 'muted small' }, s.authorization_notes) : null),
      s.source_type, badge(s.integration_status.replace(/_/g, ' '), s.integration_status === 'active' ? 'ok' : s.integration_status === 'error' ? 'bad' : 'warn'),
      s.is_enabled ? 'yes' : 'no', fmtDate(s.last_sync_at), fmtDate(s.next_sync_at),
      h('div', { class: 'stack' },
        h('button', { onclick: () => editSource(api, s, load) }, 'Configure'),
        h('button', { onclick: () => syncLogs(api, s) }, 'Logs'),
        h('button', { disabled: !(s.is_enabled && s.integration_status === 'active'), title: 'Enabled + active sources only', onclick: async () => {
          const ok = await guarded(async () => {
            const r = await api.fn<{ status: string; found: number; created: number; changed: number; message?: string }>('source-sync', { source_id: s.id });
            toast(`Sync ${r.status}: ${r.found} found, ${r.created} new, ${r.changed} changed${r.message ? ` — ${r.message}` : ''}`, r.status === 'failed' ? 'error' : 'ok');
          });
          if (ok) await load();
        } }, 'Sync now')),
    ])));
  };
  root.append(h('div', { class: 'toolbar' }, h('h2', {}, 'Data sources'), h('button', { class: 'primary', onclick: () => editSource(api, null, load) }, '+ Add source')),
    h('p', { class: 'muted' }, 'Connectors never fetch anything until a source is enabled AND marked active. Credentials are stored as backend secrets; here you only enter the secret NAME.'),
    box);
  await guarded(load);
}

async function editSource(api: Api, s: Source | null, done: () => Promise<void>) {
  const orgs = await api.select<{ id: string; name: string }>('organizations', 'select=id,name&order=name');
  const v = <K extends keyof Source>(k: K, d: Source[K]) => (s ? s[k] : d);
  const name = h('input', { value: v('name', '') }) as HTMLInputElement;
  const org = h('select', {}, h('option', { value: '' }, '—'), orgs.map((o) => h('option', { value: o.id, selected: v('organization_id', null) === o.id }, o.name))) as HTMLSelectElement;
  const type = h('select', {}, ['api', 'rss', 'web_monitor', 'pdf', 'manual'].map((t) => h('option', { value: t, selected: v('source_type', 'manual') === t }, t))) as HTMLSelectElement;
  const base = h('input', { type: 'url', value: v('base_url', null) ?? '' }) as HTMLInputElement;
  const auth = h('select', {}, ['none', 'api_key_header', 'bearer_token', 'basic', 'oauth2_client_credentials'].map((t) => h('option', { value: t, selected: v('auth_method', 'none') === t }, t))) as HTMLSelectElement;
  const secret = h('input', { value: v('secret_ref', null) ?? '', placeholder: 'e.g. HEC_API_TOKEN' }) as HTMLInputElement;
  const status = h('select', {}, ['awaiting_authorization', 'awaiting_configuration', 'active', 'paused', 'error'].map((t) => h('option', { value: t, selected: v('integration_status', 'awaiting_configuration') === t }, t))) as HTMLSelectElement;
  const notes = h('textarea', { rows: 3 }, v('authorization_notes', null) ?? '') as HTMLTextAreaElement;
  const interval = h('input', { type: 'number', min: 15, value: v('sync_interval_minutes', 1440) }) as HTMLInputElement;
  const rate = h('input', { type: 'number', min: 1, value: v('rate_limit_per_minute', 6) }) as HTMLInputElement;
  const enabled = h('input', { type: 'checkbox', checked: v('is_enabled', false) }) as HTMLInputElement;
  const terms = h('input', { type: 'checkbox', checked: Boolean(v('terms_reviewed_at', null)) }) as HTMLInputElement;
  const config = h('textarea', { rows: 10, class: 'mono' }, JSON.stringify(v('config', {}), null, 2)) as HTMLTextAreaElement;
  const examples = h('details', {}, h('summary', {}, 'Config examples'), h('pre', { class: 'mono small' }, [
    'api: {"endpoint":"/v1/opportunities","items_path":"data","id_path":"id","pagination":{"type":"page","param":"page","size_param":"per_page","size":50,"max_pages":10},"mapping":{"title":"title","deadline":"closing_date","source_url":"url","official_application_url":"apply_url"}}',
    'rss: {"feed_url":"https://example.gov.pk/feed.xml"}',
    'web_monitor: {"list_url":"https://example.gov.pk/scholarships","link_include":["/scholarship"],"fetch_details":true,"max_items":25}',
    'pdf: {"pdf_urls":["https://example.gov.pk/ad.pdf"],"ocr":true}',
  ].join('\n\n')));
  const m = modal(s ? `Configure ${s.name}` : 'New data source', h('div', { class: 'grid' },
    field('Name', name), field('Organisation', org), field('Type', type), field('Base URL (https)', base),
    field('Auth method', auth), field('Secret name', secret, 'Name of a Supabase secret — never paste the secret itself'),
    field('Integration status', status, 'Set to active only after authorisation/terms are confirmed'),
    field('Authorisation notes', notes), field('Sync interval (minutes)', interval), field('Rate limit (requests/min)', rate),
    field('Terms of use & robots.txt reviewed', terms), field('Enabled', enabled), field('Connector config (JSON)', config), examples), [
    h('button', { class: 'primary', onclick: async () => {
      let cfg: unknown;
      try { cfg = JSON.parse(config.value || '{}'); } catch { return toast('Config is not valid JSON', 'error'); }
      if (base.value && !isHttpsUrl(base.value)) return toast('Base URL must use https', 'error');
      if (secret.value && !/^[A-Z][A-Z0-9_]{2,63}$/.test(secret.value)) return toast('Secret name must look like MY_SECRET_NAME', 'error');
      if (status.value === 'active' && type.value === 'web_monitor' && !terms.checked) return toast('Review the site terms and robots.txt before activating monitoring', 'error');
      const row = {
        name: name.value.trim(), organization_id: org.value || null, source_type: type.value, base_url: base.value || null, auth_method: auth.value,
        secret_ref: secret.value || null, integration_status: status.value, authorization_notes: notes.value || null,
        sync_interval_minutes: Number(interval.value), rate_limit_per_minute: Number(rate.value), is_enabled: enabled.checked, config: cfg,
        terms_reviewed_at: terms.checked ? (s?.terms_reviewed_at ?? new Date().toISOString()) : null,
      };
      if (!row.name) return toast('Name is required', 'error');
      if (await guarded(() => (s ? api.update('data_sources', `id=eq.${s.id}`, row) : api.insert('data_sources', row)), 'Saved')) { m.close(); await done(); }
    } }, 'Save'),
  ]);
}

async function syncLogs(api: Api, s: Source) {
  const logs = await api.select<Record<string, unknown>>('source_sync_logs', `select=*&source_id=eq.${s.id}&order=started_at.desc&limit=30`);
  modal(`Sync history: ${s.name}`, table(['Started', 'Trigger', 'Status', 'Found', 'New', 'Changed', 'Dup', 'Invalid', 'Error'], logs.map((l) => [
    fmtDate(l.started_at as string), String(l.triggered_by), badge(String(l.status), l.status === 'success' ? 'ok' : l.status === 'failed' ? 'bad' : 'warn'),
    String(l.items_found), String(l.items_new), String(l.items_changed), String(l.items_duplicate), String(l.items_invalid), String(l.error_message ?? '')])), []);
}

export async function moderationPage(api: Api, root: HTMLElement) {
  const box = h('div');
  const load = async () => {
    clear(box);
    const [reports, stories, contentReports, feedback] = await Promise.all([
      api.select<Record<string, unknown>>('opportunity_reports', 'select=*,opportunities(id,title)&status=in.(open,investigating)&order=created_at.asc&limit=100'),
      api.select<Record<string, unknown>>('success_stories', 'select=*&status=eq.pending&order=created_at.asc&limit=50'),
      api.select<Record<string, unknown>>('content_reports', 'select=*,success_stories(title)&status=eq.open&order=created_at.asc'),
      api.select<Record<string, unknown>>('feedback', 'select=*&status=neq.closed&order=created_at.desc&limit=100'),
    ]);
    const setReport = (id: string, status: string) => async () => {
      const resolution = status === 'investigating' ? null : prompt('Resolution note (required):');
      if (status !== 'investigating' && !resolution) return;
      if (await guarded(() => api.update('opportunity_reports', `id=eq.${id}`, { status, resolution, handled_at: new Date().toISOString(), handled_by: api.session?.user.id }), 'Updated')) await load();
    };
    box.append(
      h('h3', {}, `Opportunity & scam reports (${reports.length})`),
      table(['When', 'Listing', 'Reason', 'Details', 'Status', ''], reports.map((r) => [fmtDate(r.created_at as string),
        String((r.opportunities as { title?: string } | null)?.title ?? r.organization_id ?? ''), badge(String(r.reason).replace(/_/g, ' '), 'warn'),
        String(r.details ?? ''), String(r.status),
        h('div', { class: 'stack' },
          h('button', { onclick: setReport(String(r.id), 'investigating') }, 'Investigate'),
          h('button', { onclick: setReport(String(r.id), 'resolved') }, 'Resolve'),
          h('button', { class: 'ghost', onclick: setReport(String(r.id), 'dismissed') }, 'Dismiss'))])),
      h('p', { class: 'muted' }, 'Listings are labelled "Reported for review" after 3 distinct reporters. Never mark a listing fraudulent without evidence from the official organisation.'),
      h('h3', {}, `Stories awaiting approval (${stories.length})`),
      table(['Author', 'Title', 'Story', ''], stories.map((s) => [String(s.author_display_name), String(s.title), h('div', { class: 'clip' }, String(s.body)),
        h('div', { class: 'stack' },
          h('button', { class: 'primary', onclick: async () => { if (await guarded(() => api.update('success_stories', `id=eq.${s.id}`, { status: 'approved', published_at: new Date().toISOString(), moderated_by: api.session?.user.id }), 'Published')) await load(); } }, 'Approve'),
          h('button', { class: 'danger', onclick: async () => { if (await guarded(() => api.update('success_stories', `id=eq.${s.id}`, { status: 'rejected', moderated_by: api.session?.user.id }), 'Rejected')) await load(); } }, 'Reject'))])),
      h('h3', {}, `Reported stories (${contentReports.length})`),
      table(['Story', 'Reason', ''], contentReports.map((c) => [String((c.success_stories as { title?: string } | null)?.title ?? ''), String(c.reason),
        h('div', { class: 'stack' },
          h('button', { class: 'danger', onclick: async () => { if (await guarded(async () => {
            await api.update('success_stories', `id=eq.${c.story_id}`, { status: 'rejected' });
            await api.update('content_reports', `id=eq.${c.id}`, { status: 'resolved' });
          }, 'Story unpublished')) await load(); } }, 'Unpublish story'),
          h('button', { class: 'ghost', onclick: async () => { if (await guarded(() => api.update('content_reports', `id=eq.${c.id}`, { status: 'dismissed' }))) await load(); } }, 'Dismiss'))])),
      h('h3', {}, `Feedback & support (${feedback.length})`),
      table(['When', 'Kind', 'Message', 'App', ''], feedback.map((f) => [fmtDate(f.created_at as string), badge(String(f.kind)), h('div', { class: 'clip' }, String(f.message)),
        `${f.app_version ?? ''} ${f.platform ?? ''}`,
        h('button', { onclick: async () => { if (await guarded(() => api.update('feedback', `id=eq.${f.id}`, { status: 'closed' }), 'Closed')) await load(); } }, 'Close')])),
    );
  };
  root.append(h('div', { class: 'toolbar' }, h('h2', {}, 'Moderation'), h('button', { onclick: () => guarded(load) }, 'Refresh')), box);
  await guarded(load);
}

export async function usersPage(api: Api, root: HTMLElement, myRoles: string[]) {
  const q = h('input', { type: 'search', placeholder: 'Search name or email…' }) as HTMLInputElement;
  const box = h('div');
  const isSuper = myRoles.includes('super_admin');
  const load = async () => {
    clear(box);
    let query = 'select=id,full_name,email,phone,province,user_category,is_suspended,created_at&order=created_at.desc&limit=50';
    const term = q.value.trim().replace(/[*,()]/g, '');
    if (term) query += `&or=(full_name.ilike.*${enc(term)}*,email.ilike.*${enc(term)}*)`;
    const users = await api.select<Record<string, unknown>>('profiles', query);
    const roles = users.length ? await api.select<{ user_id: string; role: string }>('user_roles', `select=user_id,role&user_id=in.(${users.map((u) => u.id).join(',')})`) : [];
    box.append(table(['User', 'Category', 'Joined', 'Roles', 'Status', ''], users.map((u) => {
      const mine = roles.filter((r) => r.user_id === u.id).map((r) => r.role);
      const assignable = ['verifier', 'content_manager', ...(isSuper ? ['admin', 'super_admin'] : [])];
      return [
        h('div', {}, h('strong', {}, String(u.full_name ?? '—')), h('div', { class: 'muted small' }, String(u.email ?? u.phone ?? ''))),
        String(u.user_category ?? ''), fmtDate(u.created_at as string), h('div', {}, mine.map((r) => badge(r))),
        u.is_suspended ? badge('suspended', 'bad') : badge('active', 'ok'),
        h('div', { class: 'stack' },
          ...assignable.map((r) => h('button', { class: 'ghost', onclick: async () => {
            const grant = !mine.includes(r);
            if (await guarded(() => api.rpc('admin_set_role', { p_user: u.id, p_role: r, p_grant: grant }), `${grant ? 'Granted' : 'Removed'} ${r}`)) await load();
          } }, `${mine.includes(r) ? '− ' : '+ '}${r}`)),
          h('button', { class: u.is_suspended ? '' : 'danger', onclick: async () => {
            const reason = prompt(u.is_suspended ? 'Reason for lifting suspension:' : 'Justification for suspension (logged):');
            if (reason && await guarded(() => api.rpc('admin_set_suspended', { p_user: u.id, p_suspended: !u.is_suspended, p_reason: reason }), 'Updated')) await load();
          } }, u.is_suspended ? 'Unsuspend' : 'Suspend')),
      ];
    })));
  };
  q.addEventListener('keydown', (e) => { if ((e as KeyboardEvent).key === 'Enter') guarded(load); });
  root.append(h('div', { class: 'toolbar' }, h('h2', {}, 'Users & roles'), q, h('button', { onclick: () => guarded(load) }, 'Search')), box);
  await guarded(load);
}

export async function contentPage(api: Api, root: HTMLElement) {
  const box = h('div');
  const load = async () => {
    clear(box);
    const [guides, anns, orgs, cats] = await Promise.all([
      api.select<Record<string, unknown>>('guides', 'select=*&order=sort_order'),
      api.select<Record<string, unknown>>('announcements', 'select=*&order=created_at.desc&limit=30'),
      api.select<Record<string, unknown>>('organizations', 'select=*&order=name'),
      api.select<Record<string, unknown>>('opportunity_categories', 'select=*&order=sort_order'),
    ]);
    box.append(
      h('div', { class: 'toolbar' }, h('h3', {}, 'Guides (English & Urdu)'), h('button', { onclick: () => editGuide(api, null, load) }, '+ Guide')),
      table(['Title', 'Category', 'Urdu', 'Published', ''], guides.map((g) => [String(g.title_en), String(g.category), g.body_ur ? '✓' : '—', g.is_published ? '✓' : '—',
        h('button', { onclick: () => editGuide(api, g, load) }, 'Edit')])),
      h('div', { class: 'toolbar' }, h('h3', {}, 'Announcements'), h('button', { onclick: async () => {
        const title = prompt('Announcement title'); if (!title) return;
        const body = prompt('Announcement text'); if (!body) return;
        if (await guarded(() => api.insert('announcements', { title, body, is_published: true, published_at: new Date().toISOString(), created_by: api.session?.user.id }), 'Published')) await load();
      } }, '+ Announcement')),
      table(['Title', 'Published', ''], anns.map((a) => [String(a.title), a.is_published ? fmtDate(a.published_at as string) : 'draft',
        h('button', { onclick: async () => { if (await guarded(() => api.update('announcements', `id=eq.${a.id}`, { is_published: !a.is_published }))) await load(); } }, a.is_published ? 'Unpublish' : 'Publish')])),
      h('div', { class: 'toolbar' }, h('h3', {}, 'Organisations'), h('button', { onclick: () => editOrg(api, null, load) }, '+ Organisation')),
      table(['Name', 'Type', 'Official domains', 'Verified', ''], orgs.map((o) => [String(o.name), String(o.org_type), ((o.official_domains as string[]) ?? []).join(', '),
        o.is_verified ? badge('verified', 'ok') : badge('not verified', 'warn'), h('button', { onclick: () => editOrg(api, o, load) }, 'Edit')])),
      h('h3', {}, 'Categories'),
      table(['Slug', 'English', 'Urdu', 'Order'], cats.map((c) => [String(c.slug), String(c.name_en), String(c.name_ur), String(c.sort_order)])),
    );
  };
  root.append(h('h2', {}, 'Content'), box);
  await guarded(load);
}

function editGuide(api: Api, g: Record<string, unknown> | null, done: () => Promise<void>) {
  const cats = ['scholarship', 'internship', 'job', 'government_scheme', 'cv', 'interview', 'aptitude_test', 'entry_test', 'english', 'digital_skills',
    'free_courses', 'certification', 'tips', 'faq', 'personal_statement', 'statement_of_purpose'];
  const title = h('input', { value: String(g?.title_en ?? '') }) as HTMLInputElement;
  const titleUr = h('input', { value: String(g?.title_ur ?? ''), dir: 'rtl' }) as HTMLInputElement;
  const cat = h('select', {}, cats.map((c) => h('option', { value: c, selected: g?.category === c }, c))) as HTMLSelectElement;
  const body = h('textarea', { rows: 10 }, String(g?.body_en ?? '')) as HTMLTextAreaElement;
  const bodyUr = h('textarea', { rows: 10, dir: 'rtl' }, String(g?.body_ur ?? '')) as HTMLTextAreaElement;
  const pub = h('input', { type: 'checkbox', checked: Boolean(g?.is_published) }) as HTMLInputElement;
  const m = modal(g ? 'Edit guide' : 'New guide', h('div', { class: 'grid' }, field('Title (English)', title), field('Title (Urdu)', titleUr), field('Category', cat),
    field('Body (English)', body), field('Body (Urdu)', bodyUr), field('Published', pub)), [
    h('button', { class: 'primary', onclick: async () => {
      if (!title.value.trim() || !body.value.trim()) return toast('English title and body are required', 'error');
      const row = { title_en: title.value.trim(), title_ur: titleUr.value.trim() || null, category: cat.value, body_en: body.value, body_ur: bodyUr.value || null,
        is_published: pub.checked, slug: String(g?.slug ?? slugify(title.value)), updated_by: api.session?.user.id, updated_at: new Date().toISOString() };
      if (await guarded(() => (g ? api.update('guides', `id=eq.${g.id}`, row) : api.insert('guides', row)), 'Saved')) { m.close(); await done(); }
    } }, 'Save'),
  ]);
}

function editOrg(api: Api, o: Record<string, unknown> | null, done: () => Promise<void>) {
  const name = h('input', { value: String(o?.name ?? '') }) as HTMLInputElement;
  const type = h('select', {}, ['government', 'private', 'ngo', 'university', 'international', 'other'].map((t) => h('option', { value: t, selected: o?.org_type === t }, t))) as HTMLSelectElement;
  const site = h('input', { type: 'url', value: String(o?.website ?? '') }) as HTMLInputElement;
  const domains = h('input', { value: ((o?.official_domains as string[]) ?? []).join(', '), placeholder: 'hec.gov.pk' }) as HTMLInputElement;
  const email = h('input', { type: 'email', value: String(o?.contact_email ?? '') }) as HTMLInputElement;
  const desc = h('textarea', { rows: 3 }, String(o?.description ?? '')) as HTMLTextAreaElement;
  const verified = h('input', { type: 'checkbox', checked: Boolean(o?.is_verified) }) as HTMLInputElement;
  const m = modal(o ? 'Edit organisation' : 'New organisation', h('div', { class: 'grid' }, field('Name', name), field('Type', type), field('Website', site),
    field('Official domains', domains, 'Used to warn users about non-official application links'), field('Contact email', email), field('Description', desc),
    field('Verified organisation', verified, 'Only after confirming identity with the organisation')), [
    h('button', { class: 'primary', onclick: async () => {
      if (!name.value.trim()) return toast('Name required', 'error');
      if (site.value && !isHttpsUrl(site.value)) return toast('Website must be https', 'error');
      const row = { name: name.value.trim(), org_type: type.value, website: site.value || null, contact_email: email.value || null, description: desc.value || null,
        official_domains: domains.value.split(',').map((d) => d.trim().toLowerCase()).filter(Boolean), is_verified: verified.checked,
        verified_at: verified.checked ? (o?.verified_at ?? new Date().toISOString()) : null, slug: String(o?.slug ?? slugify(name.value)) };
      if (await guarded(() => (o ? api.update('organizations', `id=eq.${o.id}`, row) : api.insert('organizations', row)), 'Saved')) { m.close(); await done(); }
    } }, 'Save'),
  ]);
}

/** Width is set through the CSSOM (allowed by the strict CSP) rather than an inline style attribute. */
function fillBar(pct: number): HTMLElement {
  const el = h('span', { class: 'fill' });
  el.style.width = `${Math.max(0, Math.min(100, pct))}%`;
  return el;
}

export async function analyticsPage(api: Api, root: HTMLElement) {
  const a = await api.rpc<Record<string, unknown>>('admin_analytics');
  const bars = (title: string, data: Record<string, number> | Array<Record<string, unknown>> | null | undefined, labelKey = '', valueKey = '') => {
    const entries: Array<[string, number]> = !data ? []
      : Array.isArray(data) ? data.map((d) => [String(d[labelKey]), Number(d[valueKey])])
      : Object.entries(data).map(([k, v]) => [k, Number(v)]);
    const max = Math.max(1, ...entries.map(([, v]) => v));
    return h('section', { class: 'chart' }, h('h3', {}, title), entries.length === 0 ? h('p', { class: 'muted' }, 'No data yet') :
      entries.sort((x, y) => y[1] - x[1]).slice(0, 12).map(([k, v]) => h('div', { class: 'bar' },
        h('span', { class: 'label' }, k.replace(/_/g, ' ')), h('span', { class: 'track' }, fillBar((v / max) * 100)), h('span', { class: 'v' }, String(v)))));
  };
  const exportBtn = (name: string, rows: unknown) => h('button', { onclick: () => {
    const arr = Array.isArray(rows) ? rows as Array<Record<string, unknown>> : Object.entries((rows ?? {}) as Record<string, unknown>).map(([k, v]) => ({ key: k, value: v }));
    download(`mauqa-${name}-${new Date().toISOString().slice(0, 10)}.csv`, toCsv(arr));
  } }, `Export ${name}.csv`);
  root.append(
    h('div', { class: 'toolbar' }, h('h2', {}, 'Analytics'),
      exportBtn('most-viewed', a.most_viewed), exportBtn('opportunities-by-category', a.opportunities_by_category), exportBtn('source-reliability', a.source_reliability)),
    h('div', { class: 'charts' },
      bars('Users by category', a.users_by_category as Record<string, number>),
      bars('Users by province', a.users_by_province as Record<string, number>),
      bars('Opportunities by category', a.opportunities_by_category as Record<string, number>),
      bars('Popular categories (views, 30d)', a.popular_categories as Array<Record<string, unknown>>, 'category', 'views'),
      bars('Popular locations', a.popular_locations as Array<Record<string, unknown>>, 'province', 'count'),
      bars('Most viewed', a.most_viewed as Array<Record<string, unknown>>, 'title', 'count'),
      bars('Most saved', a.most_saved as Array<Record<string, unknown>>, 'title', 'count'),
      bars('Most "Interested"', a.most_interested as Array<Record<string, unknown>>, 'title', 'count'),
      bars('Applications by status', a.applications_by_status as Record<string, number>),
      bars('Verification status', a.verification as Record<string, number>),
      bars('Source success rate (30d, %)', ((a.source_reliability as Array<Record<string, unknown>>) ?? []).map((r) => ({ source: r.source, pct: Math.round(Number(r.success_rate ?? 0) * 100) })), 'source', 'pct'),
      bars('Sign-ups per week', a.signups_by_week as Array<Record<string, unknown>>, 'week', 'count'),
    ),
  );
}
