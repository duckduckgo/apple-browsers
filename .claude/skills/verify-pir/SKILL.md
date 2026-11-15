---
name: verify-pir
description: Run a live Personal Information Removal broker scan and opt-out on the iOS app through its debug server, built on verify-ios. Invoke explicitly; it submits real broker requests and needs a person to set up the subscription.
disable-model-invocation: true
---

# verify-pir

Checks that the scan and opt-out flows work correctly against a live broker. It scans one exact broker with a test
profile, uniquely matches an expected record, and completes the opt-out for that record. The scheduler is deliberately
out of scope. The proof starts each job through the PIR debug server (`POST /api/debug/...`), which runs scans and
opt-outs independently of the scheduler, so a failure points at the broker flow itself, not at when or whether the
scheduler picked the job up. That is why it lives apart
from verify-ios proofs, which act like a user. It does not verify the PIR dashboard, profile editor, production
scheduler or their entry points; report those as unverified when relevant.

A confirmed opt-out proves the submission and confirmation flow only. Removal needs a later scan.

## Run it

Preconditions: a Debug app from this worktree, an explicitly authorized test profile and broker, a known expected
record, and access to a real test subscription. Keep credentials out of input files and evidence.

Create a local configuration outside the checkout. Supply the complete broker JSON, the profile JSON accepted by
`-pirProfileJSON`, and an expected-result JSON object. Paths are relative to the configuration file. Expected identity
uses exact API fields: `profileUrl`, or both `name` and `addresses`; optional `age` and `profileQuery` narrow the
match. The identity and its returned ID must each be unique in the run.

```json
{
  "brokerFile": "broker.json",
  "profileFile": "profile.json",
  "expectedFile": "expected.json",
  "emailConfirmation": true,
  "subscriptionEnvironment": "staging",
  "pirEnvironment": "staging",
  "pirEndpoint": "https://dbp-staging.duckduckgo.com",
  "checkpointTimeout": 900,
  "activityTimeout": 600,
  "emailTimeout": 300
}
```

```sh
export PIR_PROOF_INPUT=/absolute/path/to/config.json
V=.claude/skills/verify-ios/bin/verify-ios
$V check .claude/skills/verify-pir/pir.py
$V prove .claude/skills/verify-pir/pir.py --devices iphone
```

The proof declares its `LIVE` services and pins `dbpCustomWebViewUserAgent` and `dbpExtractedProfileRefresh` on in
`FLAGS`. Those are proof choices, not assertions about the remote configuration. `validate()` reads and hashes the
inputs once, before any device work, and the run uses that snapshot.

The proof resets the app, then pauses. In that same simulator, activate or restore the subscription through the normal
UI. No launch argument or fixture can grant a real PIR entitlement, so this step needs a person. Touch the
attempt-specific acknowledgement file the runner prints, or its cancel file to abort (inconclusive). `checkpoint.json`
records paths, deadline, acknowledgement and outcome, and the manifest and report mark the run human-assisted. Ctrl-C
also cancels. The proof holds the simulator lock throughout the bounded wait and never resets after acknowledgement.

A new correlated prerequisite check must report authentication, real entitlement, expected environments and endpoint,
and debug-runner readiness, or the proof stops before submission. It then scans, uniquely selects the expected record,
submits only that returned result ID, polls the run, and checks status and history events. With
`emailConfirmation: true`, it requires the waiting state, polls email checks until `hasEmailConfirmationLink`, and only
then continues that result.

Evidence includes exact broker bytes and their hash/version, profile and expected-identity references/hashes,
configuration hash, launch/build and backend identity, prerequisite snapshots, HTTP responses and run events,
application logs, and the runner verdict.

Tests, no simulator: `python3 -m unittest discover -s .claude/skills/verify-pir/tests -p 'test_*.py'`.

## Gotchas

- This submits real broker requests. Use only the broker, profile, and expected record authorized for this attempt.
- No match leaves the opt-out contract unverified and the attempt inconclusive. Site, authentication, rate-limit,
  email, and opt-out errors cannot turn into a no-match pass.
- Debug jobs are synthetic and in memory. `/api/debug/runs/{id}` is the oracle. `/api/events` reads persisted job
  history and does not prove this run. Ordinary debug-runner pixels are suppressed.
- Main-browser host observation does not cover PIR worker or backend traffic; the report lists it as unverified.
- The prerequisite token read uses the normal `.localValid` subscription policy and preserves errors instead of using
  the feature check's cached-entitlement fallback. It does not prove a new server-side subscription refresh.
- The debug server listens on this worktree's reserved PIR port. Mutations with a different `X-PIR-Debug-Instance` are
  refused. Do not run another debug client against an owned attempt.
- Cleanup stops the test app when the proof ends, including with `--keep`, which stops scans or opt-outs still
  running. It cannot undo a request already submitted to a broker.
