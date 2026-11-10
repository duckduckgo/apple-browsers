# Fake BeenVerified (test-only)

A local copy of BeenVerified's opt-out flow, so the real BeenVerified broker JSON (with its `userAssist`
steps) can run against it without Cloudflare, real captchas or real records. Nothing here ships.

- `server.py` serves the pages on the same paths, with the same selectors, as www.beenverified.com:
  the opt-out search form with a Turnstile, the comprehensive form that highly populated states get, the
  results cards, the review page with an hCaptcha, the certify checkbox and "Remove my Info", and the
  "Your optout request was submitted." page. The Cloudflare interstitial, Turnstile and hCaptcha are
  fakes that either pass by themselves (`auto`) or wait for a click (`manual`).
- `beenverified.com.json` (not committed, see `.gitignore`) is the BeenVerified broker JSON with `userAssist`
  steps. Save a copy here, or pass `drive.py --source`.
- `drive.py` is the harness. Through the PIR debug server it installs a copy of that JSON pointing at
  the fake (broker url `fakebroker.com`, written next to it as `fakebroker.com.json`), scans,
  starts the assisted opt-out and follows it to Submitted, optionally doing the user's part itself.

## One-time setup

1. A debug build of this branch. It adds the debug-server control routes (`/api/brokers`,
   `/api/assisted-optouts`, `/api/webviews`).
2. Debug → Feature Flags → `dbpUserAssistance` on.
3. Debug → Personal Information Removal → User Assistance → Override Enabled Brokers… →
   `beenverified.com, fakebroker.com`.
4. A subscribed user with a saved profile.

## Run it

```bash
./server.py                       # http://localhost:3002, leave it running
open "/Applications/DuckDuckGo PIR Debug.app" --args -pirDebugServer true
./drive.py --solve --shots shots  # unattended: every hand-off is solved by the harness
./drive.py                        # you complete the hand-offs in the agent's window
```

`./drive.py --no-scan` reuses the last scan's matches; `--id brokerId-profileQueryId-extractedProfileId`
picks the opt-out when there's more than one. The opt-out ends Submitted with
`optOutSubmittedAndAwaitingEmailConfirmation`, like the real one: the fake can't send the confirmation
email.

The broker url has to be one the DDG email service accepts, since both the scan's comprehensive form and
the opt-out generate an email. It rejects made-up urls (`INVALID_REQUEST: Invalid dataBroker parameter`)
but accepts `fakebroker.com`, the bundled test broker's url. The fake gets its own name, so it doesn't
clash with that broker's row unless "Install Test Brokers" or similar has already added one with that url,
in which case installing replaces it. `--broker-url` picks another.

## Shaping the run

Flags on `server.py`, or change them while it runs with
`curl -X POST localhost:3002/__fake/config -d '{"turnstile":"manual"}'`:

| Setting | Default | Effect |
|---|---|---|
| `--cloudflare` / `cloudflare` | `off` | `auto` or `manual` interstitial on the opt-out page (the "Opening BeenVerified" hand-off) |
| `--turnstile` / `turnstile` | `auto` | `manual` makes the "Searching for your record" hand-off fire after its 10 s grace period |
| `--hcaptcha` / `hcaptcha` | `manual` | `auto` skips the "Checking you're human" hand-off |
| `--delay-ms` / `challengeDelayMs` | `1500` | How long `auto` challenges take |
| `--comprehensive-states` / `comprehensiveStates` | `CA,NY,TX,FL` | States that get the comprehensive form; `*` for all |
| `--results` / `results` | `match` | `none` serves the no-results page |
| `--decoys` / `decoys` | `4` | Same-name cards with other ages and cities around the match |
| `--same-record` / `freshRecords` | fresh | By default the matching card gets a random relative on each search, so every scan creates a new opt-out to run. `--same-record` keeps it stable |
| `--age`, `--city` / `age`, `city` | unset | The matching record's age and city for states without the comprehensive form |

The matching card needs your profile's age and city, which the search form doesn't send. The comprehensive
form does, and the server remembers them per name in `.fake-beenverified-state.json`, so either keep your
profile's state in `comprehensiveStates` or pass `--age` and `--city`. If the scan finds nothing, the
server log says so.

Scans don't hand off, so keep `cloudflare` and `turnstile` passable (`off` or `auto`) while scanning and
switch them to `manual` before starting the opt-out.

`GET /__fake/submissions` lists the records submitted with "Remove my Info"; `POST /__fake/reset` clears them
and the remembered people.
