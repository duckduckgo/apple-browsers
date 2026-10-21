#!/bin/bash
set -euo pipefail
runner_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /usr/bin/python3 "$runner_dir/lifecycle.py" pre "$@"
