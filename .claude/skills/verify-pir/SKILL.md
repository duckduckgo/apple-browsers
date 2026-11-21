---
name: verify-pir
description: Run a live PIR broker scan and optional opt-out through the shared debug API on iOS or macOS, run a native selftest without broker requests, or verify persisted scheduler scans. Supports a supplied access token for unattended captcha and email flows. Invoke explicitly because it submits real broker requests.
disable-model-invocation: true
---

# verify-pir

Run one broker against a test profile on iOS or macOS. The standalone Python runner starts jobs through the PIR debug
API, checks their results and history, saves evidence, and stops its app or agent. It needs Python 3 and Xcode's command
line tools. Builds and simulator operations use `xcodebuild` and `xcrun simctl` directly.
It has no dependency on verify-ios, a UI runner, or a Python proof file.

The `run` command verifies the broker flow through the shared native `DebugModeRunner`. It does not verify the
dashboard, profile editor, subscription sign-in, production scheduler or their entry points. Confirmed opt-out means
submission and confirmation completed. Removal requires a later scan.

Work in this order: choose the scenario, prepare inputs, build, run `selftest` and `--check-config`, run scan-only, then
run the opt-out after the user authorizes it. The checks before the scan send no broker requests.

## 1. Choose the scenario

- **Scan only**, `"optOut": false`: pass when the app matches at least one record. No match is inconclusive. Supply a
  token if the broker's scan needs the captcha service and the app has no saved subscription.
- **Scan and opt-out**, `"optOut": true`: scan, select one matched record, submit its opt-out and, when configured,
  complete email confirmation. Use a saved subscription with PIR entitlement or supply a token.

Before submitting an opt-out, obtain the user's authorization for the broker, profile, selected record and scenario.
An opt-out sends real broker requests and cannot be undone. Run scan-only first to identify the record. With several
matches, `expectedFile` must name the exact `profileUrl` to select. The app performs profile matching; this runner does
not implement another matcher.

A child broker, whose opt-out step is `parentSiteOptOut`, opts out through its `parent`. The app skips its opt-out as
production does, so the run reports the scan verdict and leaves the opt-out unverified. To test the removal, run the
opt-out against the parent broker.

## 2. Prepare inputs and credentials

Keep a configuration, complete broker JSON and profile JSON in a durable folder outside the checkout, such as
`~/pir-runs/example/`. Paths in the configuration are relative to that file. The profile uses the `-pirProfileJSON`
shape. `expectedFile` is optional and contains only `{"profileUrl": "..."}`. For scan-only runs it checks that the
expected record was found.

```json
{
  "brokerFile": "broker.json",
  "profileFile": "profile.json",
  "expectedFile": "expected.json",
  "optOut": true,
  "emailConfirmation": true,
  "subscriptionEnvironment": "staging",
  "pirEnvironment": "staging",
  "pirEndpoint": "https://dbp-staging.duckduckgo.com",
  "activityTimeout": 600,
  "emailTimeout": 300
}
```

A scan-only run without a token needs only `brokerFile`, `profileFile` and `"optOut": false`. An opt-out or a run with a
supplied token also needs the environment and endpoint fields, and a supplied token requires `subscriptionEnvironment`
and `pirEnvironment` to match. For an opt-out, set `emailConfirmation` to `true` or `false`.

Without a supplied token, the native prerequisite check verifies that the saved subscription is signed in, has PIR
entitlement and matches the configured environment before any broker requests. The macOS agent can use its saved
subscription. The iOS runner creates a fresh simulator, so an iOS opt-out needs a supplied token.

Supply an existing access token with `--token-file /local/path/to/token` (the file contains only the token) or
`--token-env ENVIRONMENT_VARIABLE_NAME`. Do not ask the user to paste it into chat, and keep it out of configuration
files; the runner rejects inputs that contain it. The runner uses the token as given and passes it only through the
launch environment, never in arguments, logs or evidence.

A supplied token replaces saved-account authentication for that launch only. A malformed token or an authentication
failure fails the run. Reports mark token authentication and leave normal sign-in unverified.

## 3. Build and check

From the worktree root:

```sh
P=.claude/skills/verify-pir/pir.py
python3 "$P" build --platform ios
python3 "$P" selftest --platform ios --evidence-dir ~/pir-runs/evidence
python3 "$P" run --platform ios --config ~/pir-runs/example/config.json \
  --token-file /local/path/to/token --check-config
```

Use `--platform macos` for the macOS PIR agent. Use `--device ipad` on the iOS build and run commands for an iPad run.

`build` records the app's source fingerprint and executable hash; later commands reject a stale or changed build, so
rebuild after source changes. On macOS, `build` enables debug deployment with
`scripts/toggle-macos-debug-deployment.sh on`, builds a private DEBUG browser bundle under
`DerivedData/verify-pir/macos/` and discovers its embedded PIR agent. It preserves unrelated local overrides, leaves
`/Applications/DEBUG` intact, and does not change a saved simulator selection.

`selftest` uses the recorded build, forces staging with an internal dummy credential, checks correlated prerequisites,
collects native and redacted application logs, writes the usual report and manifest, and stops its runtime. It only
reads local HTTP endpoints and rejects scenario, credential, check-config and keep options. It does not establish real
authentication, broker execution, captcha handling, email delivery or removal. Evidence and cleanup failures make it
inconclusive.

`--check-config` validates the configuration, inputs and token source without building, launching or submitting
requests.

## 4. Run

```sh
python3 "$P" run --platform ios --config ~/pir-runs/example/config.json \
  --token-file /local/path/to/token --evidence-dir ~/pir-runs/evidence
```

`--evidence-dir` defaults to `~/pir-evidence` and must be outside the checkout; each attempt gets a unique child folder.
Run long scans in the background and follow their printed history events.

Run each platform separately; success on one does not establish success on the other. The broker workflow and checks
are shared, while native WebKit behavior and broker user agents can differ. Each run uses an isolated debug launch and
a correlated server instance. iOS uses a dedicated simulator. macOS launches only the private bundle's embedded PIR
agent, without starting production scheduling or registering a login item; existing browser and agent processes keep
running. Do not run another debug client against an attempt in progress.

Cleanup stops the owned app or agent even with `--keep`, which only preserves the simulator for inspection. Cleanup
cannot undo a broker request already submitted.

### Inspecting a running or stalled job

The runner prints the live `snapshots/` directory before launch. macOS writes PNGs there directly; iOS copies them from
the simulator on each status poll and once before cleanup. Filenames give the capture sequence, scan or opt-out phase,
action type and capture point (`before`, `result` or `error`). Open the newest PNG and read the action events in the
latest `pir-http-*.json` next to it, then earlier PNGs to see when the page changed. Captures happen at action
boundaries, so the page can change between them. A `.unavailable` marker records a capture that produced no image.
Screenshots can show unredacted broker records and form values; keep them in the local attempt folder.

## 5. Report the result

Report pass, fail or inconclusive, the printed `report.md` path, failed checks, cleanup problems and unverified items.
The attempt folder also contains machine-readable results, build and launch identity, input hashes, the exact broker
bytes, changed HTTP responses, final run state, application logs, and a rerun command that uses credential references.
The report links available snapshots in capture order and notes collection errors. Missing screenshots leave the broker
verdict intact.

No match remains inconclusive in either scenario, and an error never counts as an empty scan. A broker breaking
(`httpError`, such as a 410 or 429, or `actionFailed`) is a legitimate terminal outcome: the run passes and names the
error. Any other error, including captcha, email, authentication and `jobTimeout`, and any activity timeout, is our
failure and fails the run. An accepted HTTP request is not job completion; the runner polls the same run ID and checks
the selected result and history.

## 6. Verify persisted scans

Choose the scheduler command by what should happen to the DEBUG profile:

- `scheduler seed --profile-file <path>` on macOS saves a profile in an empty store and starts scans.
  An existing profile is a refusal.
- `scheduler reseed --profile-file <path>` on macOS replaces the DEBUG PIR profile and job history, then starts scans.
  Obtain explicit approval for that reset before invoking it.
- `scheduler observe` on macOS or an iOS simulator watches scans triggered separately through the app.

Before seed or reseed, build the private macOS DEBUG browser, close any running DEBUG browser, and use a signed-out
DEBUG test account so the normal agent takes its Freemium scan path. The browser saves through the real PIR data manager
and starts its regular login item and debug server on port 8474. The tool reports the cutoff and eligible jobs, stops
the browser it launched, and leaves the saved test profile and registered agent in place. These commands make live
broker scans.

Before observe, use an app with an existing Freemium or subscription profile and its debug server enabled (on iOS, turn
on **Debug Server** in the PIR debug menu). Record the UTC cutoff before triggering the scan, leaving room for the
server's second-resolution timestamps, then repeat `--job` with each exact broker URL and active profile query ID from
`GET /api`. Observation makes only GET requests to the local app or agent. Pass `--platform ios` for a simulator and
`--port` if the listener is not on 8474.

```sh
python3 "$P" scheduler seed --platform macos --profile-file ~/pir-runs/profile.json
python3 "$P" scheduler observe --platform macos \
  --since 2026-11-20T15:00:00Z --job example.com 42 --timeout 600
```

Evidence contains the listener identity, persisted scan histories and `scheduler.json`; a seeded attempt adds
`scheduler-launch.json` with the native job plan. A pass requires a fresh `scanStarted` and a matching terminal
`matchesFound`, `noMatchFound` or broker `error` (`httpError` or `actionFailed`) for every expected job; broker errors
are listed in `scheduler.json`. A broker that a broker update removes during the run is reported as `removed` and
not awaited, because removed brokers are not scanned; if every expected broker is removed the run is inconclusive.
Any other terminal error fails, and so does a timeout with jobs still missing,
incomplete or ambiguous. Listener or HTTP setup problems are inconclusive. Recurring scheduler ticks and opt-out jobs are separate checks.

## 7. Test the verifier

Unit tests, without a simulator or live backend:

```sh
python3 -m unittest discover -s .claude/skills/verify-pir/tests -p 'test_*.py'
```

The native contract test connects the real Python client to the real Swift HTTP server with stub run and log services.
It checks response shapes, HTTP statuses, instance ownership, web-origin rejection, request parsing and redaction without
executing broker jobs:

```sh
xcodebuild -workspace DuckDuckGo.xcworkspace -scheme DataBrokerProtectionCore -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData/verify-pir/core-tests \
  -only-testing:DataBrokerProtectionCoreTests/DebugHTTPPythonContractTests test
```
