# fakebroker.com

Local scenarios against the PIR fake broker. They send no requests to real brokers, but the opt-out's email field still
uses the PIR backend, so they need a saved subscription or a token.

## Assisted opt-out completes after the user's turn

- tags: assisted, optout, local
- platform: macOS
- setup: `example`, `fakebroker.com`, `fake-broker-john-doe`
- action: `run`, `"optOut": true`, `"emailConfirmation": false`, `"assist": {"hookUrl": "http://localhost:3001/api/test/assist"}`
- expect:
  - The opt-out hands off once at "Prove you're human", the hook returns HTTP 200, and the opt-out then resumes and
    ends in `confirmed`.

## Assisted opt-out without a hook fails at the hand-off

- tags: assisted, optout, local
- platform: macOS
- setup: `example`, `fakebroker.com`, `fake-broker-john-doe`
- action: `run`, `"optOut": true`, `"emailConfirmation": false`
- verdict: fail
- expect:
  - The opt-out fails with a user-assistance error before the human check, and the record is not removed.
