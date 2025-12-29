-- SolidLog Database Structure for MySQL
-- Generated from migrations in db/log_migrate/

-- solid_log_raw: Fast ingestion table for raw log payloads
CREATE TABLE solid_log_raw (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  received_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  token_id BIGINT NOT NULL,
  payload TEXT NOT NULL,
  parsed TINYINT(1) NOT NULL DEFAULT 0,
  parsed_at DATETIME,
  INDEX idx_raw_unparsed (parsed, received_at),
  INDEX idx_raw_token (token_id),
  INDEX idx_raw_received (received_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- solid_log_entries: Parsed and indexed log entries for querying
CREATE TABLE solid_log_entries (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  raw_id BIGINT NOT NULL,
  timestamp DATETIME NOT NULL,
  created_at DATETIME NOT NULL,
  level VARCHAR(255) NOT NULL,
  app VARCHAR(255),
  env VARCHAR(255),
  message TEXT,
  request_id VARCHAR(255),
  job_id VARCHAR(255),
  duration DOUBLE,
  status_code INT,
  controller VARCHAR(255),
  action VARCHAR(255),
  path VARCHAR(255),
  method VARCHAR(255),
  extra_fields TEXT,
  INDEX idx_entries_timestamp (timestamp DESC),
  INDEX idx_entries_level (level),
  INDEX idx_entries_app_env_time (app, env, timestamp DESC),
  INDEX idx_entries_request (request_id),
  INDEX idx_entries_job (job_id),
  INDEX idx_entries_raw (raw_id),
  FULLTEXT INDEX idx_entries_fts (message, extra_fields)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- solid_log_fields: Field registry for tracking dynamic JSON fields
CREATE TABLE solid_log_fields (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  field_type VARCHAR(255) NOT NULL,
  filter_type VARCHAR(255) NOT NULL DEFAULT 'multiselect',
  usage_count INT NOT NULL DEFAULT 0,
  last_seen_at DATETIME,
  promoted TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE INDEX idx_fields_name (name),
  INDEX idx_fields_promoted (promoted),
  INDEX idx_fields_usage (usage_count)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- solid_log_tokens: API tokens for log ingestion authentication
CREATE TABLE solid_log_tokens (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  token_hash VARCHAR(255) NOT NULL,
  last_used_at DATETIME,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE INDEX idx_tokens_hash (token_hash),
  INDEX idx_tokens_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- solid_log_facet_cache: Cache for filter options to reduce DB load
CREATE TABLE solid_log_facet_cache (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  key_name VARCHAR(255) NOT NULL,
  cache_value TEXT NOT NULL,
  expires_at DATETIME,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE INDEX idx_facet_key_name (key_name),
  INDEX idx_facet_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Schema migrations
CREATE TABLE IF NOT EXISTS schema_migrations (
  version VARCHAR(255) PRIMARY KEY
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO schema_migrations (version) VALUES
  ('20251222000001'),
  ('20251222000002'),
  ('20251222000004'),
  ('20251222000005'),
  ('20251222000006'),
  ('20251222000007');
