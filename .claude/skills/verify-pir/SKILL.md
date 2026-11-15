---
name: verify-pir
description: Run a live Personal Information Removal broker scan, and optionally the opt-out, on the iOS app through its debug server, built on verify-ios. Invoke explicitly; it submits real broker requests, and an opt-out needs a person to set up the subscription.
disable-model-invocation: true
---

# verify-pir

Checks that the scan and opt-out flows work correctly against a live broker. The proof scans one exact broker with a
test profile, uniquely matches an expected record, and, unless the run is scan-only, completes the opt-out for that
record. It starts each job through the PIR debug server (`POST /api/debug/...`), which runs scans and opt-outs
independently of the scheduler, so a failure points at the broker flow itself, not at when or whether the scheduler
picked the job up. That is why it lives apart from verify-ios proofs, which act like a user. It does not verify the PIR
dashboard, profile editor, production scheduler or their entry points; report those as unverified when relevant.

A confirmed opt-out proves the submission and confirmation flow only. Removal needs a later scan.

## 1. Choose the scenario

- **Scan only** (`"optOut": false`): scan and uniquely match the expected record, then pass with the opt-out reported
  as unverified. Scans need no subscription, so nobody has to step in. A broker that shows a captcha during the scan
  may still need one, because solving it goes through the backend.
- **Scan and opt-out** (`"optOut": true`): scan and match, pause for a person to set up the subscription, then opt out.

An opt-out sends real requests to a broker and cannot be undone. Before running one, confirm the broker, profile,
expected record and scenario with the user, and use only ones they authorized for this attempt.

## 2. Prepare

Get a current Debug app and runner with verify-ios: `.claude/skills/verify-ios/bin/verify-ios build` (or
`build --app-only` after app changes). `prove` refuses a stale build.

Write a configuration outside the checkout, one file per scenario. Paths in it are relative to the file. Supply the
complete broker JSON, the profile JSON accepted by `-pirProfileJSON`, and an expected-result JSON object. Expected
identity uses exact API fields: `profileUrl`, or both `name` and `addresses`; optional `age` and `profileQuery` narrow
the match. The identity and its returned ID must each be unique in the run. Keep credentials out of these files.

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
  "checkpointTimeout": 900,
  "activityTimeout": 600,
  "emailTimeout": 300
}
```

A scan-only configuration needs only the three files and `"optOut": false`; the other fields apply to the opt-out.

## 3. Run

```sh
export PIR_PROOF_INPUT=/absolute/path/to/config.json
V=.claude/skills/verify-ios/bin/verify-ios
$V check .claude/skills/verify-pir/pir.py
$V prove .claude/skills/verify-pir/pir.py --devices iphone --no-video
```

Run `prove` in the background and follow its output: a scan and opt-out can take many minutes, and the subscription
pause alone can last up to `checkpointTimeout` seconds, longer than a foreground command may run. It prints each PIR
history event as it happens. Keep `--no-video` unless the user asks for a recording, because the subscription step can
show account details.

## 4. Hand the subscription step to the user (opt-out only)

After the scan, the proof prints an instruction with an acknowledge path and a cancel path. Pass the instruction to the
user: in the simulator the proof opened, activate or restore the test subscription through Settings, without
resetting or relaunching the app. When they say it is active, `touch` the acknowledge path; if they want to stop,
`touch` the cancel path (the run ends inconclusive). Ctrl-C also cancels. No launch argument or fixture can grant a
real PIR entitlement, which is why this step needs a person.

The proof then checks that the subscription is authenticated and entitled, and that the environments and endpoint match
the configuration. Only then does it submit the matched result ID, poll the run, and check status and history events.
With `emailConfirmation: true`, it waits for the confirmation link before continuing that result.

## 5. Report

Tell the user the verdict (pass, fail or inconclusive), the `report.md` path `prove` prints, any failed checks, the
Unverified items, and whether the run was human-assisted. Evidence next to the report includes the exact broker bytes,
input hashes, prerequisite snapshots, every debug-server HTTP response, and the app logs.

Tests, no simulator: `python3 -m unittest discover -s .claude/skills/verify-pir/tests -p 'test_*.py'`.

## Gotchas

- No match is inconclusive in both scenarios. Site, authentication, rate-limit, email and opt-out errors cannot turn
  into a no-match pass.
- Host observation covers browser traffic only, so PIR worker and backend traffic is listed as unverified.
- The debug server listens on this worktree's debug server port and refuses mutations with another launch's
  `X-PIR-Debug-Instance`. Do not run another debug client against a run in progress.
- Cleanup stops the test app when the proof ends, including with `--keep`, which stops scans or opt-outs still
  running. It cannot undo a request already submitted to a broker.
