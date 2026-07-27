-- native_apps.macos_browser_health_nav_to_lcp_attempts
--
-- Companion to native_apps.macos_browser_health_nav_to_lcp: one row per
-- run x domain x browser answering "did we actually measure this site, and if
-- not, why not". Same naming and key shape as that table, so the two join on
-- (webview_type, webview_channel, domain, run_id).
--
-- macOS only, like its metrics sibling. The Windows harness has its own tables
-- and is not written to or read from here.
--
-- The columns are grouped by the STAGE the failure happened in, because the two
-- stages fail for unrelated reasons and get confused otherwise:
--
--   Stage 1 — pre-flight (curl, before the browser starts). A whole-site
--   decision. `preflight_*` columns. A blocked verdict means the browser never
--   ran: attempted = 0 and there is no metrics row for the domain at all.
--
--   Stage 2 — measurement (the browser ran the site N times). A per-repetition
--   accounting. `attempted` / `observed` / `recorded` / `dropped_*`. The site
--   loaded fine; individual repetitions still failed to yield a number.
--
-- `outcome` collapses both stages into the one column you group by day-to-day;
-- the stage columns are there to explain it.
--
-- Why a separate table rather than columns on the metrics table:
--   1. The metrics table is a ReplacingMergeTree keyed on
--      (webview_type, webview_channel, domain, run_id). A disposition row and a
--      metrics row for the same domain in the same run would share that key and
--      be collapsed into one, which breaks the case that matters most —
--      "3 of 5 reps recorded, 2 dropped because X" needs the metric AND the
--      reason to coexist.
--   2. A totally failed domain produces no metrics row at all, so there is
--      nothing to attach columns to. Without this table such a domain is simply
--      absent, which is indistinguishable from "that run never tested it".
--   3. Altering the macOS metrics table would break its shape symmetry with the
--      Windows sibling.
--
-- Populated by aggregate-dispositions.py from the disposition TSV that
-- test-safari.sh / test-chrome.sh emit.

-- ON CLUSTER is required, not optional: the engine path below uses the {uuid}
-- macro, and ClickHouse only expands that inside an ON CLUSTER query (or a
-- Replicated database). Without it the server rejects the statement with
-- BAD_ARGUMENTS. The metrics tables were created the same way — SHOW CREATE
-- doesn't echo the ON CLUSTER clause back, so their DDL looks like it lacks it.
CREATE TABLE IF NOT EXISTS native_apps.macos_browser_health_nav_to_lcp_attempts ON CLUSTER `ch-prod-cluster`
(
    `run_id` UInt64 COMMENT 'GitHub Actions workflow run id (duckduckgo/apple-browsers)',
    `start_time` DateTime COMMENT 'Source kickoff time (UTC); identical for all rows in a run',
    `date` Date DEFAULT toDate(start_time) COMMENT 'Partition key',
    `domain` LowCardinality(String) COMMENT 'Target domain as requested (not as landed)',
    `webview_type` LowCardinality(String) COMMENT 'chr / sfr',
    `webview_channel` LowCardinality(String) COMMENT 'stable / beta / dev / canary',
    `webview_version` String COMMENT 'Browser version string from the run',

    -- Overall verdict, both stages collapsed. The column to GROUP BY.
    --   measured        every intended repetition produced a sample
    --   partial         some repetitions produced samples, some were dropped
    --   no_samples      the site loaded but no repetition produced a sample
    --   skipped_blocked pre-flight said the site is not serving us the page;
    --                   the browser never ran (attempted = 0)
    --   infra_error     the harness itself failed for this site
    `outcome` LowCardinality(String) COMMENT 'measured / partial / no_samples / skipped_blocked / infra_error',

    -- ---- Stage 1: out-of-browser pre-flight (curl) -------------------------
    -- Describes ONLY the pre-flight request. Replay runners do not make that
    -- live-network request and write `not_run`. Whether measurement succeeded
    -- is recorded separately in `outcome`.
    `preflight_verdict` LowCardinality(String) COMMENT 'not_run / ok / blocked_status / blocked_marker / preflight_error',
    `http_status` Int32 COMMENT 'Final HTTP status seen by the pre-flight; -1 when unknown',
    `status_chain` String COMMENT 'Comma-separated status chain incl. redirects, e.g. "301,403"',
    `redirect_count` Int32 COMMENT 'Redirects followed by the pre-flight; -1 when unknown',
    `final_url` String COMMENT 'URL the pre-flight landed on after redirects',
    `landed_offsite` UInt8 COMMENT '1 when final_url is not on the requested domain (consent wall, country variant, login); saves re-deriving host matching per query',
    `preflight_bytes` Int64 COMMENT 'Response body size of the pre-flight; the evidence for auditing a suspected false-positive blocked_marker; -1 when unknown',
    `blocked_marker` String COMMENT 'Bot-wall phrase matched in the response body, empty when none',

    -- ---- Stage 2: per-repetition measurement -------------------------------
    -- attempted >= observed >= recorded + dropped_*. A gap between attempted and
    -- observed means the browser/harness stopped early; the dropped_* counters
    -- account for everything observed but unusable.
    `attempted` UInt32 COMMENT 'Repetitions the run intended to measure; 0 when skipped at pre-flight',
    `observed` UInt32 COMMENT 'Repetitions that produced probe output at all',
    `recorded` UInt32 COMMENT 'Repetitions that yielded a usable sample; 0 means the domain has no metrics row',
    `dropped_unfinalized` UInt32 COMMENT 'No LCP entry within the load window — right-censored, i.e. the page is slower than the window, not fast',
    `dropped_no_metric` UInt32 COMMENT 'Probe ran but wrote no metric (probe/JS failure)',
    `dropped_http_error` UInt32 COMMENT 'In-page status said HTTP >= 400; always 0 today, neither browser exposes it',

    -- ---- Run context -------------------------------------------------------
    `load_window_ms` UInt32 COMMENT 'Dwell time per load. dropped_unfinalized is only comparable across runs with the same window',
    `runner_image` String COMMENT 'Runner OS image identity; GitHub run logs expire in 90 days, these rows live 365',

    `gh_run_started_at` DateTime COMMENT 'GitHub Actions run wall-clock time (UTC); ReplacingMergeTree version column',
    `gh_run_conclusion` LowCardinality(String) COMMENT 'success / failure / cancelled / timed_out / skipped'
)
ENGINE = ReplicatedReplacingMergeTree('/clickhouse/tables/{shard}/db_uuid/{uuid}', '{replica}', gh_run_started_at)
PARTITION BY date
ORDER BY (webview_type, webview_channel, domain, run_id)
TTL start_time + toIntervalDay(365)
SETTINGS index_granularity = 8192;

-- Everything that isn't a clean measurement, most recent first:
--
--   SELECT date, domain, webview_type, outcome, preflight_verdict, status_chain,
--          recorded, attempted, dropped_unfinalized, dropped_no_metric
--   FROM native_apps.macos_browser_health_nav_to_lcp_attempts
--   WHERE outcome != 'measured'
--   ORDER BY date DESC, domain;
--
-- When did a site start refusing the runner?
--
--   SELECT min(date) AS since, domain, http_status, any(blocked_marker) AS marker
--   FROM native_apps.macos_browser_health_nav_to_lcp_attempts
--   WHERE outcome = 'skipped_blocked'
--   GROUP BY domain, http_status ORDER BY since;
--
-- Which domains are slower than the load window rather than blocked? A high
-- dropped_unfinalized share means the recorded LCPs for that domain are
-- right-censored and its p95 is optimistic.
--
--   SELECT domain, sum(dropped_unfinalized) AS censored, sum(observed) AS ran,
--          round(censored / ran, 3) AS share
--   FROM native_apps.macos_browser_health_nav_to_lcp_attempts
--   WHERE date >= today() - 30 AND observed > 0
--   GROUP BY domain HAVING censored > 0
--   ORDER BY share DESC;
