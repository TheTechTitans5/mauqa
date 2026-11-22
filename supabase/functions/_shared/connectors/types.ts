import type { DraftOpportunity } from '../dedupe.ts';
import type { FetchLike } from '../rest.ts';

export interface DataSourceRow {
  id: string;
  organization_id: string | null;
  name: string;
  source_type: 'api' | 'rss' | 'web_monitor' | 'pdf' | 'manual';
  base_url: string | null;
  config: Record<string, unknown>;
  auth_method: 'none' | 'api_key_header' | 'bearer_token' | 'basic' | 'oauth2_client_credentials';
  secret_ref: string | null;
  integration_status: 'awaiting_authorization' | 'awaiting_configuration' | 'active' | 'paused' | 'error';
  rate_limit_per_minute: number;
  sync_interval_minutes: number;
  is_enabled: boolean;
  consecutive_failures: number;
  terms_reviewed_at: string | null;
  robots_txt_checked_at: string | null;
}

export interface RawItem {
  externalId: string;
  url: string | null;
  raw: Record<string, unknown>;
  draft: DraftOpportunity;
}

export interface ConnectorContext {
  fetch: FetchLike;
  sleep: (ms: number) => Promise<void>;
  log: (msg: string, data?: unknown) => void;
  now: () => Date;
}

export interface Connector {
  /** Throws ConnectorConfigError when the source is not configured/authorised. */
  validateConfig(source: DataSourceRow): void;
  fetchItems(source: DataSourceRow, ctx: ConnectorContext): Promise<RawItem[]>;
}

export class ConnectorConfigError extends Error {
  constructor(msg: string) { super(msg); this.name = 'ConnectorConfigError'; }
}
export class ConnectorBlockedError extends Error {
  constructor(msg: string) { super(msg); this.name = 'ConnectorBlockedError'; }
}
