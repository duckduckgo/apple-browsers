#!/usr/bin/env bash
#
# provision-macos.sh — install the replay toolchain used by Chrome and Safari
# page-load LCP on a macOS runner.
#
# Chrome replays each site from a WPR archive through a traffic shaper and
# crossbench extracts LCP from the Perfetto trace. This script installs the
# toolchain, builds the `wpr` binary, and installs the pinned traffic shaper.
# CI supplies archives staged by the shared validator. Local runs may download
# archives directly. Safari also uses the WPR checkout's ECDSA certificate and
# key with acceptInsecureCerts; provisioning never adds them to a keychain.
#
# Idempotent: safe to run on every CI job; installs only what's missing.
#
# Prerequisites that must exist BEFORE this runs (they need sudo / a human once,
# so they belong in the runner image, not here):
#   - Xcode Command Line Tools  (xcode-select --install)
#   - Homebrew                  (/opt/homebrew, bootstrapped once)
# This script fails fast with instructions if either is missing.
#
# Usage: [CROSSBENCH_DIR=/path/to/crossbench] ./provision-macos.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRAS_DIR="$SCRIPT_DIR/crossbench-extras"
# shellcheck source=macOS/scripts/crossbench/wpr-config.sh
. "$SCRIPT_DIR/wpr-config.sh"

# Canonical crossbench checkout. The fork-only files the LCP run needs
# (navToLCP probe config + LCP SQL module) are copied in as untracked files.
CROSSBENCH_DIR="${CROSSBENCH_DIR:-$HOME/Developer/crossbench-upstream}"
CROSSBENCH_GIT="${CROSSBENCH_GIT:-https://chromium.googlesource.com/crossbench}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"   # matches Windows (poetry env use 3.11)

# crossbench is pinned, not tip-of-tree: upstream can rename/refactor the code
# our extras + the cpu_freq patch target underneath us. Anchor to a known-good
# rev so the extras and patch always line up with code that exists.
CROSSBENCH_REV="${CROSSBENCH_REV:-be14dbfb884747ea577e2e65b6a4a77d7ecd807d}"

# Where the wpr binary is built to. test-chrome.sh passes this to crossbench via
# --bin-override; test-safari.sh starts it directly.
WPR_BIN="${WPR_BIN:-$HOME/Developer/mac-perf-runner/bin/wpr}"

# The version, checksum, and URL come from wpr-config.sh so the runner uses the
# same binary that this provisioner installs.
TRACEBOX_BIN="${TRACEBOX_BIN:-$HOME/Developer/mac-perf-runner/bin/tracebox-$TRACEBOX_VERSION}"

# The tsproxy revision in crossbench's DEPS is not Python-3-compatible. Use
# Catapult's fixed copy instead, pinned to immutable source and verified by
# content hash so scheduled runs cannot silently pick up tip-of-tree changes.
TSPROXY_REV="d810008022eeaefcbea50393ea5baa0930b27047"
TSPROXY_SHA256="8380fa81c3b632aa9b83a34728b31046c53855adbf071c18a7afc2945c523c67"
TSPROXY_URL="https://chromium.googlesource.com/catapult/+/$TSPROXY_REV/third_party/tsproxy/tsproxy.py?format=TEXT"
TSPROXY_PY="${TSPROXY_PY:-$HOME/Developer/mac-perf-runner/bin/tsproxy.py}"

# Non-interactive: never prompt (Homebrew honors these).
export NONINTERACTIVE=1
export HOMEBREW_NO_AUTO_UPDATE=1        # don't self-update mid-job (perf hygiene)
export HOMEBREW_NO_INSTALL_CLEANUP=1

log() { printf '\n=== %s ===\n' "$1"; }

# 1. Xcode Command Line Tools — brew and git depend on it. Headless install
#    needs sudo, so it must be pre-installed when imaging the runner.
log "Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  echo "ERROR: Command Line Tools missing. Run 'xcode-select --install' on the runner first." >&2
  exit 1
fi
echo "present: $(xcode-select -p)"

# 2. Homebrew — must already be bootstrapped (its installer shells out to sudo,
#    which can't run unattended on a password-sudo box).
log "Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    echo "ERROR: Homebrew not found. Bootstrap it once on the runner:" >&2
    # shellcheck disable=SC2016  # literal install command for the operator to copy-paste
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
    exit 1
  fi
fi
echo "brew: $(brew --version | head -1)"

# 3. Python + Poetry (brew manages its own prefix — no sudo needed).
log "Python ${PYTHON_VERSION} + Poetry"
brew list "python@${PYTHON_VERSION}" >/dev/null 2>&1 || brew install "python@${PYTHON_VERSION}"
command -v poetry >/dev/null 2>&1 || brew install poetry
PY_BIN="$(brew --prefix "python@${PYTHON_VERSION}")/bin/python${PYTHON_VERSION}"
echo "python: $("$PY_BIN" --version)"
echo "poetry: $(poetry --version)"

# 4. Google Chrome — latest stable. Deliberately NOT pinned: the baseline should
#    track what users actually run, and crossbench stamps the exact version into
#    each result so a step caused by a Chrome bump stays traceable.
#    INSTALL_CHROME=0 skips this — the Safari harness reuses everything else this
#    script sets up (python/poetry/crossbench/extras) but drives Safari, so it
#    has no need for Chrome. Default is 1 to preserve the Chrome-job behavior.
INSTALL_CHROME="${INSTALL_CHROME:-1}"
if [ "$INSTALL_CHROME" = "1" ]; then
  log "Google Chrome"
  # Explicit `brew update` first: HOMEBREW_NO_AUTO_UPDATE=1 freezes the cask
  # index, so without this an upgrade would never see a newer version.
  brew update
  if brew list --cask google-chrome >/dev/null 2>&1; then
    # --greedy because Chrome's cask auto_updates and a plain upgrade skips it.
    brew upgrade --cask --greedy google-chrome
  else
    brew install --cask --force google-chrome
  fi
  echo "chrome: $('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --version 2>/dev/null || echo 'version unavailable')"
else
  log "Google Chrome (skipped: INSTALL_CHROME=0)"
fi

# 5. crossbench checkout, pinned to CROSSBENCH_REV. Clone it if absent (keeps
#    setup to a single command).
log "crossbench checkout @ $CROSSBENCH_REV"
if [ ! -d "$CROSSBENCH_DIR/.git" ]; then
  echo "cloning crossbench into $CROSSBENCH_DIR"
  git clone --quiet "$CROSSBENCH_GIT" "$CROSSBENCH_DIR"
fi
if ! git -C "$CROSSBENCH_DIR" cat-file -e "${CROSSBENCH_REV}^{commit}" 2>/dev/null; then
  echo "rev not present locally; fetching..."
  git -C "$CROSSBENCH_DIR" fetch --quiet origin "$CROSSBENCH_REV"
fi
# -f: a prior self-heal leaves crossbench/plt/macos.py modified (the cpu_freq
# patch); -f discards it here and self-heal re-applies it below. This does NOT
# touch untracked files, so the copied-in extras survive — do not add git clean.
git -C "$CROSSBENCH_DIR" -c advice.detachedHead=false checkout --quiet -f "$CROSSBENCH_REV"
echo "crossbench: $(git -C "$CROSSBENCH_DIR" rev-parse HEAD)"

# Use a checksum-verified Perfetto binary instead of Crossbench's older
# auto-downloaded default.
log "Perfetto tracebox $TRACEBOX_VERSION"
TRACEBOX_ACTUAL_SHA256=""
if [ -f "$TRACEBOX_BIN" ]; then
  TRACEBOX_ACTUAL_SHA256="$(shasum -a 256 "$TRACEBOX_BIN" | awk '{print $1}')"
fi
if [ "$TRACEBOX_ACTUAL_SHA256" != "$TRACEBOX_SHA256" ]; then
  TRACEBOX_TMP="${TRACEBOX_BIN}.tmp"
  mkdir -p "$(dirname "$TRACEBOX_BIN")"
  rm -f "$TRACEBOX_TMP"
  if ! curl -fLSs "$TRACEBOX_URL" -o "$TRACEBOX_TMP"; then
    rm -f "$TRACEBOX_TMP"
    echo "ERROR: could not fetch Perfetto $TRACEBOX_VERSION." >&2
    exit 1
  fi
  TRACEBOX_ACTUAL_SHA256="$(shasum -a 256 "$TRACEBOX_TMP" | awk '{print $1}')"
  if [ "$TRACEBOX_ACTUAL_SHA256" != "$TRACEBOX_SHA256" ]; then
    rm -f "$TRACEBOX_TMP"
    echo "ERROR: Perfetto tracebox checksum mismatch." >&2
    exit 1
  fi
  mv "$TRACEBOX_TMP" "$TRACEBOX_BIN"
fi
chmod +x "$TRACEBOX_BIN"
"$TRACEBOX_BIN" --version

# 6. Self-heal the fork-only extras + cpu_freq patch. REQUIRED: without the
#    extras LCP silently returns no rows, and without the patch crossbench
#    crashes on Apple Silicon (psutil.cpu_freq raises AttributeError).
#      - config/probe/perfetto/navToLCP.config.hjson              (probe config)
#      - crossbench/probes/trace_processor/modules/ext/largestcontentfulpaint.sql
log "crossbench extras + cpu_freq patch (self-heal)"
if [ ! -f "$CROSSBENCH_DIR/cb.py" ]; then
  echo "ERROR: crossbench checkout looks wrong at $CROSSBENCH_DIR (cb.py missing)." >&2
  exit 1
fi
# `cp -R <dir>/.` merges into the destination tree without clobbering unrelated files.
cp -R "$EXTRAS_DIR/." "$CROSSBENCH_DIR/"
TRACEBOX_BIN="$TRACEBOX_BIN" perl -0pi -e \
  's{__TRACEBOX_BIN__}{$ENV{TRACEBOX_BIN}}g' \
  "$CROSSBENCH_DIR/config/probe/perfetto/navToLCP.config.hjson"
echo "extras: installed navToLCP.config.hjson + largestcontentfulpaint.sql"
# Apply the cpu_freq patch idempotently, guarding on the patched text (the change
# is line-number independent between upstream and the fork).
MACOS_PY="$CROSSBENCH_DIR/crossbench/plt/macos.py"
if grep -q 'except (AttributeError, FileNotFoundError, SystemError, RuntimeError)' "$MACOS_PY"; then
  echo "cpu_freq patch: already applied"
elif grep -q 'except (FileNotFoundError, SystemError, RuntimeError) as e:' "$MACOS_PY"; then
  perl -0pi -e 's/except \(FileNotFoundError, SystemError, RuntimeError\) as e:/except (AttributeError, FileNotFoundError, SystemError, RuntimeError) as e:/' "$MACOS_PY"
  echo "cpu_freq patch: applied"
else
  echo "WARNING: cpu_freq patch target not found in $MACOS_PY; crossbench may have changed upstream." >&2
  echo "         Reconcile patches/cpu_freq-attributeerror.patch against the new source." >&2
fi

# 7. crossbench Python deps. --no-root is intentionally omitted: the crossbench
#    package + cb entry point require the root install.
log "crossbench deps (poetry install)"
cd "$CROSSBENCH_DIR"
poetry env use "$PY_BIN"
poetry install

# 8. WPR — crossbench does NOT ship the `wpr` binary, only a DEPS pin of its Go
#    source. A poetry-only setup never runs `gclient sync`, which is what would
#    normally populate third_party/, so clone the pinned source and `go build`
#    it here. test-chrome.sh hands the result to crossbench via --bin-override,
#    keeping crossbench's own build machinery (scripts/build.py + a hermetic
#    CIPD Go toolchain) out of the picture.
#
#    The checkout must stay at third_party/webpagereplay inside CROSSBENCH_DIR:
#    crossbench also reads deterministic.js and the ECDSA key/cert from there at
#    runtime. It is untracked as far as the crossbench repo is concerned, so the
#    `checkout -f` in step 5 leaves it alone.
log "Go toolchain (builds the wpr binary)"
brew list go >/dev/null 2>&1 || brew install go
echo "go: $(go version)"

log "WebPageReplay source (pinned by crossbench DEPS) + tool build"
WPR_SRC="$CROSSBENCH_DIR/third_party/webpagereplay"
WPR_SRC="$WPR_SRC" \
WPR_BIN="$WPR_BIN" \
  "$SCRIPT_DIR/provision-wpr-tools.sh"

# 9. tsproxy — fetch one immutable Python-3-compatible source file rather than
#    cloning Catapult. Verify both new downloads and cached copies: persistent
#    runners must not silently retain an older shaper at the same path.
log "tsproxy @ $TSPROXY_REV"
TSPROXY_ACTUAL_SHA256=""
if [ -f "$TSPROXY_PY" ]; then
  TSPROXY_ACTUAL_SHA256="$(shasum -a 256 "$TSPROXY_PY" | awk '{print $1}')"
fi
if [ "$TSPROXY_ACTUAL_SHA256" = "$TSPROXY_SHA256" ]; then
  echo "tsproxy: verified cached copy"
else
  TSPROXY_TMP="${TSPROXY_PY}.tmp"
  mkdir -p "$(dirname "$TSPROXY_PY")"
  rm -f "$TSPROXY_TMP"
  # Gitiles serves raw file content as base64 with ?format=TEXT.
  if ! curl -fLSs "$TSPROXY_URL" \
      | "$PY_BIN" -c 'import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))' \
      > "$TSPROXY_TMP"; then
    rm -f "$TSPROXY_TMP"
    echo "ERROR: could not fetch pinned tsproxy revision $TSPROXY_REV." >&2
    exit 1
  fi
  TSPROXY_ACTUAL_SHA256="$(shasum -a 256 "$TSPROXY_TMP" | awk '{print $1}')"
  if [ "$TSPROXY_ACTUAL_SHA256" != "$TSPROXY_SHA256" ]; then
    rm -f "$TSPROXY_TMP"
    echo "ERROR: tsproxy checksum mismatch." >&2
    echo "       expected: $TSPROXY_SHA256" >&2
    echo "       actual:   $TSPROXY_ACTUAL_SHA256" >&2
    exit 1
  fi
  mv "$TSPROXY_TMP" "$TSPROXY_PY"
  echo "tsproxy: downloaded and verified"
fi
"$PY_BIN" "$TSPROXY_PY" --help >/dev/null
echo "tsproxy: $TSPROXY_PY"

log "Provisioning complete"
