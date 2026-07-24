# macOS crossbench — Chrome LCP (live network)

Measures Chrome page-load performance (navigation → Largest Contentful Paint)
on macOS using [crossbench], over a fixed top-sites list, against the **live
network**. This is the minimal first slice of the macOS crossbench harness: no
Web Page Replay, no traffic shaping, no proxy, and Chrome only.

> Live-network results are noisy — they vary run-to-run with network conditions
> and are **not** comparable to recorded-network (WPR) numbers or to the Windows
> crossbench pipeline. This slice exists to stand up the measurement pipeline,
> not to produce trustworthy cross-browser comparisons. Recorded network (WPR)
> and a dedicated runner come in a later iteration.

## Layout

| File | Purpose |
|------|---------|
| `provision-macos.sh` | Installs the minimum: Python 3.11 + Poetry, latest Chrome, a pinned crossbench checkout, the LCP extras, and the `cpu_freq` patch. Idempotent. |
| `test-chrome.sh` | Runs the LCP suite against the live network and writes a results TSV. |
| `crossbench-extras/` | Fork-only files crossbench needs but a plain clone doesn't ship: the `navToLCP` probe config and the LCP SQL module. Copied into the crossbench checkout by `provision-macos.sh`. |
| `patches/` | `cpu_freq` AttributeError fix (crossbench crashes on Apple Silicon without it). |

## Prerequisites (on the runner, once)

- Xcode Command Line Tools (`xcode-select --install`)
- Homebrew (`/opt/homebrew`)

Everything else is installed by `provision-macos.sh`.

## Usage

```sh
# 1. Install/refresh the toolchain (safe to re-run every job).
./provision-macos.sh

# 2. Measure. Defaults: 22 sites, 10 reps each, 12 s load window.
./test-chrome.sh
# Quick smoke run:
./test-chrome.sh --sites apple.com,wikipedia.org --reps 3
```

Both honor `CROSSBENCH_DIR` (default `~/Developer/crossbench-upstream`).

## How you see results

Two ways:

1. **Console summary** — per site, as the run progresses:
   ```
   === site: apple.com ===
     apple.com: lcp_ms=[812.4,799.1,835.0] mean=815.5 n=3
   ```
2. **Results file** — a TSV written to `./crossbench-results/chrome-lcp-<UTC>.tsv`
   (override with `--out FILE`). One row per rep:
   ```
   browser  browser_version  site        rep  lcp_ms
   chrome   150.0.7258.5     apple.com   1    812.4
   chrome   150.0.7258.5     apple.com   2    799.1
   ```

In CI this TSV is uploaded as a workflow artifact (download it from the Actions
run), and the console summary shows in the job log. Aggregating these per-rep
rows into percentiles and pushing them to ClickHouse is the next increment — not
part of this slice.

## Safari

`test-safari.sh` is the Safari sibling of `test-chrome.sh` — same site list, same
1 warm-up + 10 measured reps, same TSV columns (with `browser=safari`). It's run
by `.github/workflows/macos_crossbench_safari.yml`, which mirrors the Chrome
workflow but tags rows `--webview-type sfr` in the aggregation step.

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

Provisioning is shared: run `./provision-macos.sh` with `INSTALL_CHROME=0` to set
up python/poetry/crossbench + the LCP extras without installing Chrome.

> Whether Safari exposes `largest-contentful-paint` entries via
> `getEntriesByType` is engine/version dependent; if a run reports "NO LCP VALUES
> PARSED", that API path isn't available in the Safari under test.

[crossbench]: https://chromium.googlesource.com/crossbench
