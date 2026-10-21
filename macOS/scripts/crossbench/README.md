# macOS browser LCP with WPR

Measures browser navigation-to-LCP on macOS using fixed Web Page Replay
archives and the same US-broadband profile as the Windows harness:

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
| `provision-ddg-runtime.sh` | Installs only DDG's pinned WPR, Python, and tsproxy runtime under the runner user. |
| `provision-wpr-tools.sh` | Builds requested WPR tools from the crossbench-pinned WPR revision. |
| `validate-wpr-archives.sh` | Downloads the complete selected archive set and produces its validation report and manifest. |
| `validate-wpr.go` | Parses stored WPR requests and responses without starting a replay server. |
| `wpr-sites.txt` | Single default site list shared by validation and the browser run. |
| `test-chrome.sh` | Runs Chrome through the validated WPR archives and tsproxy, and writes per-repetition results and per-site dispositions. |
| `test-ddg.sh` | Runs a DuckDuckGo Review build through validated WPR archives and tsproxy. |
| `ddg-automation.py` | Authenticated local automation client used by the DDG harness. |
| `prepare-ddg-review.py` | Downloads or consumes, verifies, and normalizes the signed Review app used by DDG CI. |
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

CI can create one write-only Asana task for archive-validation errors and one
for browser-measurement errors per workflow run, in the `Alerts` section
(`1217628708169657`) of project `1217628708169653`. It uses
`ASANA_ACCESS_TOKEN` only to create tasks and never reads Asana. Repository
variable `CROSSBENCH_ALERT_FOLLOWERS` optionally adds collaborators.
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

CI uploads both artifacts with `webview_type=chrome`.

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
eligible sites as `infra_error`. Its rows use `webview_type=safari`. CI retains
bounded Safari, proxy, shaping, and per-site WPR logs in `safari-diagnostics/`.

Safari is quit before every repetition, so each load runs on a process
safaridriver has just launched — the same per-repetition freshness Chrome gets
from a new process and profile, and DuckDuckGo from a relaunch and data wipe.
Because Safari must therefore be the only one on the machine, the run refuses to
start while another Safari is already open, and a Safari that will not quit is a
harness failure rather than a warmer measurement.

Quitting removes the JIT, prewarmed-process and in-memory carry-over. The disk
cache needs no separate reset: safaridriver gives every WebDriver session its own
ephemeral store under the Safari container's `tmp/SafariAutomation`, and the
harness opens one session per repetition, so each load starts with an empty
network cache, cookie jar and local storage while Safari's own persistent cache
is left untouched.

safaridriver never removes those session stores, so the harness prunes them
itself: at startup, after each repetition's quit, and during cleanup. Pruning is
skipped while any Safari is alive, since a live session owns its store.

## DuckDuckGo

DuckDuckGo uses `test-ddg.sh` with a Review or Debug app build that exposes the
authenticated local automation server. Each repetition launches a fresh app,
clears website data, and uses a fresh tsproxy instance to route its WKWebView
to WPR. There is no live-network fallback or system proxy change.

The harness consumes validator-staged archives and writes the same result and
disposition formats as the other browser runners. Replay misses, failed
automation acknowledgements, incomplete cleanup, and invalid measurements are
recorded as infrastructure errors, and affected samples are discarded.

The manual `macos_ddg_lcp.yml` workflow runs on the same hosted `macos-latest`
runner as Chrome and Safari, behind the `macos-performance` environment, so the
three browsers stay comparable. A supplied Review URL is downloaded without
placing it on a process command line. With a blank URL, CI builds the exact
workflow commit using the existing notarized Review workflow. Before execution,
the app is checked for its Review bundle identifier, DuckDuckGo signing team,
valid deep signature, and Gatekeeper assessment. Validation failures are
included in the consolidated runtime report.

DDG scheduling remains disabled until two full runs complete
with understood variance. The optional ClickHouse rows use
`webview_type=ddg` and `webview_channel=review`.
