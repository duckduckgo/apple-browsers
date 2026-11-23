# Example scenarios

One example of each kind of scenario. Copy them into your own scenario file and replace the placeholders in angle
brackets. `example` is the profile in `fixtures/profiles/example.json`, a made-up person. Use a profile that matches
on your broker instead when a scenario needs a match.

## Scan finds the profile's record

Use for a broker JSON change, or to check a broker still works. Sends only the read-only requests a scan makes.

- tags: example, scan, live
- platform: iOS, macOS
- setup: `example`, `<broker URL>`
- action: `run`, `"optOut": false`
- expect:
  - The scan ends in `matchesFound`, and each matched `profileUrl` is recorded.
  - `noMatchFound` is inconclusive.

## Opt-out is submitted

Use to check a broker's opt-out flow. It sends a real removal request and can't be undone.

- tags: example, optout, live, irreversible
- platform: macOS, iOS
- setup: `example`, `<broker URL>`, `staging-token`, a matched `profileUrl` from the scan
- action: `run`, `"optOut": true`, `"emailConfirmation": <true if the broker's opt-out has an emailConfirmation step>`
- expect:
  - The opt-out is requested for the pinned record.
  - The last page is the broker's opt-out confirmation.
  - No action times out.

## A child broker is recognized as opting out through its parent

Use for a broker whose opt-out step is `parentSiteOptOut`. Shows the app classifies it as a child; production
scheduling isn't exercised.

- tags: example, optout, live
- platform: macOS, iOS
- setup: `example`, `<child broker URL>`, `staging-token`
- action: `run`, `"optOut": true`
- expect:
  - The selected record gets `optsOutInParent`, and the opt-out is reported as skipped and unverified.
  - No opt-out request is sent.

## A profile save starts the initial scans

Use for scheduler changes. Scans every eligible broker, so it takes several minutes.

- tags: example, scheduler, scan, live
- platform: iOS
- setup: `example`, `fresh-simulator`
- action: `scheduler seed`
- expect:
  - Every planned job gets a fresh `scanStarted` and reaches a terminal event.
  - No broker the app lists as removed in `GET /api` is planned.

## A broker JSON with an unsupported action is rejected

An example of a scenario that expects the run to fail. Copy a bundled broker JSON and add an action with a made-up
`actionType` to its opt-out step.

- tags: example, compatibility
- platform: macOS, iOS
- setup: `example`, `<the edited broker JSON>`
- action: `run`, `"optOut": false`
- verdict: fail
- expect:
  - The app rejects the file as an unsupported action before any broker request.
