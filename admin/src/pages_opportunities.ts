// Opportunity management, eligibility rule editor, required documents and the verification queue.
import { Api, enc } from './api.ts';
import { badge, clear, field, fmtDate, guarded, h, modal, table, toast } from './dom.ts';
import { CRITERIA, isHttpsUrl, isoToPktLocal, pktLocalToIso, rowsToTree, treeToRows, validateTree, type RuleNode, type RuleRow } from './lib.ts';

interface Opp {
  id: string; title: string; organization_id: string; category_id: string; summary: string | null; description: string | null;
  benefits: string | null; eligibility_summary: string | null; application_procedure: string | null; selection_procedure: string | null;
  important_instructions: string | null; funding_type: string; amount_text: string | null; amount_min_pkr: number | null; amount_max_pkr: number | null;
  work_mode: string; location_text: string | null; is_nationwide: boolean; provinces: string[]; cities: string[];
  education_levels: string[]; fields_of_study: string[]; required_skills: string[]; tags: string[];
  min_age: number | null; max_age: number | null; gender_eligibility: string; opening_date: string | null; deadline: string | null;
  status: string; source_url: string | null; official_application_url: string | null; verification_status: string;
  approval_status: string; is_published: boolean; is_featured: boolean; is_demo: boolean; is_reported: boolean;
  has_application_fee: boolean; application_fee_pkr: number | null; duration_text: string | null; recurrence_key: string | null;
  last_checked_at: string | null; last_verified_at: string | null; organizations?: { name: string; official_domains: string[] };
}
interface Org { id: string; name: string; official_domains: string[] }
interface Cat { id: string; slug: string; name_en: string }

const verifKind = (s: string) => s === 'verified' ? 'ok' : s === 'rejected' ? 'bad' : s === 'expired' ? 'muted' : 'warn';

export async function opportunitiesPage(api: Api, root: HTMLElement) {
  const q = h('input', { type: 'search', placeholder: 'Search title…' }) as HTMLInputElement;
  const status = h('select', {}, ['', 'pending_verification', 'verified', 'unverified', 'rejected', 'expired'].map((s) => h('option', { value: s }, s || 'Any verification'))) as HTMLSelectElement;
  const list = h('div');
  const load = async () => {
    clear(list);
    let query = 'select=id,title,deadline,verification_status,approval_status,is_published,is_featured,is_demo,is_reported,organizations(name)&order=updated_at.desc&limit=100';
    if (q.value.trim()) query += `&title=ilike.*${enc(q.value.trim().replace(/[*,()]/g, ''))}*`;
    if (status.value) query += `&verification_status=eq.${status.value}`;
    const rows = await api.select<Opp>('opportunities', query);
    list.append(table(['Title', 'Organisation', 'Deadline', 'Verification', 'State', ''], rows.map((o) => [
      h('strong', {}, o.title), o.organizations?.name ?? '', fmtDate(o.deadline),
      badge(o.verification_status.replace(/_/g, ' '), verifKind(o.verification_status)),
      h('span', {}, o.is_published ? badge('published', 'ok') : badge(o.approval_status), o.is_featured ? badge('featured') : null,
        o.is_demo ? badge('DEMO', 'muted') : null, o.is_reported ? badge('reported', 'bad') : null),
      h('button', { onclick: () => editOpportunity(api, o.id, load) }, 'Edit'),
    ])));
  };
  root.append(
    h('div', { class: 'toolbar' }, h('h2', {}, 'Opportunities'), q, status,
      h('button', { onclick: () => load() }, 'Search'), h('button', { class: 'primary', onclick: () => editOpportunity(api, null, load) }, '+ Add opportunity')),
    list,
  );
  q.addEventListener('keydown', (e) => { if ((e as KeyboardEvent).key === 'Enter') load(); });
  await guarded(load);
}

async function editOpportunity(api: Api, id: string | null, done: () => Promise<void>) {
  const [orgs, cats, opp] = await Promise.all([
    api.select<Org>('organizations', 'select=id,name,official_domains&order=name'),
    api.select<Cat>('opportunity_categories', 'select=id,slug,name_en&order=sort_order'),
    id ? api.select<Opp>('opportunities', `select=*,organizations(name,official_domains)&id=eq.${id}`).then((r) => r[0]) : Promise.resolve(null),
  ]);
  const o: Partial<Opp> = opp ?? { funding_type: 'not_applicable', work_mode: 'not_applicable', gender_eligibility: 'any', is_nationwide: true, status: 'open' };
  const inp = (k: keyof Opp, type = 'text') => h('input', { type, value: (o[k] as string | number | null) ?? '', 'data-k': k }) as HTMLInputElement;
  const area = (k: keyof Opp) => h('textarea', { rows: 4, 'data-k': k }, (o[k] as string | null) ?? '') as HTMLTextAreaElement;
  const sel = (k: keyof Opp, opts: Array<[string, string]>) => h('select', { 'data-k': k }, opts.map(([v, l]) => h('option', { value: v, selected: o[k] === v }, l))) as HTMLSelectElement;
  const list = (k: keyof Opp) => h('input', { type: 'text', value: ((o[k] as string[] | undefined) ?? []).join(', '), 'data-list': k }) as HTMLInputElement;
  const check = (k: keyof Opp) => h('input', { type: 'checkbox', checked: Boolean(o[k]), 'data-bool': k }) as HTMLInputElement;
  const deadline = h('input', { type: 'datetime-local', value: isoToPktLocal(o.deadline) }) as HTMLInputElement;
  const opening = h('input', { type: 'datetime-local', value: isoToPktLocal(o.opening_date) }) as HTMLInputElement;

  const form = h('form', { class: 'grid' },
    field('Title *', inp('title')),
    field('Organisation *', sel('organization_id', [['', '— select —'], ...orgs.map((x): [string, string] => [x.id, x.name])])),
    field('Category *', sel('category_id', [['', '— select —'], ...cats.map((x): [string, string] => [x.id, x.name_en])])),
    field('Official source URL *', inp('source_url', 'url'), 'Required before verification'),
    field('Official application URL', inp('official_application_url', 'url'), 'Must be the genuine portal — never a third-party form'),
    field('Opening (PKT)', opening), field('Deadline (PKT)', deadline),
    field('Status', sel('status', [['open', 'open'], ['upcoming', 'upcoming'], ['closed', 'closed'], ['cancelled', 'cancelled']])),
    field('Summary', area('summary')), field('Description', area('description')), field('Benefits', area('benefits')),
    field('Eligibility summary (human-readable)', area('eligibility_summary')),
    field('How to apply', area('application_procedure')), field('Selection process', area('selection_procedure')),
    field('Important instructions', area('important_instructions')),
    field('Funding type', sel('funding_type', ['fully_funded', 'partially_funded', 'paid', 'unpaid', 'not_applicable'].map((v): [string, string] => [v, v]))),
    field('Amount text', inp('amount_text')), field('Min amount PKR', inp('amount_min_pkr', 'number')), field('Max amount PKR', inp('amount_max_pkr', 'number')),
    field('Work mode', sel('work_mode', ['remote', 'onsite', 'hybrid', 'not_applicable'].map((v): [string, string] => [v, v]))),
    field('Location text', inp('location_text')), field('Nationwide', check('is_nationwide')),
    field('Provinces (comma separated)', list('provinces')), field('Cities', list('cities')),
    field('Education levels', list('education_levels'), 'matric, intermediate, bachelor, master, mphil, phd…'),
    field('Fields of study', list('fields_of_study')), field('Required skills', list('required_skills')), field('Tags', list('tags')),
    field('Min age', inp('min_age', 'number')), field('Max age', inp('max_age', 'number')),
    field('Open to', sel('gender_eligibility', [['any', 'Everyone'], ['female', 'Women'], ['male', 'Men'], ['transgender', 'Transgender persons'], ['female_transgender', 'Women & transgender persons']])),
    field('Duration', inp('duration_text')), field('Recurrence key (yearly cycles)', inp('recurrence_key')),
    field('Has application fee', check('has_application_fee')), field('Fee PKR', inp('application_fee_pkr', 'number')),
    field('Featured', check('is_featured')), field('Demo record', check('is_demo'), 'Demo records can never be verified'),
  ) as HTMLFormElement;

  const collect = (): Record<string, unknown> => {
    const out: Record<string, unknown> = {};
    form.querySelectorAll<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>('[data-k]').forEach((el) => {
      const k = el.dataset.k!;
      const v = el.value.trim();
      out[k] = el instanceof HTMLInputElement && el.type === 'number' ? (v === '' ? null : Number(v)) : v === '' ? null : v;
    });
    form.querySelectorAll<HTMLInputElement>('[data-list]').forEach((el) => {
      out[el.dataset.list!] = el.value.split(',').map((s) => s.trim()).filter(Boolean);
    });
    form.querySelectorAll<HTMLInputElement>('[data-bool]').forEach((el) => { out[el.dataset.bool!] = el.checked; });
    out.deadline = deadline.value ? pktLocalToIso(deadline.value) : null;
    out.opening_date = opening.value ? pktLocalToIso(opening.value) : null;
    return out;
  };

  const save = async () => {
    const row = collect();
    if (!row.title || !row.organization_id || !row.category_id) return toast('Title, organisation and category are required', 'error');
    for (const k of ['source_url', 'official_application_url'] as const) {
      if (row[k] && !isHttpsUrl(row[k] as string)) return toast(`${k} must be an https:// link`, 'error');
    }
    const org = orgs.find((x) => x.id === row.organization_id);
    if (row.official_application_url && org?.official_domains.length) {
      const host = new URL(row.official_application_url as string).hostname;
      if (!org.official_domains.some((d) => host === d || host.endsWith('.' + d)) &&
          !confirm(`The application link (${host}) is not on ${org.name}'s official domains (${org.official_domains.join(', ')}). Save anyway?`)) return;
    }
    const ok = await guarded(async () => {
      if (id) await api.update('opportunities', `id=eq.${id}`, row);
      else await api.insert('opportunities', { ...row, approval_status: 'pending_review', verification_status: 'pending_verification' });
    }, 'Saved');
    if (ok) { m.close(); await done(); }
  };

  const actions = [h('button', { class: 'primary', onclick: save }, 'Save')];
  if (id && opp) {
    actions.unshift(
      h('button', { onclick: () => rulesEditor(api, id) }, 'Eligibility rules'),
      h('button', { onclick: () => docsEditor(api, id) }, 'Required documents'),
      h('button', { onclick: () => reviewDialog(api, opp, async () => { m.close(); await done(); }) }, 'Verify / publish'),
      h('button', { onclick: async () => {
        if (await guarded(() => api.update('opportunities', `id=eq.${id}`, { is_published: !opp.is_published }), opp.is_published ? 'Unpublished' : 'Published')) { m.close(); await done(); }
      } }, opp.is_published ? 'Unpublish' : 'Publish'),
      h('button', { class: 'danger', onclick: async () => {
        if (!confirm('Delete this opportunity permanently? Users following it lose it from their lists.')) return;
        if (await guarded(() => api.remove('opportunities', `id=eq.${id}`), 'Deleted')) { m.close(); await done(); }
      } }, 'Delete'),
    );
  }
  const meta = opp ? h('p', { class: 'muted' }, `Verification: ${opp.verification_status} · approval: ${opp.approval_status} · last checked ${fmtDate(opp.last_checked_at)} · last verified ${fmtDate(opp.last_verified_at)}`) : null;
  const m = modal(id ? 'Edit opportunity' : 'New opportunity', h('div', {}, meta, form), actions);
}

function reviewDialog(api: Api, o: Opp, done: () => Promise<void>) {
  const box = (k: string, label: string) => h('label', { class: 'check' }, h('input', { type: 'checkbox', 'data-c': k }), label);
  const notes = h('textarea', { rows: 3, placeholder: 'Notes (what you checked, where)' }) as HTMLTextAreaElement;
  const publish = h('input', { type: 'checkbox', checked: true }) as HTMLInputElement;
  const body = h('div', {},
    h('p', {}, 'Confirm each item against the OFFICIAL source before approving:'),
    o.source_url ? h('p', {}, 'Source: ', h('a', { href: o.source_url, target: '_blank', rel: 'noopener noreferrer' }, o.source_url)) : h('p', { class: 'bad' }, 'No source URL — cannot verify.'),
    o.official_application_url ? h('p', {}, 'Apply: ', h('a', { href: o.official_application_url, target: '_blank', rel: 'noopener noreferrer' }, o.official_application_url)) : null,
    box('source_url_official', 'Source URL is the organisation’s official page'),
    box('application_url_official', 'Application URL is the genuine official portal'),
    box('deadline_confirmed', `Deadline confirmed: ${fmtDate(o.deadline)}`),
    box('eligibility_matches', 'Eligibility rules match the announcement'),
    box('no_unexplained_fees', 'No unexplained fees or payment requests'),
    notes, h('label', { class: 'check' }, publish, 'Publish after approval'),
  );
  const decide = (decision: string) => async () => {
    const checklist: Record<string, boolean> = {};
    body.querySelectorAll<HTMLInputElement>('[data-c]').forEach((c) => { checklist[c.dataset.c!] = c.checked; });
    if (await guarded(() => api.rpc('review_opportunity', { p_opportunity: o.id, p_decision: decision, p_checklist: checklist,
      p_notes: notes.value || null, p_publish: publish.checked }), `Decision recorded: ${decision}`)) { m.close(); await done(); }
  };
  const m = modal(`Verify: ${o.title}`, body, [
    h('button', { class: 'danger', onclick: decide('rejected') }, 'Reject'),
    h('button', { onclick: decide('needs_changes') }, 'Needs changes'),
    h('button', { class: 'primary', onclick: decide('approved') }, 'Approve'),
  ]);
}

async function rulesEditor(api: Api, opportunityId: string) {
  const rows = await api.select<RuleRow>('opportunity_eligibility_rules', `select=*&opportunity_id=eq.${opportunityId}&order=sort_order`);
  let tree: RuleNode = rows.length ? rowsToTree(rows) : { kind: 'group', op: 'and', mandatory: true, children: [] };
  const holder = h('div', { class: 'rules' });
  const render = () => { clear(holder); holder.append(renderNode(tree, () => render(), null)); };
  const renderNode = (n: RuleNode, rerender: () => void, removeSelf: (() => void) | null): HTMLElement => {
    if (n.kind === 'group') {
      const opSel = h('select', { onchange: (e: Event) => { n.op = (e.target as HTMLSelectElement).value as 'and' | 'or'; } },
        h('option', { value: 'and', selected: n.op === 'and' }, 'ALL of (AND)'), h('option', { value: 'or', selected: n.op === 'or' }, 'ANY of (OR)'));
      return h('div', { class: 'group' },
        h('div', { class: 'row' }, opSel,
          h('button', { onclick: () => { n.children = [...(n.children ?? []), { kind: 'criterion', type: 'cgpa_min', params: { min: 3 }, mandatory: true }]; rerender(); } }, '+ condition'),
          h('button', { onclick: () => { n.children = [...(n.children ?? []), { kind: 'group', op: 'or', mandatory: true, children: [] }]; rerender(); } }, '+ group'),
          removeSelf ? h('button', { class: 'ghost', onclick: removeSelf }, 'remove group') : null),
        (n.children ?? []).map((c, i) => renderNode(c, rerender, () => { n.children!.splice(i, 1); rerender(); })),
      );
    }
    const typeSel = h('select', { onchange: (e: Event) => {
      n.type = (e.target as HTMLSelectElement).value; n.params = { ...CRITERIA[n.type].example }; rerender();
    } }, Object.entries(CRITERIA).map(([k, v]) => h('option', { value: k, selected: n.type === k }, v.label)));
    const params = h('input', { type: 'text', class: 'mono', value: JSON.stringify(n.params ?? {}), onchange: (e: Event) => {
      try { n.params = JSON.parse((e.target as HTMLInputElement).value); (e.target as HTMLElement).classList.remove('invalid'); }
      catch { (e.target as HTMLElement).classList.add('invalid'); }
    } });
    const label = h('input', { type: 'text', placeholder: 'Label shown to users', value: n.label ?? '', onchange: (e: Event) => { n.label = (e.target as HTMLInputElement).value || undefined; } });
    const mand = h('input', { type: 'checkbox', checked: n.mandatory, onchange: (e: Event) => { n.mandatory = (e.target as HTMLInputElement).checked; } });
    return h('div', { class: 'criterion' }, typeSel, params, label, h('label', { class: 'check' }, mand, 'required'),
      h('small', { class: 'muted' }, `params: ${CRITERIA[n.type ?? 'custom']?.params ?? ''}`), removeSelf ? h('button', { class: 'ghost', onclick: removeSelf }, '✕') : null);
  };
  render();
  const m = modal('Eligibility rules', h('div', {},
    h('p', { class: 'muted' }, 'Rules are deterministic. If a requirement cannot be expressed, add a "Custom (manual check)" condition — users will see it as "could not be confirmed", never as eligible.'),
    holder), [
    h('button', { class: 'primary', onclick: async () => {
      const errs = tree.children?.length ? validateTree(tree) : [];
      if (errs.length) return toast(errs.join('; '), 'error');
      const newRows = tree.children?.length ? treeToRows(tree, opportunityId, () => crypto.randomUUID()) : [];
      if (await guarded(async () => {
        await api.remove('opportunity_eligibility_rules', `opportunity_id=eq.${opportunityId}`);
        if (newRows.length) await api.insert('opportunity_eligibility_rules', newRows);
      }, 'Rules saved — users’ eligibility results will refresh')) m.close();
    } }, 'Save rules'),
  ]);
}

async function docsEditor(api: Api, opportunityId: string) {
  const cats = ['cnic', 'passport', 'cv', 'transcript', 'degree', 'domicile', 'photograph', 'recommendation_letter', 'statement_of_purpose',
    'personal_statement', 'income_certificate', 'experience_certificate', 'skill_certificate', 'other'];
  const box = h('div');
  const load = async () => {
    clear(box);
    const docs = await api.select<{ id: string; category: string; label: string; is_mandatory: boolean }>('opportunity_documents', `select=*&opportunity_id=eq.${opportunityId}`);
    box.append(table(['Category', 'Label', 'Required', ''], docs.map((d) => [d.category, d.label, d.is_mandatory ? 'yes' : 'no',
      h('button', { class: 'ghost', onclick: async () => { if (await guarded(() => api.remove('opportunity_documents', `id=eq.${d.id}`))) await load(); } }, 'remove')])));
  };
  const cat = h('select', {}, cats.map((c) => h('option', { value: c }, c))) as HTMLSelectElement;
  const label = h('input', { type: 'text', placeholder: 'e.g. Attested transcript' }) as HTMLInputElement;
  const req = h('input', { type: 'checkbox', checked: true }) as HTMLInputElement;
  await guarded(load);
  modal('Required documents', h('div', {}, box, h('div', { class: 'row' }, cat, label, h('label', { class: 'check' }, req, 'required'),
    h('button', { onclick: async () => {
      if (!label.value.trim()) return toast('Enter a label', 'error');
      if (await guarded(() => api.insert('opportunity_documents', { opportunity_id: opportunityId, category: cat.value, label: label.value.trim(), is_mandatory: req.checked }))) {
        label.value = '';
        await load();
      }
    } }, 'Add'))), []);
}

// ------------------------------------------------------------------ verification queue
interface SourceItem {
  id: string; external_id: string; item_url: string | null; extracted: Record<string, unknown>; review_status: string;
  duplicate_of: string | null; duplicate_score: number | null; detected_changes: Record<string, { from: unknown; to: unknown }> | null;
  validation_issues: Array<{ severity: string; message: string }>; opportunity_id: string | null; first_seen_at: string; data_sources?: { name: string };
}

export async function reviewPage(api: Api, root: HTMLElement) {
  const box = h('div');
  const load = async () => {
    clear(box);
    const [pending, items, subs, corrections] = await Promise.all([
      api.select<Opp>('opportunities', 'select=*,organizations(name,official_domains)&verification_status=eq.pending_verification&order=updated_at.asc&limit=50'),
      api.select<SourceItem>('source_items', 'select=*,data_sources(name)&review_status=in.(pending,duplicate)&order=first_seen_at.asc&limit=50'),
      api.select<{ id: string; organization_name: string; title: string; source_url: string; payload: Record<string, unknown>; created_at: string }>(
        'opportunity_submissions', 'select=*&status=eq.pending&order=created_at.asc&limit=50'),
      api.select<{ id: string; field: string; suggested_value: string; evidence_url: string | null; opportunity_id: string; created_at: string; opportunities?: { title: string } }>(
        'user_corrections', 'select=*,opportunities(title)&status=eq.pending&order=created_at.asc&limit=50'),
    ]);
    const cats = await api.select<Cat>('opportunity_categories', 'select=id,slug,name_en&order=sort_order');
    const orgs = await api.select<Org>('organizations', 'select=id,name,official_domains&order=name');
    box.append(
      h('h3', {}, `Listings awaiting verification (${pending.length})`),
      table(['Title', 'Organisation', 'Deadline', 'Source', ''], pending.map((o) => [o.title, o.organizations?.name ?? '', fmtDate(o.deadline),
        o.source_url ? h('a', { href: o.source_url, target: '_blank', rel: 'noopener noreferrer' }, new URL(o.source_url).hostname) : badge('missing', 'bad'),
        h('button', { onclick: () => reviewDialog(api, o, load) }, 'Review')])),
      h('h3', {}, `Ingested items (${items.length})`),
      table(['Source', 'Extracted title', 'Deadline', 'Issues', 'Status', ''], items.map((it) => {
        const cat = h('select', {}, cats.map((c) => h('option', { value: c.slug }, c.name_en))) as HTMLSelectElement;
        const apply = h('input', { type: 'url', placeholder: 'Official application URL' }) as HTMLInputElement;
        return [
          it.data_sources?.name ?? '', h('div', {}, String(it.extracted.title ?? ''), it.item_url ? h('div', {}, h('a', { href: it.item_url, target: '_blank', rel: 'noopener noreferrer' }, 'open source')) : null,
            it.detected_changes ? h('div', { class: 'muted' }, 'Changed: ' + Object.keys(it.detected_changes).join(', ')) : null),
          fmtDate(it.extracted.deadline as string | null),
          h('ul', {}, (it.validation_issues ?? []).map((i) => h('li', { class: i.severity === 'error' ? 'bad' : '' }, i.message))),
          it.review_status === 'duplicate' ? badge(`duplicate ${Math.round((it.duplicate_score ?? 0) * 100)}%`, 'warn') : badge(it.review_status),
          h('div', { class: 'stack' },
            it.opportunity_id
              ? h('button', { onclick: async () => { if (await guarded(() => api.rpc('apply_source_item_changes', { p_item: it.id }), 'Changes applied')) await load(); } }, 'Apply changes')
              : h('div', { class: 'stack' }, cat, apply, h('button', { onclick: async () => {
                  if (apply.value && !isHttpsUrl(apply.value)) return toast('Application URL must be https', 'error');
                  if (await guarded(() => api.rpc('create_opportunity_from_source_item', { p_item: it.id, p_category_slug: cat.value,
                    p_official_application_url: apply.value || null }), 'Draft created — now verify it')) await load();
                } }, 'Create draft')),
            h('button', { class: 'danger', onclick: async () => {
              const reason = prompt('Reason for rejecting this item?');
              if (reason && await guarded(() => api.rpc('reject_source_item', { p_item: it.id, p_reason: reason }), 'Rejected')) await load();
            } }, 'Reject')),
        ];
      })),
      h('h3', {}, `User / organisation submissions (${subs.length})`),
      table(['Organisation', 'Title', 'Source', ''], subs.map((s) => {
        const org = h('select', {}, orgs.map((o) => h('option', { value: o.id }, o.name))) as HTMLSelectElement;
        const cat = h('select', {}, cats.map((c) => h('option', { value: c.slug }, c.name_en))) as HTMLSelectElement;
        return [s.organization_name, s.title, h('a', { href: s.source_url, target: '_blank', rel: 'noopener noreferrer' }, s.source_url),
          h('div', { class: 'stack' }, org, cat,
            h('button', { onclick: async () => { if (await guarded(() => api.rpc('accept_opportunity_submission', { p_submission: s.id, p_organization: org.value, p_category_slug: cat.value }), 'Draft created')) await load(); } }, 'Accept as draft'),
            h('button', { class: 'danger', onclick: async () => { if (await guarded(() => api.update('opportunity_submissions', `id=eq.${s.id}`, { status: 'rejected' }), 'Rejected')) await load(); } }, 'Reject'))];
      })),
      h('h3', {}, `Suggested corrections (${corrections.length})`),
      table(['Opportunity', 'Field', 'Suggestion', 'Evidence', ''], corrections.map((c) => [c.opportunities?.title ?? c.opportunity_id, c.field, c.suggested_value,
        c.evidence_url ? h('a', { href: c.evidence_url, target: '_blank', rel: 'noopener noreferrer' }, 'link') : '—',
        h('div', { class: 'stack' },
          h('button', { onclick: () => editOpportunity(api, c.opportunity_id, load) }, 'Open listing'),
          h('button', { onclick: async () => { if (await guarded(() => api.update('user_corrections', `id=eq.${c.id}`, { status: 'approved', reviewed_at: new Date().toISOString() }), 'Marked as applied')) await load(); } }, 'Mark applied'),
          h('button', { class: 'danger', onclick: async () => { if (await guarded(() => api.update('user_corrections', `id=eq.${c.id}`, { status: 'rejected', reviewed_at: new Date().toISOString() }), 'Dismissed')) await load(); } }, 'Dismiss'))])),
    );
  };
  root.append(h('div', { class: 'toolbar' }, h('h2', {}, 'Verification queue'), h('button', { onclick: () => guarded(load) }, 'Refresh')), box);
  await guarded(load);
}
