#!/bin/sh
# Serves the fake assisted broker on http://localhost:3001 (the port fakeassistedbroker.com.json points at).
cd "$(dirname "$0")" && exec python3 -m http.server "${1:-3001}" --bind 127.0.0.1
