# macOS crossbench — Chrome and Safari LCP

The Chrome harness measures navigation-to-LCP using fixed Web Page Replay
archives and the same US-broadband profile as the Windows harness:

- 28 ms RTT
- 50,000 Kbps downstream
- 10,000 Kbps upstream
- TCP window 10

There is no live-network fallback or curl site pre-check. A site without an
archive is recorded as an infrastructure error and skipped. Each available site
gets 10 measured loads with no discarded warm-up.

## Layout

| File | Purpose |
|------|---------|
| `provision-macos.sh` | Installs Chrome when requested, Python 3.11, Poetry, a pinned crossbench checkout, the LCP extras, a pinned WPR binary, and a checksum-verified tsproxy. |
| `test-chrome.sh` | Downloads each archive, runs Chrome through WPR and tsproxy, and writes per-repetition results and per-site dispositions. |
| `test-safari.sh` | Runs Safari against the live network and writes per-repetition results and per-site dispositions. |
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

The runner writes:

- `crossbench-results/chrome-lcp-<UTC>.tsv`
- `crossbench-dispositions/chrome-dispositions-<UTC>.tsv`

CI uploads both artifacts and aggregates them with `webview_type=chr-wpr`, so
replay results cannot be mixed with the earlier live-network `chr` rows.

## Safari

`test-safari.sh` is the live-network Safari sibling. It uses the same site list
and TSV columns, with one discarded warm-up followed by 5 measured loads. It is
run by `.github/workflows/macos_crossbench_safari.yml`, which tags aggregate rows
with `webview_type=sfr`.

It differs from the Chrome path in how LCP is measured. WebKit does **not** emit
Chromium Perfetto traces, so the `perfetto` + `trace_processor` probe can't work.
Instead Safari LCP is read straight from the page via the standard
`largest-contentful-paint` PerformanceObserver entries (the Web Vitals LCP API),
through crossbench's browser-agnostic `js` probe
(`crossbench-extras/config/probe/js/navToLCP.safari.config.hjson`). Two
consequences:

- **No `--about-blank-duration`.** The `js` probe reads LCP after the story's
  core workload with the browser still on the page; navigating to about:blank
  first would clear the performance timeline. (Chrome needs about:blank to
  *finalize* LCP into its trace; the JS read does not.)
- **safaridriver must be enabled.** crossbench drives Safari over WebDriver, which
  refuses sessions until "Allow Remote Automation" is on (`sudo safaridriver
  --enable` or Safari's Develop menu). The workflow runs `sudo safaridriver
  --enable`; hosted runners grant passwordless sudo, self-hosted ones may not.

Because Safari's current path still uses the live network, its values remain
noisy and are not directly comparable with Chrome's WPR results. Porting Safari
to WPR requires Safari-specific proxy and certificate handling; it is not
provided by passing Chrome's crossbench `--network` argument through unchanged.

Provisioning is shared: run `./provision-macos.sh` with `INSTALL_CHROME=0` to
install Python, Poetry, crossbench, the LCP extras, WPR, and tsproxy without
installing Chrome.
