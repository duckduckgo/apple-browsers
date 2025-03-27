#!/bin/bash

SCRIPT_URL="https://raw.githubusercontent.com/duckduckgo/apple-browsers/main/SharedPackages/BrowserServicesKit/scripts/pre-commit.sh"
curl -s "${SCRIPT_URL}" | bash -s -- "$@"
