-- DESTRUCTIVE schema cutover: run only while existing rows are disposable.
DROP TABLE IF EXISTS native_apps.macos_browser_health_nav_to_lcp_attempts
ON CLUSTER `ch-prod-cluster`
SYNC;

-- One row per workflow run, browser, and requested domain. This companion to
-- native_apps.macos_browser_health_nav_to_lcp answers whether a site was
-- eligible and measured, and why a requested site has no metrics row.
CREATE TABLE native_apps.macos_browser_health_nav_to_lcp_attempts
ON CLUSTER `ch-prod-cluster`
(
    run_id UInt64
        COMMENT 'GitHub Actions workflow run ID; stable across retries of the same workflow run',
    start_time DateTime
        COMMENT 'Workflow kickoff time in UTC; identical for every site in the run',
    date Date MATERIALIZED toDate(start_time)
        COMMENT 'UTC partition date derived from start_time',

    domain LowCardinality(String)
        COMMENT 'Requested site hostname, not a redirected or final URL',
    webview_type LowCardinality(String)
        COMMENT 'Stable browser and harness code shared with the metrics table, such as chr-wpr',
    webview_channel LowCardinality(String)
        COMMENT 'Browser release channel, such as stable, beta, dev, or canary',
    webview_version String
        COMMENT 'Full browser version reported by the runner',

    outcome LowCardinality(String)
        COMMENT 'Overall result: measured=all requested samples recorded; partial=some recorded; no_samples=measurement ran without a usable sample; excluded=WPR validation failed; infra_error=harness failed',

    validation_status LowCardinality(String)
        COMMENT 'WPR archive eligibility result: ok or error',
    validation_reason LowCardinality(String)
        COMMENT 'Stable machine-readable reason code, such as archive_missing, archive_corrupt, or http_403; empty when validation_status is ok',
    validation_http_status Nullable(UInt16)
        COMMENT 'Recorded main-document HTTP error status when applicable; NULL otherwise',
    validation_detail String
        COMMENT 'Sanitized diagnostic detail for investigation; empty when unnecessary',
    archive_sha256 Nullable(FixedString(64))
        COMMENT 'SHA-256 of the WPR archive bytes; NULL when the archive was absent or its identity was unavailable',

    failure_stage LowCardinality(String)
        COMMENT 'Stable harness stage that failed after validation, such as crossbench; empty when no runtime infrastructure failure was identified',
    failure_reason LowCardinality(String)
        COMMENT 'Stable machine-readable runtime failure code, such as site_timeout; empty when no runtime infrastructure failure was identified',
    failure_detail String
        COMMENT 'Bounded sanitized runtime diagnostic detail for investigation; empty when unnecessary',

    requested_repetitions UInt32
        COMMENT 'Configured repetitions for this requested site, including sites excluded before browser launch',
    observed_repetitions UInt32
        COMMENT 'Repetitions that produced probe output',
    recorded_samples UInt32
        COMMENT 'Repetitions that yielded a usable LCP sample and contribute to the metrics table',
    dropped_unfinalized UInt32
        COMMENT 'Observed repetitions with no finalized LCP inside load_window_ms',
    dropped_no_metric UInt32
        COMMENT 'Observed repetitions whose probe output contained no usable LCP metric',

    load_window_ms UInt32
        COMMENT 'Per-load measurement window in milliseconds',
    runner_image String
        COMMENT 'Runner OS image identifier retained after GitHub logs expire',

    gh_run_started_at DateTime
        COMMENT 'Current GitHub run-attempt start time in UTC; ReplacingMergeTree version',
    gh_run_conclusion LowCardinality(String)
        COMMENT 'GitHub job conclusion, such as success, failure, cancelled, timed_out, or skipped'
)
ENGINE = ReplicatedReplacingMergeTree(
    '/clickhouse/tables/{shard}/db_uuid/{uuid}',
    '{replica}',
    gh_run_started_at
)
PARTITION BY date
ORDER BY (webview_type, webview_channel, domain, run_id)
TTL start_time + toIntervalDay(365)
SETTINGS index_granularity = 8192;

-- Coverage and exclusions, most recent first:
--
-- SELECT date, domain, webview_type, outcome, validation_reason, failure_reason,
--        validation_http_status, archive_sha256, recorded_samples,
--        requested_repetitions
-- FROM native_apps.macos_browser_health_nav_to_lcp_attempts
-- WHERE outcome != 'measured'
-- ORDER BY date DESC, domain;
--
-- Measurement coverage by browser:
--
-- SELECT date, webview_type, sum(recorded_samples) AS recorded,
--        sum(requested_repetitions) AS requested,
--        round(recorded / requested, 3) AS end_to_end_coverage
-- FROM native_apps.macos_browser_health_nav_to_lcp_attempts
-- WHERE requested_repetitions > 0
-- GROUP BY date, webview_type
-- ORDER BY date DESC, webview_type;
