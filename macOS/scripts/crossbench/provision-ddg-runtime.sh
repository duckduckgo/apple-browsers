#!/usr/bin/env bash
#
# Install only the user-space replay tools required by the DDG LCP harness.
# Xcode Command Line Tools and Homebrew are commissioned on the runner once.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=macOS/scripts/crossbench/wpr-config.sh
. "$SCRIPT_DIR/wpr-config.sh"

PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
RUNTIME_ROOT="${RUNTIME_ROOT:-$HOME/Developer/mac-perf-runner}"
WPR_SRC="${WPR_SRC:-$RUNTIME_ROOT/webpagereplay}"
WPR_BIN="${WPR_BIN:-$RUNTIME_ROOT/bin/wpr}"
TSPROXY_PY="${TSPROXY_PY:-$RUNTIME_ROOT/bin/tsproxy.py}"

export NONINTERACTIVE=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

if ! xcode-select -p >/dev/null 2>&1; then
  echo "ERROR: Xcode Command Line Tools must be commissioned on the runner." >&2
  exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    echo "ERROR: Homebrew must be commissioned on the runner." >&2
    exit 1
  fi
fi

brew list "python@$PYTHON_VERSION" >/dev/null 2>&1 ||
  brew install "python@$PYTHON_VERSION"
brew list go >/dev/null 2>&1 || brew install go
PYTHON_BIN="$(brew --prefix "python@$PYTHON_VERSION")/bin/python$PYTHON_VERSION"

WPR_SRC="$WPR_SRC" WPR_BIN="$WPR_BIN" \
  "$SCRIPT_DIR/provision-wpr-tools.sh"

actual_sha=""
if [ -f "$TSPROXY_PY" ]; then
  actual_sha="$(shasum -a 256 "$TSPROXY_PY" | awk '{print $1}')"
fi
if [ "$actual_sha" != "$TSPROXY_SHA256" ]; then
  temporary="${TSPROXY_PY}.tmp"
  mkdir -p "$(dirname "$TSPROXY_PY")"
  rm -f "$temporary"
  if ! curl -fLSs "$TSPROXY_URL" |
      "$PYTHON_BIN" -c \
        'import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))' \
      > "$temporary"; then
    rm -f "$temporary"
    echo "ERROR: could not fetch pinned tsproxy." >&2
    exit 1
  fi
  actual_sha="$(shasum -a 256 "$temporary" | awk '{print $1}')"
  if [ "$actual_sha" != "$TSPROXY_SHA256" ]; then
    rm -f "$temporary"
    echo "ERROR: tsproxy checksum mismatch." >&2
    exit 1
  fi
  mv "$temporary" "$TSPROXY_PY"
fi
"$PYTHON_BIN" "$TSPROXY_PY" --help >/dev/null

printf 'python:  %s\n' "$("$PYTHON_BIN" --version)"
printf 'wpr:     %s\n' "$WPR_BIN"
printf 'tsproxy: %s\n' "$TSPROXY_PY"
