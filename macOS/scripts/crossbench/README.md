# macOS crossbench — Chrome LCP with WPR

Measures Chrome navigation-to-LCP on macOS using fixed Web Page Replay archives
and the same US-broadband profile as the Windows harness:

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
| `provision-macos.sh` | Installs Chrome, Python 3.11, Poetry, a pinned crossbench checkout, the LCP extras, a pinned WPR binary, and a checksum-verified tsproxy. |
| `test-chrome.sh` | Downloads each archive, runs Chrome through WPR and tsproxy, and writes per-repetition results and per-site dispositions. |
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
