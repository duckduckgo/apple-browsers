# Fake assisted broker (test-only)

A local stand-in for a broker whose opt-out needs the user, for trying PIR user assistance end to end.
It mirrors BeenVerified's three hand-offs: a fake Turnstile ("Verify you are human" fills the hidden
`cf-turnstile-response` value), a fake hCaptcha ("I am human" sets `data-hcaptcha-response` on the widget's iframe),
and the final "Remove my Info" submit, which lands on a page with a `comprehensive-confirm-title` heading.
The scan returns a canned match for whoever is searched.

Nothing here ships: these files sit outside the package's sources, and the broker JSON
(`SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/UserAssistanceTesting/fakeassistedbroker.com.json`)
is only ever loaded by the debug menu's "Install Test Brokers".

## Run it

1. `./serve.sh` (serves this folder on http://localhost:3001; pass another port as the first argument if you also change the JSON).
2. In a debug build: Debug → Personal Information Removal → User Assistance → "Enable for beenverified.com, fakeassistedbroker.com",
   then "Install Test Brokers (BeenVerified, Fake Assisted Broker)".
3. Debug → Personal Information Removal → Operations → Hidden WebView → Run scan operations, so the fake broker finds a match.
4. Within 30 seconds the agent lists the opt-out under Needs you in the dashboard. Start it there.
