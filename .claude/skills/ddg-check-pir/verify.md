# Verify a verify-pir result

The runner's verdict comes from the app's own history events. This review checks that the evidence supports that verdict and, for a scenario run, each of the scenario's expectations.

Review every run.

## Hand-off

Start a subagent with fresh context. Give it:

- the attempt folder the runner printed
- the scenario's section and the profile fixture, if the run was for a scenario
- this file

Don't give it the verdict you expect or your reading of the run. It reads the evidence itself.

## What the reviewer reads

- `report.md` and `result.json`: the verdict, the checks and the reason.
- For `run`: `pir-final-run.json` (matched records, the selected record, history) and `pir-broker.json` (the broker JSON that ran).
- For `scheduler`: `scheduler.json` (jobs and terminal events), `scheduler-launch.json` (the plan), and the first `pir-http-*.json` with path `/api`. That file lists every broker the app loaded, with its version and `isRemoved`. The app refreshes broker JSON from the server, so judge versions and deprecation from this list, not the bundled JSON.
- `snapshots/`: the last `result` snapshot of each phase, and every `error` snapshot. The file names give the sequence, phase, action and capture point.
- `pir-native-logs.json`: every line has level `NOTICE`, so search the messages for `error`, `fail`, `timeout` and `exception` instead of filtering by level.

## Questions

1. Does the last page fit the verdict?
   - An opt-out marked confirmed should end on the broker's own confirmation page.
   - `matchesFound` should end on a results page that lists the matched records.
   - `noMatchFound` should end on a results page or an empty-results page.
   - A broker error should end on the page that caused it, such as a block page, a challenge or an HTTP error.

   A Cloudflare or CAPTCHA challenge, a blank page, or an error page behind a pass or a `noMatchFound` disputes the verdict. So does an `actionFailed` on a page that loaded normally. The runner passes `actionFailed` as a broker outcome, but on a normal page it usually means the broker JSON no longer fits the page, which is a regression when the run tests a broker JSON change.
2. Do the matched records fit the profile? Check the name, the city and state, and an age that fits the birth year. Compare the extracted fields in `pir-final-run.json` with what the last results page shows.

   Dispute the run, even when every scenario expectation is met, if any of these holds:
   - A matched or selected record doesn't fit the profile.
   - The extract is missing a field the page shows, such as an age, addresses or relatives. That means the broker JSON no longer fits the page and the app matched on fewer fields than it should.
3. Do the native logs show a failure the verdict doesn't account for?
4. For a scenario run, is each `expect` item met, not met, or not checkable from this evidence?
5. For a run that didn't pass, what caused it: our code, the broker (blocked, changed or down), or the setup (fixture, token, build)?

## Output

Write `verification.md` in the attempt folder. It starts with `confirmed` or `disputed`. `confirmed` means the evidence supports the verdict, every expectation is met, and none of the dispute conditions above applies. Then it answers each question in one or two lines, naming the evidence file behind each answer. Report the reviewer's result next to the runner's verdict. In a baseline, keep a `disputed` run with its finding: it records a failure the baseline build already has, so a later run that shows the same failure isn't a regression.

Snapshots and records show real people's data. Keep `verification.md` with the evidence, outside the checkout.

## Negative controls

Run these once for each new baseline build. They show the checks can fail.

- **Broken selector:** copy the broker JSON and change the scan's first `expectation` selector so it can't match. The runner passes the run, because it counts `actionFailed` as a broker outcome. The review must dispute it: the page loaded normally, so the broker didn't cause the failure.
- **No match:** use a profile fixture with no record on the broker. Expect `inconclusive`.
- **Bad token:** pass a token file containing a malformed token. Expect `fail` before any broker request.
