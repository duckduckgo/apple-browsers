# Fake assisted broker (test-only)

A local stand-in for a broker whose opt-out needs the user, for trying PIR user assistance end to end.
It mirrors BeenVerified's three hand-offs: a fake Turnstile ("Verify you are human" fills the hidden
`cf-turnstile-response` value), a fake hCaptcha ("I am human" sets `data-hcaptcha-response` on the widget's iframe),
and the final "Remove my Info" submit, which lands on a page with a `comprehensive-confirm-title` heading.
The scan returns a canned match for whoever is searched.

Nothing here ships: these files sit outside the package's sources, and `fakeassistedbroker.com.json` is only
loaded by the end-to-end test.

## Run it

1. `./serve.sh` (serves this folder on http://localhost:3001; pass another port as the first argument if you also change the JSON).
2. In a debug build: Debug → Personal Information Removal → User Assistance → "Enable for beenverified.com, fakeassistedbroker.com",
   then "Install Test Brokers (BeenVerified, Fake Assisted Broker)".
3. Debug → Personal Information Removal → Operations → Hidden WebView → Run scan operations, so the fake broker finds a match.
4. Within 30 seconds the agent lists the opt-out under Needs you in the dashboard. Start it there.

## Headless end-to-end test

`Tests/DataBrokerProtection-macOSTests/AssistedOptOutEndToEndTests.swift` uses the agent's real attempt window.
From this package run `PIR_FAKE_ASSISTED_BROKER_E2E=1 swift test --filter AssistedOptOutEndToEndTests`. Add
`PIR_FAKE_ASSISTED_BROKER_SHOTS=<folder>` to save PNGs of the attempt window at each stage. The debug menu steps above
are out of date: enabled brokers now come from config or the debug override, behind the `dbpUserAssistance` flag.
