# macOS replay benchmarks — Chrome and Safari LCP

The Chrome and Safari harnesses measure navigation-to-LCP using fixed Web Page
Replay archives and the same US-broadband profile as the Windows harness:

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
downloading the files again. Safari verifies each staged archive's filename and
SHA-256 against that manifest before starting WPR. Corruption between validation
and the browser runner is an infrastructure failure, not a site exclusion.

## Layout

| File | Purpose |
|------|---------|
| `provision-macos.sh` | Installs Chrome when requested, Python 3.11, Poetry, a pinned crossbench checkout, the LCP extras, a pinned WPR binary, and a checksum-verified tsproxy. |
| `.github/workflows/wpr_archive_validation.yml` | Reusable validation and consolidated alerting for every browser workflow. |
| `provision-wpr-tools.sh` | Builds requested WPR tools from the crossbench-pinned WPR revision. |
| `validate-wpr-archives.sh` | Downloads the complete selected archive set and produces its validation report and manifest. |
| `validate-wpr.go` | Parses stored WPR requests and responses without starting a replay server. |
| `wpr-config.sh` | Shared WPR source, archive URL, and US-broadband profile. |
| `wpr-sites.txt` | Single default site list shared by validation and browser runs. |
| `test-chrome.sh` | Runs Chrome through the validated WPR archives and tsproxy, and writes per-repetition results and per-site dispositions. |
| `test-safari.sh` | Runs Safari through its per-app proxy, `httpproxy.py`, tsproxy and WPR. |
| `safari-automation.py` | Drives safaridriver with `acceptInsecureCerts` and reads LCP from WebKit. |
| `httpproxy.py` | Adapts Safari's HTTP proxy to tsproxy's SOCKS5 endpoint without a system proxy. |
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

# Safari consumes only the validator's staged archive set.
WPR_DIR="$PWD/wpr-archives" WPR_REPLAY_DIR="$PWD/validated-wpr-archives" \
  ./validate-wpr-archives.sh --sites apple.com
WPR_DIR="$PWD/validated-wpr-archives" WPR_ARCHIVES_PREPARED=1 \
  ./test-safari.sh --sites apple.com --reps 1
```

The manual CI workflow also accepts a `reps` input. Scheduled runs retain the
10-load default; use a smaller value for validation runs.

## Tests

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
```

The Safari harness tests run the real shell runner against temporary loopback
fake services and preferences; they do not start Safari or access the network.
The pull-request replay workflow runs this suite independently of browser
provisioning and WPR archive validation.

CI creates at most one write-only Asana subtask per workflow run under task
`1216902374642227` when its consolidated validation report has new errors. It
uses `ASANA_ACCESS_TOKEN` only with
Asana's create-subtask endpoint and never lists or reads Asana tasks. A
pair of 90-day GitHub artifacts keyed by workflow run and deterministic report
fingerprint provide best-effort suppression of duplicate reports without
querying Asana; concurrent runs or artifact failures can still create duplicates.
Alerting defaults on and can be disabled for
a manual run with the `alert-asana` input. Setting the repository variable
`CROSSBENCH_WPR_ASANA_ALERTS_ENABLED` to `false` disables it globally, including
scheduled runs; an absent variable means enabled.

The Chrome workflow writes:

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
dispositions survive, then exits nonzero. CI uploads Perfetto diagnostics on
failure; successful runs upload them only when `upload-diagnostics` is selected.

## Safari

Safari has no command-line host remapping, so `test-safari.sh` temporarily sets
`com.apple.Safari`'s `WebKit2HTTPProxy` and `WebKit2HTTPSProxy` preferences. The
route is:

```text
Safari -> httpproxy.py -> tsproxy -> WPR
```

The harness captures and restores both preference values, including whether a
key was absent, on exit and signals. It does not change the macOS system proxy.

WPR serves leaves from its P-256 ECDSA certificate and key with
`--no-archive-certificates`. The WebDriver session requests
`acceptInsecureCerts=true`; the certificate is not installed in or trusted by a
keychain. The workflow still runs `sudo safaridriver --enable`, which is required
before Safari accepts automation sessions.

WebKit does not emit Chromium Perfetto traces. `safari-automation.py` instead
reads the buffered `largest-contentful-paint` PerformanceObserver entries over
WebDriver. Its non-blocking page-load strategy observes a fixed 12-second window
from navigation rather than waiting for the page `load` event. Certificate
interstitials, other off-site landings, and failed session cleanup are
infrastructure errors.
Every eligible site gets 10 measured replay loads and no warm-up. Validation
errors are recorded as exclusions, with no live-network fallback. WPR or
automation failures are recorded as `infra_error`; the remaining sites still
run before the job exits nonzero.

Safari results and disposition rows use `webview_type=sfr-wpr`, keeping them
separate from historical live-network `sfr` data.

On failure, Safari retains the WPR, proxy, tsproxy, and safaridriver logs in
`safari-diagnostics/`; CI uploads that directory for three days.
