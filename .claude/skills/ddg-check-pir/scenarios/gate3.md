# Gate 3: internal dogfood

The assisted opt-out flow, run against the PIR fake broker through the debug server. These runs send no requests to real
brokers, but the opt-out's email field still uses the PIR backend, so they need a saved subscription or a token on the
same environment as `pirEnvironment`.

- `fakebroker.com` is version 0.0.1 of `docs/assisted-opt-out-broker.json` from
  [pir-fake-broker #32](https://github.com/duckduckgo/pir-fake-broker/pull/32). Its opt-out has one `userAssist` step,
  "Prove you're human".
- The `userAssist` step needs this branch's C-S-S pin (`ff7ceedd`, with
  [#3161](https://github.com/duckduckgo/content-scope-scripts/pull/3161)). C-S-S 21.4.0, which `main` pins, doesn't have the action.

## Assisted opt-out completes after the user's turn

- tags: gate3, assisted, optout, local
- platform: macOS
- setup: `example`, `fakebroker.com`, `fake-broker-john-doe`
- action: `run`, `"optOut": true`, `"emailConfirmation": false`, `"assist": {"hookUrl": "http://localhost:3001/api/test/assist"}`
- expect:
  - The opt-out hands off once at "Prove you're human", the hook returns HTTP 200, and the opt-out then resumes and
    ends in `confirmed`.

## Assisted opt-out without a hook fails at the hand-off

- tags: gate3, assisted, optout, local
- platform: macOS
- setup: `example`, `fakebroker.com`, `fake-broker-john-doe`
- action: `run`, `"optOut": true`, `"emailConfirmation": false`
- verdict: fail
- expect:
  - The opt-out fails with a user-assistance error before the human check, and the record is not removed.
