---
name: verify-pir
description: Run a live PIR broker scan and optional opt-out through the shared debug API on iOS or macOS. Supports supplied subscription service tokens for unattended captcha and email flows. Invoke explicitly because it submits real broker requests.
disable-model-invocation: true
---

# verify-pir

Run one broker against a test profile on iOS or macOS. The standalone Python runner starts jobs through the PIR debug
API, checks their results and history, saves evidence, and stops its app or agent. It needs Python 3 and Xcode's command
line tools. Builds and simulator operations use `xcodebuild` and `xcrun simctl` directly.
It has no dependency on verify-ios, a UI runner, or a Python proof file.

This verifies the broker flow through the shared native `DebugModeRunner`. It does not verify the dashboard, profile
editor, subscription sign-in, production scheduler or their entry points. Confirmed opt-out means submission and
confirmation completed. Removal requires a later scan.

## 1. Choose the scenario

- **Scan only**, `"optOut": false`: pass when the app matches at least one record. No match is inconclusive. Supply a
  token if the broker's scan needs the captcha service.
- **Scan and opt-out**, `"optOut": true`: scan, select one matched record, submit its opt-out and, when configured,
  complete email confirmation. A supplied token removes the manual subscription login step.

Before submitting an opt-out, obtain the user's authorization for the broker, profile, selected record and scenario.
An opt-out sends real broker requests and cannot be undone. A scan-only run can identify the record first. With several
matches, `expectedFile` must name the exact `profileUrl` to select. The app performs profile matching; this runner does
not implement another matcher.

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

A scan-only run without a token needs only `brokerFile`, `profileFile` and `"optOut": false`. A token-authenticated run
also needs the environment and endpoint fields, including when scan-only. An opt-out needs `emailConfirmation` explicitly
set to `true` or `false`.

Supply an existing subscription service access token with `--token-file /local/path/to/token` or
`--token-env ENVIRONMENT_VARIABLE_NAME`. The file contains only the token. Keep the token outside configuration and
evidence files, and do not ask the user to paste it into chat. Existing staging test credentials, including the token
used by `PRIVACYPRO_STAGING_ACCESS_TOKEN_V2`, can be supplied this way if still accepted by the backend. The issuer
controls token lifetime; the runner does not mint tokens, extend expiry or refresh them.

The runner supplies the credential only in the app or agent launch environment as `PIR_DEBUG_ACCESS_TOKEN`, using
`SIMCTL_CHILD_PIR_DEBUG_ACCESS_TOKEN` for the simulator. It never puts the token in process arguments or evidence.
The existing PIR subscription adapter captures this DEBUG override once and uses it for the native captcha and email
clients. It takes precedence over integration-test and saved-account tokens, without adopting or persisting it.
An invalid override fails closed. Without an override, normal subscription authentication applies. The configured PIR
environment applies only to this debug runner.
Token authentication requires matching subscription and PIR environments. Prerequisites report `credentialProvided`
on the first check, which establishes launch credential availability. Server acceptance and subscription entitlement
remain unverified. Backend authentication failures fail the flow. Reports identify token authentication and leave normal
sign-in unverified.

## 3. Build and run

From the worktree root:

```sh
P=.claude/skills/verify-pir/pir.py
python3 "$P" build --platform ios
python3 "$P" run --platform ios --config ~/pir-runs/example/config.json \
  --token-file /local/path/to/token --evidence-dir ~/pir-runs/evidence
```

Use `--platform macos` for the macOS PIR agent. Use `--device ipad` on the iOS build and run commands for an iPad run.
Run each platform separately; success on one does not establish success on the other. The broker workflow and checks
are shared, while native WebKit behavior and broker user agents can differ.

`build` records the app's source fingerprint and executable hash. `run` rejects a stale or changed build. Each run uses
an isolated debug launch and correlated server instance. iOS uses a dedicated simulator. macOS builds a private DEBUG
browser bundle and launches only its embedded PIR agent, without starting production scheduling or registering a login
item. Existing browser and agent processes stay running.
Before a macOS build, the runner enables debug deployment with `scripts/toggle-macos-debug-deployment.sh on`, then builds
the browser into a private deployment root under `DerivedData/verify-pir/macos/` and discovers its embedded PIR agent.
It preserves unrelated local overrides, leaves `/Applications/DEBUG` intact, and does not change a saved simulator
selection.

Add `--check-config` to a run command to validate inputs without building, launching or submitting requests. Run long
scans in the background and follow their printed history events. Tokens are excluded from saved HTTP responses and logs.
For each scenario run, the runner prints the live `snapshots/` directory before launch. macOS writes PNGs there directly.
iOS copies them from the simulator on each run-status poll and once more before cleanup. Filenames give the capture
sequence, scan or opt-out phase, action type and capture point (`before`, `result` or `error`). To inspect a running or stalled job, open the newest PNG
and read the action events in the latest `pir-http-*.json` next to it. Read earlier PNGs in sequence to see when
the page changed. These are action-boundary captures of the viewport. The page can change between captures.
A `.unavailable` marker records a capture that produced no image. Screenshots can show unredacted broker
records and form values. Keep them in the local attempt folder.

## 4. Use interactive subscription setup only when requested

For an iOS run that must use normal subscription authentication, replace the token option with
`--interactive-subscription`. After the scan, pass the printed checkpoint instruction to the user. They activate or
restore the test subscription in that same simulator, without resetting or relaunching. Acknowledge only after they
report it ready, using the printed acknowledge path. The cancel path or Ctrl-C ends the attempt inconclusive.
`checkpointTimeout` controls this wait and defaults to 900 seconds.

This mode checks normal authentication and entitlement after acknowledgement. An opt-out without a supplied token or
explicit interactive mode is rejected before launch. macOS unattended runs use supplied tokens; its agent has no
subscription sign-in UI.

## 5. Report the result

Report pass, fail or inconclusive, the printed `report.md` path, failed checks, cleanup problems and unverified items.
The attempt folder also contains machine-readable results, build and launch identity, input hashes, the exact broker
bytes, changed HTTP responses, final run state and application logs. It records a rerun command using credential
references rather than secret values. The report links the available web view snapshots in capture order and notes
collection errors. The manifest includes the PNGs and unavailable markers. Missing screenshots leave the broker
verdict intact.

No match remains inconclusive in either scenario. Site, rate-limit, captcha, authentication and email errors cannot
become a successful empty scan. An accepted HTTP request is not job completion; the runner polls the same run ID and
checks the selected result and history.

Cleanup stops the owned app or agent even with `--keep`. That option preserves the simulator for inspection. Cleanup
cannot undo a broker request already submitted. Do not run another debug client against an attempt in progress.

Tests without a simulator or live backend:

```sh
python3 -m unittest discover -s .claude/skills/verify-pir/tests -p 'test_*.py'
```

## 6. Verify persisted scans on macOS

Choose the scheduler command by what should happen to the DEBUG profile:

- `scheduler seed --profile-file <path>` saves a profile in an empty store and starts scans. An existing profile is a refusal.
- `scheduler reseed --profile-file <path>` replaces the DEBUG PIR profile and job history, then starts scans. Obtain explicit
  approval for that reset before invoking it.
- `scheduler observe` watches work triggered separately through the app. Supply the UTC cutoff recorded before the
  trigger and repeat `--job` with each exact broker URL and active profile query ID from the normal agent's `GET /api`.

```sh
python3 .claude/skills/verify-pir/pir.py scheduler seed --platform macos --profile-file ~/pir-runs/profile.json
python3 .claude/skills/verify-pir/pir.py scheduler observe --platform macos \
  --since 2026-11-20T15:00:00Z --job example.com 42 --timeout 600
```

Build the private macOS DEBUG browser first for seed or reseed. Close any running DEBUG browser and use a signed-out
DEBUG test account so the normal agent takes its Freemium scan path. The browser saves through the real PIR data manager
and starts its regular login item and debug server on port 8474. It reports the cutoff and eligible jobs automatically.
These commands make live broker scans. The tool stops the browser it launched. The saved test profile and registered
agent remain available after the attempt.

Observation makes only GET requests. Evidence contains the agent identity, persisted scan histories and
`scheduler.json`. A seeded attempt includes `scheduler-launch.json` with the native job plan. A pass requires a fresh
`scanStarted` and a matching terminal `matchesFound` or `noMatchFound` for every expected job. A fresh terminal error
fails. Missing, incomplete, or ambiguous evidence is inconclusive. For observe, choose a cutoff with room for the
server's second-resolution timestamps. Recurring scheduler ticks and opt-out jobs are separate checks.

## 7. Check the verifier without broker requests

After building, run a native startup check on each platform:

```sh
python3 .claude/skills/verify-pir/pir.py selftest --platform ios --evidence-dir ~/pir-runs/evidence
python3 .claude/skills/verify-pir/pir.py selftest --platform macos --evidence-dir ~/pir-runs/evidence
```

`selftest` uses the recorded build, forces staging with an internal dummy credential, checks correlated prerequisites,
collects the native logs array and redacted application logs, writes the usual report and manifest, and stops its owned
runtime. It only reads local HTTP endpoints. It rejects scenario, credential, interactive, check-config and keep options.
It does not establish real authentication, broker execution, captcha handling, email delivery or removal. Evidence and
cleanup failures make the attempt inconclusive. Rebuild first if the source fingerprint has changed.

The native contract test connects the real Python client to the real Swift HTTP server with stub run and log services.
It checks response shapes, HTTP statuses, instance ownership, web-origin rejection, request parsing and redaction without
executing broker jobs. Run it through the existing macOS package test scheme:

```sh
xcodebuild -workspace DuckDuckGo.xcworkspace -scheme DataBrokerProtectionCore -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData/verify-pir/core-tests \
  -only-testing:DataBrokerProtectionCoreTests/DebugHTTPPythonContractTests test
```
