# macOS crossbench — Chrome and Safari LCP

The Chrome and Safari harnesses measure navigation-to-LCP using fixed Web Page
Replay archives and the same US-broadband profile as the Windows harness:

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
| `test-safari.sh` | Runs Safari through its per-app proxy, `httpproxy.py`, tsproxy and WPR. |
| `safari-automation.py` | Drives safaridriver with `acceptInsecureCerts` and reads LCP from WebKit. |
| `httpproxy.py` | Adapts Safari's HTTP proxy to tsproxy's SOCKS5 endpoint without a system proxy. |
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
./test-safari.sh --sites apple.com --reps 1
```

The manual CI workflow also accepts a `reps` input. Scheduled runs retain the
10-load default; use a smaller value for validation runs.

The Chrome runner writes:

- `crossbench-results/chrome-lcp-<UTC>.tsv`
- `crossbench-dispositions/chrome-dispositions-<UTC>.tsv`

CI uploads both artifacts and aggregates them with `webview_type=chr-wpr`, so
replay results cannot be mixed with the earlier live-network `chr` rows.

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
WebDriver and rejects certificate interstitials or other off-site landings.
Every available site gets 10 measured replay loads and no warm-up. Missing
archives are recorded as infrastructure errors, with no live-network fallback.

Safari results and disposition rows use `webview_type=sfr-wpr`, keeping them
separate from historical live-network `sfr` data.
