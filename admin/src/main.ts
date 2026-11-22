// Mauqa admin dashboard entry point: sign-in, role gate, hash routing.
import { Api, type AdminConfig } from './api.ts';
import { clear, guarded, h, toast } from './dom.ts';
import { opportunitiesPage, reviewPage } from './pages_opportunities.ts';
import { analyticsPage, contentPage, dashboardPage, moderationPage, sourcesPage, usersPage } from './pages_admin.ts';

declare global { interface Window { MAUQA_ADMIN_CONFIG?: AdminConfig } }

const STAFF = ['admin', 'super_admin', 'verifier', 'content_manager'];
type Page = { title: string; roles: string[]; render: (api: Api, root: HTMLElement, roles: string[]) => Promise<void> };
const PAGES: Record<string, Page> = {
  dashboard: { title: 'Dashboard', roles: STAFF, render: dashboardPage },
  opportunities: { title: 'Opportunities', roles: ['admin', 'super_admin', 'verifier', 'content_manager'], render: opportunitiesPage },
  review: { title: 'Verification', roles: ['admin', 'super_admin', 'verifier'], render: reviewPage },
  sources: { title: 'Data sources', roles: STAFF, render: sourcesPage },
  moderation: { title: 'Moderation', roles: STAFF, render: moderationPage },
  users: { title: 'Users', roles: ['admin', 'super_admin'], render: usersPage },
  content: { title: 'Content', roles: ['admin', 'super_admin', 'content_manager'], render: contentPage },
  analytics: { title: 'Analytics', roles: STAFF, render: analyticsPage },
};

const app = document.getElementById('app')!;
const cfg = window.MAUQA_ADMIN_CONFIG;

function loginView(api: Api) {
  clear(app);
  const email = h('input', { type: 'email', placeholder: 'Email', autocomplete: 'username', required: true }) as HTMLInputElement;
  const pw = h('input', { type: 'password', placeholder: 'Password', autocomplete: 'current-password', required: true }) as HTMLInputElement;
  const form = h('form', { class: 'login', onsubmit: async (e: Event) => {
    e.preventDefault();
    if (await guarded(() => api.signIn(email.value.trim(), pw.value))) await boot(api);
  } }, h('div', { class: 'logo' }, 'Mauqa ', h('span', {}, 'Admin')), email, pw, h('button', { class: 'primary', type: 'submit' }, 'Sign in'),
    h('p', { class: 'muted small' }, 'Staff accounts only. Access is controlled by roles in the database.'));
  app.append(form);
}

async function boot(api: Api) {
  if (!api.session) return loginView(api);
  let roles: string[] = [];
  try { roles = await api.rpc<string[]>('my_roles'); } catch { api.signOut(); return loginView(api); }
  if (!roles.some((r) => STAFF.includes(r))) {
    api.signOut();
    toast('This account does not have staff access.', 'error');
    return loginView(api);
  }
  clear(app);
  const nav = h('nav', {}, h('div', { class: 'logo' }, 'Mauqa ', h('span', {}, 'Admin')),
    Object.entries(PAGES).filter(([, p]) => p.roles.some((r) => roles.includes(r))).map(([k, p]) => h('a', { href: `#/${k}`, 'data-page': k }, p.title)),
    h('div', { class: 'me' }, h('div', { class: 'small' }, api.session.user.email ?? ''), h('div', { class: 'small muted' }, roles.join(', ')),
      h('button', { class: 'ghost', onclick: () => { api.signOut(); loginView(api); } }, 'Sign out')));
  const main = h('main');
  app.append(nav, main);
  const route = async () => {
    const key = (location.hash.replace(/^#\//, '') || 'dashboard').split('?')[0];
    const page = PAGES[key] && PAGES[key].roles.some((r) => roles.includes(r)) ? PAGES[key] : PAGES.dashboard;
    nav.querySelectorAll('a').forEach((a) => a.classList.toggle('active', a.getAttribute('data-page') === key));
    clear(main);
    main.append(h('p', { class: 'muted' }, 'Loading…'));
    const content = h('div');
    try {
      await page.render(api, content, roles);
      clear(main);
      main.append(content);
    } catch (e) {
      clear(main);
      main.append(h('p', { class: 'bad' }, e instanceof Error ? e.message : String(e)), h('button', { onclick: route }, 'Retry'));
    }
  };
  window.onhashchange = route;
  await route();
}

if (!cfg?.supabaseUrl || !cfg.anonKey) {
  app.append(h('div', { class: 'login' }, h('h2', {}, 'Configuration missing'),
    h('p', {}, 'Copy admin/config.example.js to admin/config.js and set your Supabase URL and anon key.')));
} else {
  void boot(new Api(cfg, window.localStorage));
}
