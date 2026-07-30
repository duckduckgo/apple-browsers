# `pir-debug` cheat sheet

Headless driver for the macOS PIR/DBP debug engine — the same scan/opt-out engine as the "Run
Personal Information Removal Debug Mode" window, from a bare SPM executable. Full reference:
`macOS/LocalPackages/PIRDebugCLI/README.md`.

## Setup

```bash
cd macOS/LocalPackages/PIRDebugCLI
swift build -c release            # binary at .build/release/pir-debug
alias pd='.build/release/pir-debug'   # or just use `swift run pir-debug …`

# Credentials for email/captcha (opt-out + all email commands). Preferred, once per ~30 days:
#   in the app: Debug › Privacy Pro › Export Token for pir-debug
pd auth status            # confirms environment + "Data Broker Protection" entitlement

# Or the shared staging JWT from Bitwarden (takes precedence; never refreshed, so long waits die):
export PRIVACYPRO_STAGING_ACCESS_TOKEN_V2='<staging JWT>'

# Fake broker rules to point at instead of real sites:
FAKE=../../../SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/fakebroker.com.json
```

`p.json` — the profile, one query per name × address:

```json
{"names":[{"firstName":"John","lastName":"Smith"}],
 "addresses":[{"city":"Dallas","state":"TX"}],
 "phones":[],"birthYear":1960}
```

## The I/O rule that makes everything pipeable

**stdout = result JSON only. stderr = all progress logs.** So `pd scan … | jq` always works, even
with `--verbose`. Consequence: `--help` prints to stderr, and `--events -` sends events to
**stderr**, not stdout.

Exit codes: `0` ok (incl. zero matches) · `1` operation failed · `2` bad flags/files · `3`
`--timeout` fired.

## Auth

```bash
pd auth status                              # issuer/env, entitlements, expiries. Exit 1 if unusable
pd auth import --file token.json            # or --stdin; for the paste path
pd auth refresh --environment staging       # prove the refresh token still works
pd auth logout                              # delete the local file (app stays signed in)
```

Token lives at `~/.config/pir-debug/token.json` (0600); `--token-file <path>` points anywhere else.
Precedence: `--auth-token` / `$PRIVACYPRO_STAGING_ACCESS_TOKEN_V2` **beats** the stored token.

`accessTokenExpired: true` is **normal** — it refreshes on use; only `refreshTokenExpired` means
re-export. The token's environment must match `--environment`: a `quackdev` (staging) token gets 401s
from production services and vice versa, and `auth status` tells you which you have.

There's no self-service login — auth v2 `createAccount` gives `entitlements: []`, which DBP rejects.

## Email

```bash
# Generate an address for a broker (--broker is the broker JSON's `url`)
pd email generate --broker fakebroker.com --output mailbox.json
A=$(jq -r .email mailbox.json); I=$(jq -r .attemptId mailbox.json)

# Read the mailbox — status, confirmation link, all extracted data
pd email inbox --email "$A" --attempt-id "$I"

# Block until mail lands, print just the link
pd email inbox --email "$A" --attempt-id "$I" --wait --poll-interval 15 --timeout 900 \
  | jq -r .confirmationLink

# Generate + wait in one shot; clean up the backend copy when done
pd email generate --broker fakebroker.com --wait
pd email delete --email "$A" --attempt-id "$I"
```

Keep the `attemptId` — a mailbox is keyed by (address, attempt id), and `generate` prints the exact
`inbox` command on stderr. `status: pending` exits 0; `error`/`unknown` exits 1. Add
`--services-url http://localhost:PORT` to hit a local fake email service.

## Scan → opt-out

```bash
# Scan (one broker → object; --all or multiple → array)
pd scan --broker-file "$FAKE" --profile p.json --output scan.json
pd scan --rules-dir ~/code/dbp-api/dbp-json/data/json --broker fakebroker.com --profile p.json

# Opt out a profile from that scan, waiting for the confirmation email
pd optout --broker-file "$FAKE" --profile p.json \
  --broker fakebroker.com --extracted scan.json \
  --wait-for-email --poll-interval 15 --timeout 900
```

Without `--wait-for-email`, a halt at email confirmation exits **0** with
`awaitingEmailConfirmation: true`. Pick among several matches with `--index <n>` or `--all-matches`.

## Rules sources (pick one)

| Flag | Source |
|---|---|
| `--broker-file f.json` | one local broker |
| `--rules-dir <dir>` | a dbp-api checkout's `dbp-json/data/json/` |
| `--dbp-api-branch randerson/fix-foo` | branch deploy (label the dbp-api PR `upload-remote-config`) |
| `--dbp-api-url http://localhost:3001` | verbatim base URL |
| *(none)* + `--environment staging\|production` | remote fetch; also picks the services endpoint |

## Inspect / validate

```bash
pd validate --rules-dir ~/code/dbp-api/dbp-json/data/json   # exact runtime decoder, exit 1 on any failure
pd list-brokers --broker-file "$FAKE"                        # name/url/version/steps
pd fetch-rules --dbp-api-branch my/branch --out ./rules      # materialize main_config + broker JSONs
```

## Debugging a run

```bash
--show-webview                 # watch it happen
--events events.jsonl          # every action/response/wait/retry as JSONL
--events -                     # interleave on stderr
--verbose --await-time 2       # slower, chattier
--user-agent safari|tool       # default safari; `tool` = identifiable as pir-debug

jq -r 'select(.kind=="actionResponse") | "\(.actionType)\t\(.details)"' events.jsonl
```

## content-scope-scripts overrides

```bash
pd scan --css-checkout ~/code/content-scope-scripts --broker-file "$FAKE" --profile p.json
pd scan --css-checkout ~/code/content-scope-scripts --css-no-build …   # reuse existing dist
pd scan --css-branch my/feature --broker-file "$FAKE" --profile p.json # CI pr-releases build
pd scan --css-script /path/contentScopeIsolated.js …                   # single prebuilt file
```

One-time: `(cd ~/code/content-scope-scripts/injected && npm ci)`. If your change also alters the
native↔JS contract, the JS swap isn't enough — repoint BSK's package pin (README § SPM-repoint
fallback).

## Long-running server

```bash
pd serve --broker-file "$FAKE" --port 8475
curl -s localhost:8475/                                  # endpoint listing
curl -s -XPOST localhost:8475/scan -d '{"profile":…}'    # → 202 {jobId}
curl -s localhost:8475/jobs/<id>                         # poll for the result
curl -s 'localhost:8475/events?since=0'
```

Loopback only, no auth, one job at a time (concurrent POST → 409).

## Gotchas

- Automated loops go at fake brokers (`DuckDuckGo/pir-fake-broker` on `:3001`, or the bundled
  JSONs) — never real sites.
- **cyberbackgroundchecks.com never clears its Cloudflare interstitial** in this tool, regardless of
  `--user-agent` or `--show-webview`. Test those rules against local fixtures.
- `--services-url` exists only on the `email` commands.
- **`--auth-token` is never refreshed.** Staging access tokens live minutes, so any `--wait` longer
  than that starts 401ing partway through. Use the stored token for long runs.
- The stored token file holds a **refresh token** — a real credential, plaintext under `$HOME` at
  `0600`. `pd auth logout` deletes it; it does **not** sign the app out.
