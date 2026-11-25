# Example scenarios

Examples that anyone can run, for instance to try a pull request: `/ddg-check-pir Run the example scenarios as one batch.`
They send no opt-outs, only the read-only requests a scan makes. `example` is the profile in
`fixtures/profiles/example.json`, a made-up person.

## A scan finds the profile's record

- tags: example, scan, live
- platform: iOS, macOS
- setup: `example`, `peoplefinders.com`
- action: `run`, `"optOut": false`
- expect:
  - The scan ends in `matchesFound` on a normal results page, and each matched `profileUrl` is recorded.

## A profile save starts the initial scans

Scans every eligible broker, so it takes several minutes.

- tags: example, scheduler, scan, live
- platform: iOS
- setup: `example`, `fresh-simulator`
- action: `scheduler seed`
- expect:
  - Every planned job gets a fresh `scanStarted` and reaches a terminal event.
  - No broker the app lists as removed in `GET /api` is planned.

## A broker JSON with an unsupported action is rejected

Copy the bundled `peoplefinders.com` JSON into the batch folder and add an action with a made-up `actionType`, such as
`"notARealAction"`, to its scan step. Use that copy as the broker file.

- tags: example, compatibility
- platform: macOS, iOS
- setup: `example`, the edited broker JSON
- action: `run`, `"optOut": false`
- verdict: fail
- expect:
  - The app rejects the file as an unsupported action before any broker request.

## Templates for your own scenarios

These need a staging token and send real requests, so they aren't run as examples. Copy one into your own scenario
file, outside the commits, and fill in the placeholders.

```markdown
## Opt-out is submitted

- tags: optout, live, irreversible
- platform: macOS, iOS
- setup: <profile>, <broker URL>, `staging-token`, a matched `profileUrl` from the scan
- action: `run`, `"optOut": true`, `"emailConfirmation": <true if the opt-out has an emailConfirmation step>`
- expect:
  - The opt-out is requested for the pinned record.
  - The last page is the broker's opt-out confirmation.
  - No action times out.

## A child broker is recognized as opting out through its parent

- tags: optout, live
- platform: macOS, iOS
- setup: <profile>, <child broker URL>, `staging-token`
- action: `run`, `"optOut": true`
- expect:
  - The selected record gets `optsOutInParent`, and the opt-out is reported as skipped and unverified.
  - No opt-out request is sent.
```
