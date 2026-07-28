# macOS crossbench — Chrome LCP with WPR

Measures Chrome navigation-to-LCP on macOS using fixed Web Page Replay archives
and the same US-broadband profile as the Windows harness:

- 28 ms RTT
- 50,000 Kbps downstream
- 10,000 Kbps upstream
- TCP window 10

There is no live-network fallback or live-site curl pre-check. Before any
browser runner starts, CI downloads the selected WPR archive set and parses the
stored top-level navigations directly. Each configured site is classified as
`ok` or `error`. Only `ok` archives enter measurement. Stored HTTP errors,
incomplete redirects, unexpected destinations, non-HTML pages, recognizable
block pages, missing archives, and corrupt archives exclude that individual
site and are included in the consolidated report.

The package-level result is separate. Site errors do not prevent the remaining
valid sites from running. If validation infrastructure fails or no configured
site is eligible, package validation fails and browser jobs do not start.

The reusable validation workflow publishes an actionable report and the exact
replayable archives. Browser workflows consume that artifact instead of
downloading the files again.

## Layout

| File | Purpose |
|------|---------|
| `.github/workflows/wpr_archive_validation.yml` | Reusable validation and consolidated alerting for every browser workflow. |
| `provision-macos.sh` | Installs Chrome, Python 3.11, Poetry, a pinned crossbench checkout, the LCP extras, a pinned WPR binary, and a checksum-verified tsproxy. |
| `provision-wpr-tools.sh` | Builds requested WPR tools from the crossbench-pinned WPR revision. |
| `validate-wpr-archives.sh` | Downloads the complete selected archive set and produces its validation report and manifest. |
| `validate-wpr.go` | Parses stored WPR requests and responses without starting a replay server. |
| `wpr-sites.txt` | Single default site list shared by validation and the browser run. |
| `test-chrome.sh` | Runs Chrome through the validated WPR archives and tsproxy, and writes per-repetition results and per-site dispositions. |
| `run-with-watchdog.py` | Bounds one Crossbench site process group and terminates it on timeout. |
| `aggregate-lcp.py` | Produces per-domain ClickHouse metric rows. |
| `aggregate-dispositions.py` | Validates and encodes ClickHouse eligibility and measurement-outcome rows for every requested site. |
| `attempts-schema.sql` | Destructive recreation SQL for the attempts-table schema cutover. |
| `crossbench-extras/` | Supplies the `navToLCP` probe config and LCP SQL module missing from the upstream checkout. |
| `patches/` | Contains the Apple Silicon `cpu_freq` compatibility fix. |

## Prerequisites

- Xcode Command Line Tools
- Homebrew at `/opt/homebrew`

Everything else is installed by `provision-macos.sh`.

## Usage

```sh
./provision-macos.sh
./test-chrome.sh

# Small validation run:
./test-chrome.sh --sites apple.com --reps 1
```

The manual CI workflow also accepts a `reps` input. Scheduled runs retain the
10-load default; use a smaller value for validation runs.

CI can create one write-only Asana subtask for archive-validation errors and one
for browser-measurement errors per workflow run under task `1216902374642227`.
It uses `ASANA_ACCESS_TOKEN` only to create subtasks and never reads Asana.
GitHub artifacts provide best-effort deduplication without querying Asana.
Alerting defaults on and can be disabled for a manual run with `alert-asana`;
repository variables `CROSSBENCH_WPR_ASANA_ALERTS_ENABLED` and
`CROSSBENCH_RUNTIME_ASANA_ALERTS_ENABLED` independently disable the two alert
categories for all runs.

The runner writes:

- `crossbench-results/chrome-lcp-<UTC>.tsv`
- `crossbench-dispositions/chrome-dispositions-<UTC>.tsv`
- `wpr-validation/manifest.tsv`
- `wpr-validation/report.txt`

CI uploads both artifacts and aggregates them with `webview_type=chr-wpr`, so
replay results cannot be mixed with the earlier live-network `chr` rows.

The attempts table records one row for every requested site.
`requested_repetitions` remains the configured count when validation excludes a
site, while `recorded_samples` counts usable LCP values. Therefore
`sum(recorded_samples) / sum(requested_repetitions)` is end-to-end coverage,
including archive exclusions. `archive_sha256` identifies the exact recording;
it is `NULL` when the archive did not exist or validation could not determine
its identity.

Crossbench errors and missing result directories are recorded as `infra_error`.
The script continues through the site list so available artifacts and
dispositions survive. An isolated site failure is reported but does not fail an
otherwise useful run; CI still fails when no eligible site produces a sample or
runner disk headroom is exhausted. Runtime problems are summarized in one Asana
subtask when alerting is enabled. Each site uses a generated Crossbench directory
that is removed after its TSV rows are extracted. CI retains the first failing
site's Crossbench log and trace; selecting `upload-diagnostics` retains traces
for every site. Diagnostic copies are capped at 256 MB by default.
`KEEP_CROSSBENCH_OUTPUT=1` disables cleanup for a bounded diagnostic run.
Each Crossbench site invocation also has a 20-minute wall-clock watchdog. A
timeout terminates only that invocation's process group, records
`crossbench/site_timeout`, preserves any completed samples and bounded
diagnostics, and continues with later sites. Set
`CROSSBENCH_SITE_TIMEOUT_SECONDS` to a positive value no greater than 86400 for
a diagnostic run.

## Safari

Safari uses `test-safari.sh`, which temporarily routes Safari through
`httpproxy.py -> tsproxy -> WPR` and restores its per-browser proxy preferences
on exit. It uses WebDriver LCP observations rather than Chromium Perfetto
traces, with `acceptInsecureCerts=true` for WPR's ECDSA certificate; neither the
certificate nor a system proxy is installed or changed.

Safari runs ten replay loads per eligible site with no live-network fallback.
Validation errors are exclusions. A per-site WPR or automation failure is
`infra_error` and does not stop later sites; failure of the shared proxy,
shaping, or SafariDriver service stops measurement and records the remaining
eligible sites as `infra_error`. Its rows use `webview_type=sfr-wpr`. CI retains
bounded Safari, proxy, shaping, and per-site WPR logs in `safari-diagnostics/`.

A new WebDriver session does not by itself prove a cold Safari HTTP cache.
Before comparing absolute Safari values with Chrome cold-profile values, verify
per-repetition WPR subresource traffic or add a reliable cache reset.
