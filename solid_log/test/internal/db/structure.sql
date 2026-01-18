-- SolidLog Database Structure for SQLite
-- Generated from migrations in db/log_migrate/

-- solid_log_raw: Fast ingestion table for raw log payloads
CREATE TABLE solid_log_raw (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  received_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  token_id INTEGER NOT NULL,
  payload TEXT NOT NULL,
  parsed BOOLEAN NOT NULL DEFAULT 0,
  parsed_at DATETIME
);

CREATE INDEX idx_raw_unparsed ON solid_log_raw(parsed, received_at);
CREATE INDEX idx_raw_token ON solid_log_raw(token_id);
CREATE INDEX idx_raw_received ON solid_log_raw(received_at);

-- solid_log_entries: Parsed and indexed log entries for querying
CREATE TABLE solid_log_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  raw_id INTEGER NOT NULL,
  timestamp DATETIME NOT NULL,
  created_at DATETIME NOT NULL,
  level VARCHAR(255) NOT NULL,
  app VARCHAR(255),
  env VARCHAR(255),
  message TEXT,
  request_id VARCHAR(255),
  job_id VARCHAR(255),
  duration REAL,
  status_code INTEGER,
  controller VARCHAR(255),
  action VARCHAR(255),
  path VARCHAR(255),
  method VARCHAR(255),
  extra_fields TEXT
);

CREATE INDEX idx_entries_timestamp ON solid_log_entries(timestamp DESC);
CREATE INDEX idx_entries_level ON solid_log_entries(level);
CREATE INDEX idx_entries_app_env_time ON solid_log_entries(app, env, timestamp DESC);
CREATE INDEX idx_entries_request ON solid_log_entries(request_id);
CREATE INDEX idx_entries_job ON solid_log_entries(job_id);
CREATE INDEX idx_entries_raw ON solid_log_entries(raw_id);

-- solid_log_fields: Field registry for tracking dynamic JSON fields
CREATE TABLE solid_log_fields (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name VARCHAR(255) NOT NULL,
  field_type VARCHAR(255) NOT NULL,
  filter_type VARCHAR(255) NOT NULL DEFAULT 'multiselect',
  usage_count INTEGER NOT NULL DEFAULT 0,
  last_seen_at DATETIME,
  promoted BOOLEAN NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_fields_name ON solid_log_fields(name);
CREATE INDEX idx_fields_promoted ON solid_log_fields(promoted);
CREATE INDEX idx_fields_usage ON solid_log_fields(usage_count);

-- solid_log_tokens: API tokens for log ingestion authentication
CREATE TABLE solid_log_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name VARCHAR(255) NOT NULL,
  token_hash VARCHAR(255) NOT NULL,
  last_used_at DATETIME,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_tokens_hash ON solid_log_tokens(token_hash);
CREATE INDEX idx_tokens_name ON solid_log_tokens(name);

-- solid_log_facet_cache: Cache for filter options to reduce DB load
CREATE TABLE solid_log_facet_cache (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  key_name VARCHAR(255) NOT NULL,
  cache_value TEXT NOT NULL,
  expires_at DATETIME,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_facet_key_name ON solid_log_facet_cache(key_name);
CREATE INDEX idx_facet_expires ON solid_log_facet_cache(expires_at);

-- Full-Text Search (SQLite FTS5)
CREATE VIRTUAL TABLE solid_log_entries_fts USING fts5(
  message,
  extra_fields,
  content='solid_log_entries',
  content_rowid='id'
);

CREATE TRIGGER solid_log_entries_fts_insert AFTER INSERT ON solid_log_entries BEGIN
  INSERT INTO solid_log_entries_fts(rowid, message, extra_fields)
  VALUES (new.id, new.message, new.extra_fields);
END;

CREATE TRIGGER solid_log_entries_fts_update AFTER UPDATE ON solid_log_entries BEGIN
  UPDATE solid_log_entries_fts
  SET message = new.message, extra_fields = new.extra_fields
  WHERE rowid = new.id;
END;

CREATE TRIGGER solid_log_entries_fts_delete AFTER DELETE ON solid_log_entries BEGIN
  DELETE FROM solid_log_entries_fts WHERE rowid = old.id;
END;

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
