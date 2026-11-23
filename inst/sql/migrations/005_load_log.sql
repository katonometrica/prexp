-- 005_load_log.sql: one row per load attempt (spec sections 3.2 and 4).
--
-- An attempt starts as 'running' and ends 'loaded' or 'failed'. When a month
-- is loaded again, its previous 'loaded' row becomes 'replaced', in the same
-- transaction as the swap, so a month has at most one 'loaded' row: the data
-- that is live. A failed reload leaves the live row alone. A month dropped from
-- the window becomes 'dropped'. The window is the months with a 'loaded' row.
--
-- source_url is the resource's stable CSV link, never the signed ZIP link.
-- source_sha256 is the resource's published hash of the CSV; a changed hash
-- means the month was re-published.

CREATE TABLE core.load_log (
  load_id int4 GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  year_month int4 NOT NULL,
  source_url text,
  source_sha256 text,
  source_rows int8,
  loaded_rows int8,
  file_bytes int8,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  status text NOT NULL DEFAULT 'running'
    CHECK (status IN ('running', 'loaded', 'failed', 'replaced', 'dropped')),
  error text
);

CREATE UNIQUE INDEX load_log_live_month ON core.load_log (year_month)
  WHERE status = 'loaded';
CREATE INDEX load_log_month_idx ON core.load_log (year_month, started_at);
