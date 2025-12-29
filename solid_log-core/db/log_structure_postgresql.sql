-- SolidLog Database Structure for PostgreSQL
-- Generated from migrations in db/log_migrate/

-- solid_log_raw: Fast ingestion table for raw log payloads
CREATE TABLE solid_log_raw (
  id BIGSERIAL PRIMARY KEY,
  received_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  token_id BIGINT NOT NULL,
  payload TEXT NOT NULL,
  parsed BOOLEAN NOT NULL DEFAULT FALSE,
  parsed_at TIMESTAMP
);

CREATE INDEX idx_raw_unparsed ON solid_log_raw(parsed, received_at);
CREATE INDEX idx_raw_token ON solid_log_raw(token_id);
CREATE INDEX idx_raw_received ON solid_log_raw(received_at);

-- solid_log_entries: Parsed and indexed log entries for querying
CREATE TABLE solid_log_entries (
  id BIGSERIAL PRIMARY KEY,
  raw_id BIGINT NOT NULL,
  timestamp TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL,
  level VARCHAR(255) NOT NULL,
  app VARCHAR(255),
  env VARCHAR(255),
  message TEXT,
  request_id VARCHAR(255),
  job_id VARCHAR(255),
  duration DOUBLE PRECISION,
  status_code INTEGER,
  controller VARCHAR(255),
  action VARCHAR(255),
  path VARCHAR(255),
  method VARCHAR(255),
  extra_fields TEXT,
  fts_vector TSVECTOR
);

CREATE INDEX idx_entries_timestamp ON solid_log_entries(timestamp DESC);
CREATE INDEX idx_entries_level ON solid_log_entries(level);
CREATE INDEX idx_entries_app_env_time ON solid_log_entries(app, env, timestamp DESC);
CREATE INDEX idx_entries_request ON solid_log_entries(request_id);
CREATE INDEX idx_entries_job ON solid_log_entries(job_id);
CREATE INDEX idx_entries_raw ON solid_log_entries(raw_id);

-- Full-text search index using tsvector and GIN
CREATE INDEX idx_entries_fts ON solid_log_entries USING GIN(fts_vector);

-- Trigger to auto-update FTS vector
CREATE OR REPLACE FUNCTION solid_log_entries_fts_trigger() RETURNS trigger AS $$
BEGIN
  NEW.fts_vector :=
    setweight(to_tsvector('english', COALESCE(NEW.message, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.extra_fields, '')), 'B');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER solid_log_entries_fts_update
  BEFORE INSERT OR UPDATE ON solid_log_entries
  FOR EACH ROW EXECUTE FUNCTION solid_log_entries_fts_trigger();

-- solid_log_fields: Field registry for tracking dynamic JSON fields
CREATE TABLE solid_log_fields (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  field_type VARCHAR(255) NOT NULL,
  filter_type VARCHAR(255) NOT NULL DEFAULT 'multiselect',
  usage_count INTEGER NOT NULL DEFAULT 0,
  last_seen_at TIMESTAMP,
  promoted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_fields_name ON solid_log_fields(name);
CREATE INDEX idx_fields_promoted ON solid_log_fields(promoted);
CREATE INDEX idx_fields_usage ON solid_log_fields(usage_count);

-- solid_log_tokens: API tokens for log ingestion authentication
CREATE TABLE solid_log_tokens (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  token_hash VARCHAR(255) NOT NULL,
  last_used_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_tokens_hash ON solid_log_tokens(token_hash);
CREATE INDEX idx_tokens_name ON solid_log_tokens(name);

-- solid_log_facet_cache: Cache for filter options to reduce DB load
CREATE TABLE solid_log_facet_cache (
  id BIGSERIAL PRIMARY KEY,
  key_name VARCHAR(255) NOT NULL,
  cache_value TEXT NOT NULL,
  expires_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_facet_key_name ON solid_log_facet_cache(key_name);
CREATE INDEX idx_facet_expires ON solid_log_facet_cache(expires_at);

-- Schema migrations
CREATE TABLE IF NOT EXISTS schema_migrations (
  version VARCHAR(255) PRIMARY KEY
);

INSERT INTO schema_migrations (version) VALUES
  ('20251222000001'),
  ('20251222000002'),
  ('20251222000004'),
  ('20251222000005'),
  ('20251222000006'),
  ('20251222000007');
