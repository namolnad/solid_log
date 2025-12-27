CREATE TABLE IF NOT EXISTS "solid_log_raw" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "payload" text NOT NULL, "token_id" integer, "parsed" boolean DEFAULT 0 NOT NULL, "received_at" datetime(6) NOT NULL, "parsed_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE INDEX "idx_raw_unparsed" ON "solid_log_raw" ("parsed", "received_at") /*application='Dummy'*/;
CREATE INDEX "idx_raw_received" ON "solid_log_raw" ("received_at") /*application='Dummy'*/;
CREATE INDEX "idx_raw_token" ON "solid_log_raw" ("token_id") /*application='Dummy'*/;
CREATE TABLE IF NOT EXISTS "solid_log_entries" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "raw_id" integer NOT NULL, "timestamp" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, "level" varchar NOT NULL, "app" varchar, "env" varchar, "message" text, "request_id" varchar, "job_id" varchar, "duration" float, "status_code" integer, "controller" varchar, "action" varchar, "path" varchar, "method" varchar, "extra_fields" text);
CREATE INDEX "idx_entries_app_env_time" ON "solid_log_entries" ("app", "env", "timestamp" DESC) /*application='Dummy'*/;
CREATE INDEX "idx_entries_timestamp" ON "solid_log_entries" ("timestamp" DESC) /*application='Dummy'*/;
CREATE INDEX "idx_entries_job" ON "solid_log_entries" ("job_id") /*application='Dummy'*/;
CREATE INDEX "idx_entries_level" ON "solid_log_entries" ("level") /*application='Dummy'*/;
CREATE INDEX "idx_entries_raw" ON "solid_log_entries" ("raw_id") /*application='Dummy'*/;
CREATE INDEX "idx_entries_request" ON "solid_log_entries" ("request_id") /*application='Dummy'*/;
CREATE TABLE IF NOT EXISTS "solid_log_fields" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "field_type" varchar NOT NULL, "filter_type" varchar DEFAULT 'multiselect' NOT NULL, "usage_count" integer DEFAULT 0 NOT NULL, "last_seen_at" datetime(6), "promoted" boolean DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "idx_fields_name" ON "solid_log_fields" ("name") /*application='Dummy'*/;
CREATE INDEX "idx_fields_promoted" ON "solid_log_fields" ("promoted") /*application='Dummy'*/;
CREATE INDEX "idx_fields_usage" ON "solid_log_fields" ("usage_count") /*application='Dummy'*/;
CREATE TABLE IF NOT EXISTS "solid_log_tokens" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "token_hash" varchar NOT NULL, "last_used_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE INDEX "idx_tokens_name" ON "solid_log_tokens" ("name") /*application='Dummy'*/;
CREATE UNIQUE INDEX "idx_tokens_hash" ON "solid_log_tokens" ("token_hash") /*application='Dummy'*/;
CREATE TABLE IF NOT EXISTS "solid_log_facet_cache" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key_name" varchar NOT NULL, "cache_value" text NOT NULL, "expires_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE INDEX "idx_facet_expires" ON "solid_log_facet_cache" ("expires_at") /*application='Dummy'*/;
CREATE UNIQUE INDEX "idx_facet_key_name" ON "solid_log_facet_cache" ("key_name") /*application='Dummy'*/;
CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE VIRTUAL TABLE solid_log_entries_fts USING fts5(
  message,
  extra_fields,
  content='solid_log_entries',
  content_rowid='id'
)
/* solid_log_entries_fts(message,extra_fields) */;
CREATE TABLE IF NOT EXISTS 'solid_log_entries_fts_data'(id INTEGER PRIMARY KEY, block BLOB);
CREATE TABLE IF NOT EXISTS 'solid_log_entries_fts_idx'(segid, term, pgno, PRIMARY KEY(segid, term)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS 'solid_log_entries_fts_docsize'(id INTEGER PRIMARY KEY, sz BLOB);
CREATE TABLE IF NOT EXISTS 'solid_log_entries_fts_config'(k PRIMARY KEY, v) WITHOUT ROWID;
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
INSERT INTO "schema_migrations" (version) VALUES
('20251224213313'),
('0');

