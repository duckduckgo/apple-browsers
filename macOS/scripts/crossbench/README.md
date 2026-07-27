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
site is eligible, package validation fails, browser jobs do not start, and the
Asana subtask identifies the package failure as important.

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
| `aggregate-lcp.py` | Produces per-domain ClickHouse metric rows. |
| `aggregate-dispositions.py` | Produces ClickHouse attempt rows, including skipped and failed sites. |
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

CI creates at most one write-only Asana subtask per workflow run under task
`1216902374642227` when its consolidated validation report has new errors. It
uses `ASANA_ACCESS_TOKEN` only with
Asana's create-subtask endpoint and never lists or reads Asana tasks. A
pair of 90-day GitHub artifacts keyed by workflow run and deterministic report
fingerprint enforce at most one subtask per run and suppress identical reports
across runs without querying Asana. Alerting defaults on and can be disabled for
a manual run with the `alert-asana` input. Setting the repository variable
`CROSSBENCH_WPR_ASANA_ALERTS_ENABLED` to `false` disables it globally, including
scheduled runs; an absent variable means enabled.

The runner writes:

- `crossbench-results/chrome-lcp-<UTC>.tsv`
- `crossbench-dispositions/chrome-dispositions-<UTC>.tsv`
- `wpr-validation/manifest.tsv`
- `wpr-validation/report.txt`

CI uploads both artifacts and aggregates them with `webview_type=chr-wpr`, so
replay results cannot be mixed with the earlier live-network `chr` rows.
