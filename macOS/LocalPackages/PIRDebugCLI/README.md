# `pir-debug`

A headless command-line driver for the macOS PIR/DBP debug engine. It runs the same scan /
opt-out engine as the "Run Personal Information Removal Debug Mode" window
(`DataBrokerRunCustomJSONViewModel`), but from a bare, unsigned SPM executable — no app bundle, no
entitlements, no keychain, no background agent. It is built for **coding agents**: give it broker
rule JSON and/or a `contentScopeIsolated.js` bundle from a local checkout, a CI branch, or a custom
URL, and it emits machine-readable JSON on stdout.

The tool sits on top of **`PIRDebugKit`**
(`SharedPackages/DataBrokerProtectionCore/Sources/PIRDebugKit/`), which is the UI-agnostic
extraction of the debug-window engine. The debug window and this CLI share that one core.

> Prefer the **fake brokers** in every example — `DuckDuckGo/pir-fake-broker` served at
> `http://localhost:3001`, or the bundled `fakebroker.com.json` / `fakeremovedbroker.com.json`.
> Do not point automated loops at real broker sites.

---

## Build / run

The package lives at `macOS/LocalPackages/PIRDebugCLI/`. Run all commands from that directory.

### `swift run` (debug)

```bash
cd macOS/LocalPackages/PIRDebugCLI
swift run pir-debug --help
swift run pir-debug scan --broker-file <fakebroker.com.json> --profile p.json
```

Note that `swift run`'s own build chatter goes to stderr, so it does not pollute the result
channel. `swift run pir-debug <subcommand> …` passes everything after `pir-debug` to the tool.

### Release binary

```bash
cd macOS/LocalPackages/PIRDebugCLI
swift build -c release
.build/release/pir-debug scan --broker-file <fakebroker.com.json> --profile p.json
```

The release binary is at `.build/release/pir-debug`. Everything works in a release build — endpoint
selection does not depend on `#if DEBUG`, so custom/staging services and rule sources work
identically to debug.

---

## I/O contract

The **first thing** `main.swift` does, before any engine code runs, is a file-descriptor swap:
it `dup()`s the original stdout (fd 1) aside as the *result-JSON channel*, then `dup2()`s stderr
over fd 1. The engine contains stray `print(...)` calls (cookie-handler errors, privacy-config
parse warnings, HTML/PNG dumps) that would otherwise corrupt a JSON-on-stdout contract; after the
swap those land on stderr and never touch the result channel.

| Channel | Carries |
|---------|---------|
| **stdout** (preserved fd) | Result JSON only. Nothing else is ever written here. |
| **stderr** | Human-readable progress logs (`•`/`✗` lines, `--verbose` detail) **and** the engine's stray prints. |

Flags that redirect output:

- **`--output <path>`** — write the result JSON to a file instead of stdout.
- **`--events <path>`** — write the `PIRDebugEvent` stream as **JSONL** (one JSON object per line)
  to `<path>`.
- **`--events -`** — **deliberate inversion of the usual `-` convention.** `-` sends the event
  stream to **stderr** (interleaved with progress logs), *not* stdout, so the result channel stays
  JSON-only. This is called out in `--help`.

Because of the fd swap, **`--help` / usage text prints to stderr**, not stdout. (ArgumentParser
writes help to what it thinks is stdout, which is now the swapped-over descriptor pointing at
stderr.) A clean `--help`/`--version` still exits 0.

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success — **including a clean zero-record scan** (empty `extractedProfiles`). |
| `1` | Operation failed — a scan query with `error` outcome, an opt-out failure, or any `validate` file failure. |
| `2` | Usage / configuration error — bad flags, unreadable/undecodable files, more than one rules or script source, a rules-fetch failure. |
| `3` | Timeout — the `--timeout` watchdog fired. |

> **Behavioural note (accurate to the code):** both `scan` and `optout` map a **thrown failure of
> the scan/opt-out operation itself** to exit `1`, while **setup and rules-fetch failures** (bad
> flags, unreadable files, a remote rules fetch that fails) exit `2`. A scan query that *completes*
> with an `error` outcome also exits `1`.

---

## Flags

### Shared option groups

These groups are attached to the subcommands that need them (noted per subcommand below).

**Rules source** (`RulesSourceOptions` — at most one explicit source; with none, rules are fetched
remotely from `--environment`):

| Flag | Meaning |
|------|---------|
| `--rules-dir <dir>` | A directory of broker JSON files (e.g. a dbp-api checkout's `dbp-json/data/json/`). |
| `--broker-file <path.json>` | A single broker JSON file. |
| `--dbp-api-branch <name>` | Fetch from a dbp-api staging **branch deploy**. The branch name is **sanitized** (see below). |
| `--dbp-api-url <url>` | Fetch from a verbatim dbp-api base URL (e.g. a localhost fake broker). |
| `--environment staging\|production` | DBP environment for the remote fetch **and** the email/captcha services endpoint. Default `staging`. |

`--environment` always selects the services endpoint (staging → `https://dbp-staging.duckduckgo.com`,
production → `https://dbp.duckduckgo.com`), even when the rule source is local.

**Broker selection** (`BrokerSelectionOptions` — used by `scan`):

| Flag | Meaning |
|------|---------|
| `--broker <name-or-domain>` | Select brokers by name or URL. Exact match wins; otherwise substring match. |
| `--all` | Run every broker in the source. Required when no `--broker` is given (no selector + no `--all` ⇒ error). |

**Script source** (`ScriptSourceOptions` — default is the bundled C-S-S resource; at most one
explicit source):

| Flag | Meaning |
|------|---------|
| `--css-script <file>` | Inject this `contentScopeIsolated.js` file directly (bypasses the process-lifetime JS cache). |
| `--css-checkout <dir>` | Build and inject from a content-scope-scripts checkout. |
| `--css-no-build` | Skip the build; use the existing `dist` artifact in `--css-checkout`. |
| `--css-branch <branch>` | Download a `pr-releases/<branch>` CI build. Branch name used **verbatim** (slashes included). |

**Auth** (`AuthOptions`) — used **only** by the email/captcha services (opt-out and the `email`
commands). Rules fetch and captcha-free scans need no credentials. Two sources, in precedence order:

| Flag | Meaning |
|------|---------|
| `--auth-token <jwt>` | An access token used **verbatim, never refreshed**. Falls back to env `PRIVACYPRO_STAGING_ACCESS_TOKEN_V2`. Overrides the stored token. |
| `--token-file <path>` | The stored token container to use. Default `~/.config/pir-debug/token.json`, written by `pir-debug auth import` or the app's export item — **refreshed automatically**. See [`auth`](#auth). |

Prefer the stored container. Access tokens are short-lived (minutes on staging), so a bare
`--auth-token` goes stale *mid-run*: an `optout --wait-for-email` or `email inbox --wait` that
outlives its token starts getting 401s from the services. The stored container is refreshed on every
request, so long waits keep working.

**Runtime** (`RuntimeOptions`):

| Flag | Meaning |
|------|---------|
| `--show-webview` | Show the web view window (activation policy `.accessory` instead of `.prohibited`). |
| `--await-time <seconds>` | Seconds awaited around every action. Fractional allowed, must be `>= 0`. Default `1`. |
| `--timeout <seconds>` | Watchdog; the process exits `3` if exceeded. Default `600`. (`serve` disables the watchdog.) |
| `--verbose` | Verbose progress logging on stderr. |
| `--user-agent <safari\|tool\|verbatim>` | The web view's `applicationNameForUserAgent`. Default `safari` reproduces the app's `Version/<safari> Safari/<webkit>`; `tool` sends `pir-debug`; anything else is sent as-is. See [bot management](#bot-management). |

**Output** (`OutputOptions`): `--output`, `--events` (see [I/O contract](#io-contract)).

### Subcommands

#### `scan`

```
pir-debug scan --profile p.json (--broker <selector> | --all) [rules/script/auth/runtime/output flags]
```

Runs a scan for the selected broker(s) against the profile. Groups: rules, script, auth, runtime,
output, broker-selection. Required: `--profile`.

- Result JSON is a **single `PIRScanResult`** when exactly one broker is selected, or an **array**
  of them for multiple / `--all`.
- Exit `1` if any query outcome is `error`; otherwise `0` (a zero-record scan is `0`).

#### `optout`

```
pir-debug optout --profile p.json --broker <selector> --extracted results.json \
  [--index <n> | --all-matches] [--wait-for-email --poll-interval <s>] [rules/script/auth/runtime/output flags]
```

Runs opt-out for extracted profile(s) taken from a prior `scan` result JSON. Required: `--profile`,
`--broker`, `--extracted`.

| Flag | Meaning |
|------|---------|
| `--extracted <path>` | The `scan` result JSON (single object or array) containing `extractedProfiles[]`. |
| `--index <n>` | Opt out the profile at this 0-based index (within the broker's matches). |
| `--all-matches` | Opt out every matching extracted profile. |
| `--wait-for-email` | After submitting opt-out, poll for the email-confirmation link and continue the opt-out (mirrors the debug window's two-button flow). |
| `--poll-interval <s>` | Seconds between email-confirmation polls (with `--wait-for-email`). Default `15`. |

If neither `--index` nor `--all-matches` is given and the broker has exactly one match, that one is
used; otherwise you must disambiguate. Result JSON is a single `PIROptOutResult` (or an array for
`--all-matches`).

> **An opt-out that halts awaiting email confirmation *without* `--wait-for-email` exits `0`** — a
> `PIROptOutResult` with `awaitingEmailConfirmation: true` is an expected halt, not a failure.

#### `email`

```
pir-debug email generate --broker <domain> [--attempt-id <uuid>] [--wait] [--poll-interval <s>]
pir-debug email inbox --email <address> --attempt-id <uuid> [--wait] [--poll-interval <s>]
pir-debug email delete --email <address> --attempt-id <uuid>
```

Drives the DBP disposable-email services directly — no rules source, no script source, no web view.
These are the same services a scan/opt-out hits from a broker's `generateEmail` / `emailConfirmation`
/ `getEmailData` actions, so this is the way to check the email side on its own: generate an address,
watch what the backend extracts from mail sent to it, then clear it.

A mailbox is keyed by **(address, attempt id)** — the pair the v1 `email-data` endpoint takes — so
keep the `attemptId` that `generate` reports and pass it to `inbox` / `delete`. `generate` also
prints the exact `email inbox` command to stderr.

Every subcommand needs a token: `--auth-token`, or `PRIVACYPRO_STAGING_ACCESS_TOKEN_V2`. Without one
the command exits `2` up front rather than failing inside the service.

Shared flags (`EmailOptions`, plus `AuthOptions`):

| Flag | Meaning |
|------|---------|
| `--environment staging\|production` | Which environment's email service to use. Default `staging`. |
| `--services-url <url>` | Verbatim services base URL, overriding `--environment` (e.g. a localhost fake service). **Only the `email` commands expose this**; `scan`/`optout` derive the endpoint from `--environment`. |
| `--output <path>` | Write result JSON to a file instead of stdout. |
| `--timeout <seconds>` | Watchdog (exit `3`). Default `600`. This is what bounds `--wait`. |
| `--verbose` | Verbose progress logging on stderr. |

Per-subcommand:

| Flag | Meaning |
|------|---------|
| `--broker <domain>` (`generate`) | Sent as the service's `dataBroker` parameter — the broker JSON's `url` (e.g. `fakebroker.com`), exactly what the engine sends. |
| `--attempt-id <uuid>` | On `generate`, the id to generate under (default: a fresh UUID). On `inbox`/`delete`, **required** — the id `generate` reported. Non-UUID values are a usage error, since a wrong id silently reads a different mailbox. |
| `--email <address>` (`inbox`, `delete`) | The generated address. |
| `--wait` (`generate`, `inbox`) | Poll the mailbox until it leaves `pending`. Unbounded except by `--timeout`, matching `optout --wait-for-email`. |
| `--poll-interval <s>` | Seconds between polls with `--wait`. Default `15`. |

Exit codes: `ready` and `pending` both exit `0` (pending is an expected state, not a failure); the
service reporting `error`/`unknown` for the mailbox, or returning no item for the pair at all, exits
`1`.

#### `auth`

```
pir-debug auth status  [--token-file <path>] [--output <path>]
pir-debug auth import  (--file <token.json> | --stdin) [--token-file <path>]
pir-debug auth refresh [--environment staging|production] [--timeout <s>]
pir-debug auth logout  [--token-file <path>]
```

Manages the CLI's own subscription token, so opt-out and the `email` commands can run off a real
subscription instead of a hand-pasted access token. `status` is the default subcommand.

**Why the token is copied rather than read.** The app stores its token container in the
**data-protection keychain under an access group** (`AppDelegate` → `KeychainType.dataProtection(.named(subscriptionAppGroup))`).
Reading that requires the process to be signed with matching entitlements and the team-ID prefix;
`pir-debug` is an unsigned SPM executable with none, so it cannot read the app's token at all. Instead
the container is handed over once and kept at `~/.config/pir-debug/token.json` (mode `0600`), and the
CLI refreshes it from then on.

Setup:

1. In the DuckDuckGo app: log in, then **Debug › Privacy Pro › Export Token for pir-debug**.
2. `pir-debug auth status`

| Subcommand | Does |
|------------|------|
| `status` | Prints the stored token's issuer/environment, email, external ID, entitlements and both expiries. Offline — no refresh. Exits `1` if unusable (absent, refresh token expired, or no PIR entitlement). |
| `import` | Stores a token container JSON (`--file` or `--stdin`) and then reports its status. For the paste path, or when the app wrote it somewhere else. |
| `refresh` | Forces a refresh now — proves the stored refresh token still works. `--environment` must match the token's issuer. |
| `logout` | Deletes the stored file. **Local only** — the app stays signed in, because the refresh token is the app's too and invalidating it server-side would sign the app out. |

The environment must match: a token issued by staging auth (`quackdev`) is rejected by production DBP
services and vice versa. `auth status` reports which one the stored token came from, and the app
exports whichever environment it was logged into (the Subscription debug menu can switch it).

> **`accessTokenExpired: true` in `auth status` is normal.** Access tokens are short-lived; the
> refresh token is the durable credential. Only `refreshTokenExpired` means you need a fresh export.

There is no self-service login: auth v2's `createAccount` yields an account with
`entitlements: []`, and the DBP services reject it with `401 Authorization required`, so an entitled
subscription (staging sandbox/Stripe test, or production) is required.

#### `validate`

```
pir-debug validate [--rules-dir <dir>] [--broker-file <f.json> ...]
```

Decodes each broker JSON with the **exact runtime decoder** (`JSONDecoder().decode(DataBroker.self,…)`)
and reports per-file OK/failure. Catches JSON that passes dbp-api's schema but the app can't parse.
Exit `1` if any file fails.

> `validate` takes its **own local-only** `--rules-dir` / `--broker-file` (`--broker-file` is
> repeatable here) — it does **not** accept the remote rules-source flags (`--dbp-api-branch`,
> `--dbp-api-url`, `--environment`). Validation is a local-file operation.

#### `list-brokers`

```
pir-debug list-brokers [rules flags]
```

Resolves the rules source and prints a name/url/version/steps summary as JSON. Groups: rules,
output.

#### `fetch-rules`

```
pir-debug fetch-rules --out <dir> [--include-test-brokers] [remote rules flags]
```

Materializes `main_config.json` + all active broker JSONs from a **remote** source to `--out`,
byte-identical to the zip contents. Requires a remote source (`--dbp-api-branch`, `--dbp-api-url`,
or `--environment`); passing a local `--rules-dir`/`--broker-file` is a usage error.

| Flag | Meaning |
|------|---------|
| `--out <dir>` | Output directory (required). |
| `--include-test-brokers` | Also materialize brokers listed in `test_data_brokers`. |

Exit `1` if any wanted broker is missing from the zip; `0` otherwise.

#### `serve`

```
pir-debug serve [--port 8475] [rules/script/auth/runtime flags]
```

Long-running localhost HTTP server over one shared `PIRDebugSession`. Default port **8475**
(8473 = DebugServer default, 8474 = existing agent server). No output group; results are returned
over HTTP. The watchdog is disabled. See [HTTP API](#serve-http-api).

---

## `profile.json` schema

`DebugProfile` — a mirror of the debug-window form and `DataBrokerProtectionProfile`:

```json
{
  "names": [
    { "firstName": "John", "middleName": "Q", "lastName": "Smith" }
  ],
  "addresses": [
    { "city": "Dallas", "state": "TX" }
  ],
  "phones": [],
  "birthYear": 1960
}
```

| Field | Type | Notes |
|-------|------|-------|
| `names` | array of `{ firstName, middleName?, lastName }` | `middleName` is optional. |
| `addresses` | array of `{ city, state }` | |
| `phones` | array of strings | May be empty. |
| `birthYear` | integer | |

The engine expands the profile into one *profile query* per `name` × `address` combination. A
query's label has the form `"<firstName> <lastName> x <city> <state>"` (e.g. `John Smith x Dallas TX`);
this label appears in results and events and is what `optout` matches against.

---

## Result JSON schemas

All result JSON is pretty-printed with sorted keys and unescaped slashes.

### `scan` → `PIRScanResult` (or `[PIRScanResult]`)

```jsonc
{
  "brokerName": "fakebroker.com",
  "brokerURL": "fakebroker.com",
  "brokerVersion": "0.1.0",
  "brokerId": 123456789,
  "queryStatuses": [
    {
      "profileQueryId": 987654321,
      "profileQueryLabel": "John Smith x Dallas TX",
      "outcome": "matches",              // "matches" | "noMatch" | "error"
      "extractedProfileCount": 1,
      "error": null
    }
  ],
  "extractedProfiles": [ /* PIRExtractedProfileRecord — see below */ ],
  "duration": 4.21,
  "eventCount": 12
}
```

**`PIRExtractedProfileRecord`** (each element of `extractedProfiles`) — carries the stable IDs
needed to drive a later `optout` (deterministic across processes):

```jsonc
{
  "brokerId": 123456789,
  "profileQueryId": 987654321,
  "profileQueryLabel": "John Smith x Dallas TX",
  "extractedProfile": {
    "id": 1122334455,
    "name": "John Smith",
    "alternativeNames": [],
    "addressFull": null,
    "addresses": [ { "city": "Dallas", "state": "TX" } ],
    "phoneNumbers": [],
    "relatives": [],
    "profileUrl": "https://fakebroker.com/profile/1",
    "reportId": null,
    "age": "63",
    "email": null,
    "removedDate": null,
    "fullName": "John Smith",
    "identifier": "https://fakebroker.com/profile/1"
  }
}
```

(`extractedProfile` is the engine's `ExtractedProfile`; all fields are optional/nullable.)

### `optout` → `PIROptOutResult` (or `[PIROptOutResult]`)

```jsonc
{
  "brokerName": "fakebroker.com",
  "brokerURL": "fakebroker.com",
  "brokerVersion": "0.1.0",
  "brokerId": 123456789,
  "profileQueryId": 987654321,
  "profileQueryLabel": "John Smith x Dallas TX",
  "extractedProfileId": 1122334455,
  "lastStage": "…",                    // last recorded debug-event detail, for diagnosis
  "success": true,
  "awaitingEmailConfirmation": false,
  "error": null,
  "duration": 6.3,
  "eventCount": 20
}
```

### `email generate` → `PIRDebugGeneratedEmail`

```jsonc
{
  "dataBroker": "fakebroker.com",
  "email": "abc123@duck.com",
  "pattern": "fakebroker.com+*@duck.com",   // the service's address pattern, when it reports one
  "attemptId": "11111111-2222-3333-4444-555555555555"
}
```

With `--wait`, the same object gains an `inbox` field holding the item below (or `null` if the
service returned nothing for the mailbox).

### `email inbox` → `PIRDebugEmailInboxItem`

```jsonc
{
  "email": "abc123@duck.com",
  "attemptId": "11111111-2222-3333-4444-555555555555",
  "status": "ready",                        // "ready" | "pending" | "unknown" | "error"
  "errorCode": null,                        // "server_error" | "extraction_error" | "request_error"
  "confirmationLink": "https://fakebroker.com/confirm/abc",   // the "link" datum, once ready
  "data": {                                 // every datum the service extracted, by name
    "link": "https://fakebroker.com/confirm/abc",
    "code": "12345"
  },
  "receivedAt": "2026-07-25T17:20:00.500Z"  // ISO-8601, as in the event stream
}
```

`data` is the full bag a broker's `getEmailData` action selects keys from; `confirmationLink` is
just the `link` key surfaced for convenience.

### `email delete` → report

```jsonc
{ "email": "abc123@duck.com", "attemptId": "1111…", "deleted": true }
```

### `auth status` → report

Claims only — the token strings are never printed.

```jsonc
{
  "tokenFile": "/Users/me/.config/pir-debug/token.json",
  "present": true,
  "issuer": "https://quackdev.duckduckgo.com",
  "environment": "staging",                     // derived from the issuer; null if unrecognised
  "email": "me@duck.com",
  "externalID": "ad9dd169-…",
  "entitlements": ["Data Broker Protection", "Network Protection"],
  "hasPIREntitlement": true,
  "accessTokenExpired": true,                   // normal — refreshed on the next request
  "accessTokenExpiresAt": "2026-07-30T02:00:29Z",
  "refreshTokenExpired": false,                 // the one that matters
  "refreshTokenExpiresAt": "2026-08-29T02:01:29Z"
}
```

### `validate` → report

```jsonc
{
  "total": 3,
  "failures": 1,
  "results": [
    { "file": "/abs/path/fakebroker.com.json", "ok": true,  "brokerName": "fakebroker.com", "error": null },
    { "file": "/abs/path/broken.json",         "ok": false, "brokerName": null,             "error": "…decoding error…" }
  ]
}
```

### `list-brokers` → array of summaries

```jsonc
[
  {
    "name": "fakebroker.com",
    "url": "fakebroker.com",
    "version": "0.1.0",
    "optOutUrl": "https://fakebroker.com/optout",
    "parent": null,
    "stepTypes": ["scan", "optOut"],
    "performsOptOutWithinParent": false
  }
]
```

### `fetch-rules` → report

```jsonc
{
  "outputDirectory": "/abs/out",
  "mainConfig": "main_config.json",
  "brokers": ["fakebroker.com.json", "…"],
  "missing": []
}
```

### `PIRDebugEvent` JSONL (`--events`)

One JSON object per line:

```jsonc
{
  "timestamp": "2026-07-21T12:34:56.789Z",   // ISO-8601 with fractional seconds
  "profileQueryLabel": "John Smith x Dallas TX",
  "kind": "actionResponse",                   // actionPayload | actionResponse | actionRetry | wait | history
  "actionType": "navigate",                   // optional
  "details": "…"
}
```

---

## `serve` HTTP API

Bound to `127.0.0.1` only, **no auth**, default port **8475**. Route handlers are synchronous and
share one serial queue, so `POST /scan` and `POST /optout` validate the request, kick off the work
in a background task, and return **`202 {jobId}`** immediately; poll `GET /jobs/<id>` for the
result. Only **one job runs at a time**: a `POST` while a job is in flight returns **`409`**.

| Method / path | Body | Response |
|---------------|------|----------|
| `GET /` | — | Endpoint listing. |
| `POST /scan` | `{ "profile": <DebugProfile>, "broker"?: string, "all"?: bool }` | `202 { "jobId": "<uuid>" }`, or `409` if a job is running |
| `POST /optout` | `{ "profile": <DebugProfile>, "broker": string, "extracted": <scan result JSON>, "index"?: int, "allMatches"?: bool, "waitForEmail"?: bool, "pollInterval"?: number }` | `202 { "jobId": "<uuid>" }`, or `409` if a job is running |
| `GET /jobs/<id>` | — | `{ "id", "kind", "status": "running"\|"succeeded"\|"failed", "error"?, "result"? }` |
| `GET /brokers` | — | Array of `{ name, url, version, optOutUrl, stepTypes }` |
| `GET /events?since=<cursor>` | — | `{ "nextCursor": int, "events": [ <PIRDebugEvent> … ] }` |

`extracted` in `POST /optout` is the scan **result JSON itself** (a `PIRScanResult` object or an
array of them), not a file path. `since` defaults to `0`; poll with the returned `nextCursor`.

> `serve` required adding `202 accepted` and `409 conflict` cases to `DebugServer`'s
> `HTTPStatusCode`.

---

## Agent loops

Worked, copy-pasteable examples. Assume `cd macOS/LocalPackages/PIRDebugCLI` and a `p.json` profile
in the current directory. Substitute the bundled fake broker for a real path:

```
FAKE=../../../SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/fakebroker.com.json
```

### Rules loop (edit a rule in a dbp-api checkout → validate → scan → assert)

```bash
# 1. Edit a broker JSON in your dbp-api checkout, e.g. ~/code/dbp-api/dbp-json/data/json/fakebroker.com.json

# 2. Validate it decodes with the exact runtime decoder (catches schema-valid-but-unparseable JSON):
swift run pir-debug validate --rules-dir ~/code/dbp-api/dbp-json/data/json

# 3. Scan a single broker from that directory:
swift run pir-debug scan \
  --rules-dir ~/code/dbp-api/dbp-json/data/json \
  --broker fakebroker.com \
  --profile p.json \
  --output result.json

# 4. Assert on the result JSON with jq (exit non-zero fails the loop):
jq -e '.queryStatuses[0].outcome == "matches" and (.extractedProfiles | length) >= 1' result.json
```

Piping the result channel straight into `jq` also works because stdout is JSON-only even with
`--verbose` (progress goes to stderr):

```bash
swift run pir-debug scan --broker-file "$FAKE" --profile p.json --verbose | jq '.extractedProfiles | length'
```

### C-S-S loop (edit a feature → scan with the local build)

```bash
# One-time in the checkout: install deps.
( cd ~/code/content-scope-scripts/injected && npm ci )

# Edit a feature under injected/, then scan — the CLI runs
#   node scripts/entry-points.js --platform apple-isolated
# in <checkout>/injected and injects <checkout>/Sources/ContentScopeScripts/dist/contentScopeIsolated.js:
swift run pir-debug scan \
  --css-checkout ~/code/content-scope-scripts \
  --broker-file "$FAKE" --profile p.json

# If you've already built and just want to re-use the existing dist artifact, skip the build:
swift run pir-debug scan --css-checkout ~/code/content-scope-scripts --css-no-build \
  --broker-file "$FAKE" --profile p.json
```

If `node_modules` is missing the tool exits `2` with "run npm ci in the checkout first". You can
also inject a single prebuilt file directly with `--css-script <path>/contentScopeIsolated.js`.

### Branch validation

**dbp-api branch deploy** — label the dbp-api PR `upload-remote-config` (workflow
`upload_remote_configuration_pr.yml`) so its rules are served under
`https://dbp-staging.duckduckgo.com/branches/<sanitized-branch>/…`. The CLI applies the **same
sanitization** dbp-api does: lowercase, then every character outside `[a-z0-9.-]` → `-`. So
`randerson/fix-foo` is fetched from `branches/randerson-fix-foo`:

```bash
swift run pir-debug list-brokers --dbp-api-branch randerson/fix-foo
swift run pir-debug scan --dbp-api-branch randerson/fix-foo --broker fakebroker.com --profile p.json
```

**content-scope-scripts branch** — C-S-S CI builds each branch's artifacts into a
`pr-releases/<branch>` branch. The branch name is used **verbatim** (slashes included). The CLI
resolves `pr-releases/<branch>` to an immutable commit SHA via the GitHub API, then downloads
`Sources/ContentScopeScripts/dist/contentScopeIsolated.js` from raw.githubusercontent at that SHA
(avoids raw's CDN staleness, gives a clean cache key), caching by SHA:

```bash
swift run pir-debug scan --css-branch my/feature-branch --broker-file "$FAKE" --profile p.json
```

The unauthenticated GitHub API limit is **60 requests/hour**; set `GITHUB_TOKEN` to raise it. A
branch with no CI build yields a clear error.

### Opt-out testing (with your own subscription + email confirmation)

Opt-out email/captcha need credentials. The durable way — log in once in the app, then the CLI keeps
itself alive:

```bash
# In the app: Debug › Privacy Pro › Export Token for pir-debug (Environment submenu picks staging/production)
swift run pir-debug auth status          # confirms environment + "Data Broker Protection" entitlement

swift run pir-debug scan --broker-file "$FAKE" --profile p.json --output scan.json
swift run pir-debug optout --broker-file "$FAKE" --profile p.json \
  --broker fakebroker.com --extracted scan.json \
  --wait-for-email --poll-interval 15 --timeout 900   # survives access-token expiry mid-wait
```

The shared staging JWT still works and takes precedence when supplied (`--auth-token` or the env var,
stored in **Bitwarden**) — but it is a bare access token, so a long `--wait` can outlive it:

```bash
export PRIVACYPRO_STAGING_ACCESS_TOKEN_V2="$(… fetch from Bitwarden …)"

# First scan to produce extracted profiles:
swift run pir-debug scan --broker-file "$FAKE" --profile p.json --output scan.json

# Then opt out, waiting for the email-confirmation link and continuing automatically:
swift run pir-debug optout \
  --broker-file "$FAKE" --profile p.json \
  --broker fakebroker.com --extracted scan.json \
  --wait-for-email --poll-interval 15 \
  --timeout 900
```

Without `--wait-for-email`, an opt-out that stops to await confirmation exits `0` with
`awaitingEmailConfirmation: true`.

### Email loop (check the email side without running a scan)

Same token. Useful when an opt-out stalls at email confirmation and you want to know whether the
problem is the mail or the rule:

```bash
export PRIVACYPRO_STAGING_ACCESS_TOKEN_V2="$(… fetch from Bitwarden …)"

# 1. Generate an address for the broker, and keep the mailbox key:
swift run pir-debug email generate --broker fakebroker.com --output mailbox.json
ADDRESS=$(jq -r .email mailbox.json)
ATTEMPT=$(jq -r .attemptId mailbox.json)

# 2. Send mail to $ADDRESS (submit the broker's opt-out form with it), then read the mailbox:
swift run pir-debug email inbox --email "$ADDRESS" --attempt-id "$ATTEMPT"

# …or block until something lands (bounded by --timeout, exit 3 if it never does):
swift run pir-debug email inbox --email "$ADDRESS" --attempt-id "$ATTEMPT" \
  --wait --poll-interval 15 --timeout 900 | jq -r .confirmationLink

# 3. Clear the backend's copy when you're done:
swift run pir-debug email delete --email "$ADDRESS" --attempt-id "$ATTEMPT"
```

`generate --wait` collapses steps 1–2 into one command when the mail is triggered elsewhere. Against
a local fake email service, add `--services-url http://localhost:<port>` to every call.

### Always use fake brokers for automated loops

Point loops at `DuckDuckGo/pir-fake-broker` (served at `http://localhost:3001`) or the bundled fake
broker JSONs:

- `SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/fakebroker.com.json`
- `SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/fakeremovedbroker.com.json`

To fetch rules from a running fake-broker HTTP endpoint use `--dbp-api-url http://localhost:3001`.
Do **not** run automated loops against real broker sites.

---

## Bot management

`applicationNameForUserAgent` is appended to the web view's User-Agent, and a tool-shaped value is
enough for a broker behind bot management to serve an interstitial instead of the page. So the
default is `--user-agent safari`, which reproduces the macOS app's
`Version/<safari> Safari/<webkit>` (`PIRDebugUserAgent.safariLike`, mirroring the app's
`WebViewUserAgentProvider`). Use `--user-agent tool` to be identifiable against your own fixtures.

**The UA is not sufficient for every broker.** Some clusters — cyberbackgroundchecks.com among them —
sit behind Cloudflare bot management that this tool does not get past regardless of UA: the web view
sits on `Performing security verification` indefinitely (verified over a ~2 minute wait), and there is
no interactive widget to solve, so `--show-webview` doesn't help either. Fingerprinting beyond the UA
(the unsigned executable, an ephemeral `WKWebsiteDataStore` with no `cf_clearance`, TLS/IP signals) is
the likely cause.

To tell a challenge apart from a broken selector, scrape the page text into
[`extras`](#result-json-schemas) — any profile key the extractors don't recognise falls through to a
generic text extraction, and the `extract` action's debug event carries the scraped data:

```jsonc
{ "actionType": "extract", "selector": "body", "noResultsSelector": "body",
  "profile": { "zzBodyText": { "selector": "body" } } }
```

```bash
pir-debug scan --broker-file probe.json --broker probe --profile p.json --events events.jsonl
jq -r 'select(.actionType=="extract" and .kind=="actionResponse") | .details' events.jsonl
```

When a broker is unreachable this way, validate the rule against local fixtures that reproduce its
markup and form field IDs instead, and treat live markup drift as unverified.

## SPM-repoint fallback (native ↔ JS contract changes)

The `--css-*` flags only swap the **JS artifact** (`contentScopeIsolated.js`); the Swift-side
message contract still comes from BrowserServicesKit's pinned content-scope-scripts package. If your
C-S-S change **also** alters the native↔JS message contract, the JS-only override is not enough —
repoint BSK's pin at your local checkout:

In `SharedPackages/BrowserServicesKit/Package.swift`, change

```swift
.package(url: "https://github.com/duckduckgo/content-scope-scripts.git", exact: "15.18.0"),
```

to

```swift
.package(path: "../../../content-scope-scripts"),   // your local checkout
```

so both the Swift contract and the JS artifact come from the same tree. Revert before committing.

---

## Known deviations / caveats

- **`fetch-rules`** unzips the broker archive with the system `/usr/bin/unzip`.
- **`--css-checkout`** builds with the system `node` (`/usr/bin/env node`); it must be installed and
  on `PATH`.
- **`serve`** required adding `202 accepted` and `409 conflict` cases to `DebugServer`'s
  `HTTPStatusCode`.
- **`serve` binds `127.0.0.1` only** (loopback), and runs **one job at a time** — a `POST /scan` or
  `POST /optout` while another job is in flight returns **HTTP 409** (so concurrent jobs cannot
  corrupt the single shared session's multi-step state). Its job table and event buffer are capped
  to keep a long-running server's memory bounded; `/events` cursors stay monotonic across trims.
- **`--all-matches` always emits a JSON array** (even for a single match); a single-profile opt-out
  (via `--index` or a lone match) emits a single object.
- An **opt-out that halts awaiting email confirmation without `--wait-for-email` exits `0`** (an
  expected halt, not a failure).
- **`email inbox` with `status: "pending"` exits `0`** for the same reason; only `error`/`unknown`,
  or no item at all for the (address, attempt id) pair, exit `1`.
- **`--services-url` exists only on the `email` commands.** `scan`/`optout`/`serve` still derive the
  services endpoint from `--environment`.
- **`--auth-token` is never refreshed.** It is used exactly as given, so a run longer than the access
  token's lifetime starts failing partway through. Use the stored container (`auth import`) for long
  waits.
- **The stored token file holds a refresh token** — a real credential, in plaintext under `$HOME` at
  mode `0600`. `auth logout` deletes it. The CLI's own keychain item would be stronger, but an
  unsigned binary's keychain ACL is path/identity-bound and re-prompts after every `swift build`,
  which breaks unattended loops.
- **`auth logout` is local only.** It does not call the auth service's logout, because the refresh
  token is shared with the signed-in app and invalidating it would sign the app out too.
- **Date fidelity in the token file is load-bearing.** `OAuthClient.getTokens(policy: .localValid)`
  decides whether to refresh from the deserialized `exp` claim, so the store encodes and decodes with
  matching `Date` strategies; `PIRDebugTokenStoreTests` pins that round-trip.
- **Acceptance criteria 1, 3, and 5** (live headless scan, headed scan with `--show-webview`, and
  the opt-out email-confirmation continuation) require a manual run against a **running** fake
  broker and were **not** automatically verified.
