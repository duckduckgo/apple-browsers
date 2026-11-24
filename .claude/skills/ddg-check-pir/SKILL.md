---
name: ddg-check-pir
description: Run a live PIR broker scan and optional opt-out through the debug API on iOS or macOS, a native selftest, or a persisted scheduler check. Accepts a supplied access token for captcha and email flows. Invoke explicitly because it sends real broker requests.
disable-model-invocation: true
---

# ddg-check-pir

Runs one broker against a test profile on iOS or macOS. The Python runner starts jobs through the PIR debug API, checks
results and history, saves evidence and stops the app or agent it launched. It needs Python 3 and Xcode's command line
tools.

`run` exercises the broker flow through the shared native `DebugModeRunner`, not the dashboard, profile editor,
subscription sign-in or production scheduler. A confirmed opt-out means submission and confirmation completed; removal
needs a later scan.

Order: choose the scenario, prepare inputs, build, run `selftest` and `--check-config` (no broker requests), run
scan-only, then the opt-out once the user authorizes it.

## 1. Choose the scenario

- **Scan only**, `"optOut": false`: passes when the app matches at least one record. No match is inconclusive. Supply a
  token if the scan needs the captcha service and the app has no saved subscription.
- **Scan and opt-out**, `"optOut": true`: scans, selects one matched record, submits its opt-out and, when configured,
  completes email confirmation. Needs a saved subscription with PIR entitlement or a supplied token.

An opt-out sends real broker requests and cannot be undone. Run scan-only first, then get the user's authorization for
the broker, profile, selected record and scenario. With several matches, `expectedFile` must name the exact
`profileUrl`. The app does the matching; the runner has no matcher of its own.

A child broker (opt-out step `parentSiteOptOut`) opts out through its `parent`. The app skips its opt-out as production
does, so the run reports the scan verdict and leaves the opt-out unverified. Test removal against the parent broker.

## 2. Prepare inputs and credentials

Keep the configuration, broker JSON and profile JSON in a folder outside the checkout, such as `~/pir-runs/example/`.
Configuration paths are relative to the configuration file. Unless the user supplies a broker JSON, copy the bundled one
from `SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/` (for example
`peoplefinders.com.json`). The profile uses the `-pirProfileJSON` shape. The optional `expectedFile` holds only
`{"profileUrl": "..."}`; on scan-only runs it checks that record was found.

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

A scan-only run without a token needs only `brokerFile`, `profileFile` and `"optOut": false`. An opt-out or a supplied
token also needs the environment and endpoint fields, and a supplied token requires matching `subscriptionEnvironment`
and `pirEnvironment`. An opt-out sets `emailConfirmation` explicitly.

Without a token, the native prerequisite check confirms the saved subscription is signed in, entitled and on the
configured environment before any broker request. The macOS agent can use its saved subscription; iOS uses a fresh
simulator, so an iOS opt-out needs a token.

Supply the token with `--token-file <path>` (a file containing only the token) or `--token-env <NAME>`. Never ask the user
to paste it, and keep it out of configuration files; the runner rejects inputs that contain it. The runner passes it only
through the launch environment, never in arguments, logs or evidence. It replaces saved-account authentication for that
launch; a malformed token or authentication failure fails the run, and the report leaves normal sign-in unverified.

## 3. Build and check

From the worktree root:

```sh
P=.claude/skills/ddg-check-pir/pir.py
python3 "$P" build --platform ios
python3 "$P" selftest --platform ios --evidence-dir ~/pir-runs/evidence
python3 "$P" run --platform ios --config ~/pir-runs/example/config.json \
  --token-file /local/path/to/token --check-config
```

Use `--platform macos` for the macOS PIR agent and `--device ipad` on iOS build and run commands for an iPad.

`build` records the source fingerprint and executable hash; later commands reject a stale build, so rebuild after source
changes. On macOS it turns on debug deployment (`scripts/toggle-macos-debug-deployment.sh on`, preserving other local
overrides), builds a private DEBUG browser under `DerivedData/ddg-check-pir/macos/` and finds its embedded PIR agent. It
leaves `/Applications/DEBUG` alone and refuses while the private browser or agent runs; its error names the command to
stop an agent a scheduler seed left registered.

`selftest` launches the recorded build in staging with a dummy credential, checks the prerequisites and native logs,
writes the usual report and stops the runtime. It only reads local endpoints, takes no scenario, credential,
check-config or keep options, and proves nothing about authentication, brokers, captcha, email or removal. Evidence or
cleanup failures make it inconclusive.

`--check-config` validates the configuration, inputs and token source without building, launching or sending requests.

## 4. Run

```sh
python3 "$P" run --platform ios --config ~/pir-runs/example/config.json \
  --token-file /local/path/to/token --evidence-dir ~/pir-runs/evidence
```

`--evidence-dir` defaults to `~/pir-evidence`, must be outside the checkout, and gets a new child folder per attempt.
Run long scans in the background and follow the printed history events.

Run each platform separately: WebKit and broker user agents differ, so a pass on one proves nothing for the other. Each
run gets an isolated debug launch and server instance. iOS uses a dedicated simulator. macOS launches only the private
bundle's embedded agent, without production scheduling or a login item, and leaves existing browser and agent processes
running. Don't point another debug client at an attempt in progress.

Cleanup stops the owned app or agent even with `--keep`, which only keeps the simulator. It cannot undo a broker request.

To inspect a running or stalled job, open the `snapshots/` folder the runner prints before launch (macOS writes PNGs
directly; iOS copies them on each poll and before cleanup). Filenames give sequence, phase, action and capture point
(`before`, `result`, `error`); a `.unavailable` marker means no image. Read the newest PNG with the latest
`pir-http-*.json`, then earlier ones. Screenshots can show unredacted records and form values; keep them local.

## 5. Report the result

Report pass, fail or inconclusive, the printed `report.md` path, failed checks, cleanup problems and unverified items.
The attempt folder also holds machine-readable results, build and launch identity, input hashes, the exact broker bytes,
changed HTTP responses, the final run state, native PIR logs (`pir-native-logs.json`), linked snapshots and a rerun
command with credential references. Missing screenshots don't change the verdict.

No match is inconclusive, and an error never counts as an empty scan. A broker breaking (`httpError`, such as a 410 or
429, or `actionFailed`) is a legitimate terminal outcome: the run passes and names it. Any other error, including
captcha, email, authentication and `jobTimeout`, and any activity timeout, is our failure and fails the run. An accepted
HTTP request is not completion; the runner polls the run ID and checks the selected result and history.

Then have a fresh subagent review the evidence of every run as `.claude/skills/ddg-check-pir/review.md` describes, and
report its `confirmed` or `disputed` next to the verdict. To run a batch of scenarios, follow
`.claude/skills/ddg-check-pir/scenarios/README.md`.

## 6. Check persisted scans

Choose by what should happen to the DEBUG profile:

- `scheduler seed --profile-file <path>` saves a profile into an empty store and starts scans; an existing profile is a
  refusal.
- `scheduler reseed --profile-file <path>` replaces the DEBUG PIR profile and job history, then starts scans. Get
  explicit approval for the reset first.
- `scheduler observe` watches scans triggered separately in the app, on macOS or an iOS simulator.

`--broker <url>`, repeated, limits a seed or reseed to those brokers, still subject to the app's own eligibility. A
listed broker with no eligible scan fails the seed, and `scheduler-launch.json` says why. On macOS the subset persists
until a seed without `--broker`.

`scheduler upgrade` runs a later build on a store an earlier build seeded (on iOS, seed with `--keep` and pass that
seed's `--simulator <udid>`). It re-reads the broker JSON at once (`--reset-delivery` also re-downloads remote brokers),
then scans the `--broker` brokers and observes them. `upgrade-refresh.json` lists the stored brokers after the refresh,
and `upgrade-scans.json` the queued jobs.

For a scenario that takes several commands, pass `--step <name>` with `--scenario` on each. The report counts each
step's latest attempt as a run of its own.

These make live broker scans. On macOS, close any DEBUG browser. A seed signs the DEBUG account out first, so the agent
takes the Freemium path and plans scans only; sign in again afterwards if you need the subscription. The private browser saves through the real PIR data manager, starts its login item and debug server on
port 8474, and the tool reports the cutoff and planned jobs, stops the browser and leaves the profile and registered agent
in place. macOS seeds run one at a time.

On iOS, each attempt creates a fresh simulator, launches the recorded build signed out with the profile in its launch
environment, and picks a free port. The app refreshes broker JSON, saves the profile, records the plan and starts the
same initial scans as a profile saved in the app. The tool reads the receipt from the app's container, then stops the
app and deletes the simulator unless `--keep`. Attempts share nothing, so iOS seeds can run in parallel.

For observe, use an app with a saved profile and its debug server on (on iOS, **Debug Server** in the PIR debug menu).
Record a UTC cutoff before triggering the scan, allowing for second-resolution timestamps, and pass `--job` for each
exact broker URL and active profile query ID from `GET /api`. Observe only makes GET requests. Add `--platform ios` for a
simulator and `--port` if the listener isn't on 8474.

```sh
python3 "$P" scheduler seed --platform macos --profile-file ~/pir-runs/profile.json
python3 "$P" scheduler seed --platform ios --profile-file ~/pir-runs/profile.json
python3 "$P" scheduler observe --platform macos \
  --since 2026-11-20T15:00:00Z --job example.com 42 --timeout 600
```

Evidence holds the listener identity, persisted histories and `scheduler.json`, plus `scheduler-launch.json` with the
native plan for a seed. A pass needs, for every expected job, a fresh `scanStarted` and a terminal `matchesFound`,
`noMatchFound` or broker `error` (`httpError`, `actionFailed`); broker errors are listed. A broker removed by a broker
update during the run is reported as `removed` and not awaited; if all are removed the run is inconclusive. A scan cut
off by its job timeout (`Cancelled`, `jobTimeout`) or by a dropped connection is reported as `transient`; the run waits
for every job, then is inconclusive and names those brokers to rerun. Any other terminal error fails, after every job has
finished, and so does a timeout with jobs missing, incomplete or ambiguous. Listener or HTTP setup problems are
inconclusive. Recurring scheduler ticks and opt-outs are separate checks.

## 7. Test the checker

Unit tests, without a simulator or backend:

```sh
python3 -m unittest discover -s .claude/skills/ddg-check-pir/tests -p 'test_*.py'
```

The native contract test runs the real Python client against the real Swift HTTP server with stub services:

```sh
xcodebuild -workspace DuckDuckGo.xcworkspace -scheme DataBrokerProtectionCore -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData/ddg-check-pir/core-tests \
  -only-testing:DataBrokerProtectionCoreTests/DebugHTTPPythonContractTests test
```
