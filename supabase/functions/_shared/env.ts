// Environment access that works in Deno (Edge Functions) and Node (tests).
// Secrets are read ONLY on the server. Never ship any of these values in the Flutter app.

declare const Deno: { env: { get(k: string): string | undefined } } | undefined;
declare const process: { env: Record<string, string | undefined> } | undefined;

export function env(name: string): string | undefined {
  try {
    if (typeof Deno !== 'undefined' && Deno?.env) return Deno.env.get(name);
  } catch { /* permission denied in some contexts */ }
  if (typeof process !== 'undefined' && process?.env) return process.env[name];
  return undefined;
}

export function requireEnv(name: string): string {
  const v = env(name);
  if (!v) throw new ConfigError(`Missing required environment variable ${name}`);
  return v;
}

export class ConfigError extends Error {
  constructor(msg: string) { super(msg); this.name = 'ConfigError'; }
}

/** Secret references stored in data_sources.secret_ref must look like env var names. */
export function readSecretRef(ref: string | null | undefined): string | undefined {
  if (!ref) return undefined;
  if (!/^[A-Z][A-Z0-9_]{2,63}$/.test(ref)) throw new ConfigError('Invalid secret reference name');
  if (/^(SUPABASE_|SERVICE_ROLE|CRON_SECRET)/.test(ref)) throw new ConfigError('Connector secrets cannot reference platform secrets');
  return env(ref);
}
