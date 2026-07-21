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

**Auth** (`AuthOptions`):

| Flag | Meaning |
|------|---------|
| `--auth-token <jwt>` | Staging JWT used **only** by email/captcha services during opt-out. Falls back to env `PRIVACYPRO_STAGING_ACCESS_TOKEN_V2`. Rules fetch and captcha-free scans need no token. |

**Runtime** (`RuntimeOptions`):

| Flag | Meaning |
|------|---------|
| `--show-webview` | Show the web view window (activation policy `.accessory` instead of `.prohibited`). |
| `--await-time <seconds>` | Seconds awaited around every action. Fractional allowed, must be `>= 0`. Default `1`. |
| `--timeout <seconds>` | Watchdog; the process exits `3` if exceeded. Default `600`. (`serve` disables the watchdog.) |
| `--verbose` | Verbose progress logging on stderr. |

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

### Opt-out testing (with staging token + email confirmation)

Opt-out email/captcha need a staging JWT. Supply it via `--auth-token` or the env var
`PRIVACYPRO_STAGING_ACCESS_TOKEN_V2` (stored in **Bitwarden**):

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

### Always use fake brokers for automated loops

Point loops at `DuckDuckGo/pir-fake-broker` (served at `http://localhost:3001`) or the bundled fake
broker JSONs:

- `SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/fakebroker.com.json`
- `SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/fakeremovedbroker.com.json`

To fetch rules from a running fake-broker HTTP endpoint use `--dbp-api-url http://localhost:3001`.
Do **not** run automated loops against real broker sites.

---

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
- **Acceptance criteria 1, 3, and 5** (live headless scan, headed scan with `--show-webview`, and
  the opt-out email-confirmation continuation) require a manual run against a **running** fake
  broker and were **not** automatically verified.
