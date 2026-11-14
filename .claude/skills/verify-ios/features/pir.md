# Personal Information Removal

Run a live broker scan and complete the opt-out for the selected record, with a pause for manual subscription setup.

## Sub-features

- PIR.1: live debug scan, unique expected-record assertion, and completed opt-out for that result.
- Subscription setup: activate or restore through the app's normal subscription UI, then verify authentication and a real PIR entitlement.
- Removal verification requires a later scan. A confirmed opt-out proves the submission flow only.

## How to get to it (user POV)

Open Settings, then Subscription to activate or restore the test subscription. PIR.1 exercises the debug runner directly, so it does not verify the PIR dashboard, profile editor, production scheduler, or their entry points. Report those paths as unverified when relevant.

## Driving it with verify-ios

Preconditions: a Debug app from this worktree, an explicitly authorized test profile and broker, a known expected record, and access to a real test subscription. Keep credentials out of input files and evidence. Run `examples/live/pir.py` explicitly; ordinary `examples/*.py` runs do not include it.

Create a local configuration outside the checkout. Supply the complete broker JSON, the profile JSON accepted by `-pirProfileJSON`, and an expected-result JSON object. Paths are relative to the configuration file. Expected identity uses exact API fields: `profileUrl`, or both `name` and `addresses`; optional `age` and `profileQuery` narrow the match. The identity and its returned ID must each be unique in the run.

```json
{
  "brokerFile": "broker.json",
  "profileFile": "profile.json",
  "expectedFile": "expected.json",
  "emailConfirmation": true,
  "subscriptionEnvironment": "staging",
  "pirEnvironment": "staging",
  "pirEndpoint": "https://dbp-staging.duckduckgo.com",
  "live": ["chosen broker and confirmation hosts", "subscription service", "PIR email and captcha services", "privacy configuration service"],
  "flags": {"dbpCustomWebViewUserAgent": false, "dbpExtractedProfileRefresh": false},
  "checkpointTimeout": 900,
  "activityTimeout": 600,
  "emailTimeout": 300
}
```

Replace the LIVE descriptions with the actual services and hosts used by the chosen broker and app configuration. The two flag values are explicit proof choices, not assertions about the remote configuration. The iOS challenge solver is disabled by the app; this proof does not change that behavior. Other worker behavior can still depend on privacy configuration, so declare that service too.

Use the runner's usual per-worktree iPhone simulator:

```sh
export PIR_PROOF_INPUT=/absolute/path/to/config.json
V=.claude/skills/verify-ios/bin/verify-ios
$V check .claude/skills/verify-ios/examples/live/pir.py
$V prove .claude/skills/verify-ios/examples/live/pir.py --devices iphone
```

Build with the established runner first when its source fingerprint is stale. The runner uses the portable Xcode and simctl backend.

The proof performs its final reset before pausing. In that same simulator, activate or restore the subscription through the normal UI. Touch the attempt-specific acknowledgement file printed by the runner, or its cancel file to abort. `checkpoint.json` records paths, deadline, acknowledgement, and outcome. Ctrl-C also cancels. The proof holds the simulator lock throughout the bounded wait and never resets after acknowledgement.

A new correlated prerequisite check must report authentication, real entitlement, expected environments and endpoint, and debug-runner readiness. A bypass, failed check, or missing entitlement stops the proof before submission. The proof then scans, uniquely selects the expected record, submits only that returned result ID, polls the run, and checks status and history events. With `emailConfirmation: true`, it requires the waiting state, polls email checks until `hasEmailConfirmationLink`, and only then continues that result.

Evidence includes exact broker bytes and their hash/version, profile and expected-identity references/hashes, configuration hash, launch/build and backend identity, prerequisite snapshots, HTTP responses and run events, application logs, and the runner verdict.

## Gotchas

- This submits real broker requests. Use only the broker, profile, and expected record authorized for this attempt.
- No match leaves the opt-out contract unverified and the attempt inconclusive. Site, authentication, rate-limit, email, and opt-out errors cannot turn into a no-match pass.
- Debug jobs are synthetic and in memory. `/api/debug/runs/{id}` is the oracle. `/api/events` reads persisted job history and does not prove this run. Ordinary debug-runner pixels are suppressed.
- Main-browser host observation does not cover PIR workers or backend traffic. LIVE is a dependency declaration, not complete observed host coverage.
- The prerequisite token read uses the normal `.localValid` subscription policy and preserves errors instead of using the feature check's cached-entitlement fallback. It does not prove a new server-side subscription refresh.
- Port and instance ID belong to the launch. Mutations with a different `X-PIR-Debug-Instance` are refused. Do not run another debug client against an owned attempt.
- This proof uses the existing `on_cleanup` hook to stop the test app when it ends, including with `--keep`. This stops scans or opt-outs that are still running. It cannot undo a request already submitted to a broker. Cleanup or log failures are evidence problems.
- The runner owns its dedicated simulator for the whole attempt. Subscription setup uses that same simulator; it does not require an existing user simulator. Ordinary cleanup deletes the simulator unless `--keep` is selected.
