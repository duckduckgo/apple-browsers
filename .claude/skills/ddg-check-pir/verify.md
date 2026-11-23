# Verify a verify-pir result

The runner's verdict comes from the app's own history events. This review checks that the evidence supports that
verdict and, for a scenario run, each of the scenario's expectations. Review every run.

## Hand-off

Start a subagent with fresh context. Give it:

- the attempt folder the runner printed
- the scenario's section and the profile fixture, if the run was for a scenario, including its expected verdict
- this file

Don't give it your own reading of the run or the verdict you predict.

## What the reviewer reads

- `report.md` and `result.json`: the verdict, the checks and the reason.
- For `run`: `pir-final-run.json` (matched records, the selected record, history) and `pir-broker.json` (the broker JSON
  that ran).
- For `scheduler`: `scheduler.json` (jobs and terminal events), `scheduler-launch.json` (the plan), and the first
  `pir-http-*.json` with path `/api`, which lists every broker the app loaded with its version and `isRemoved`.
- `snapshots/`: the last `result` snapshot of each phase, and every `error` snapshot. The file names give the sequence,
  phase, action and capture point.
- `pir-native-logs.json`: every line has level `NOTICE`, so search the messages for `error`, `fail`, `timeout` and
  `exception` instead of filtering by level.

Don't re-judge the app's own decisions, such as which records match, which jobs get planned or which brokers are
eligible. Check what the evidence shows. Differences between builds show up when a batch is compared with a baseline.

## Questions

1. Is each of the scenario's `expect` items met, not met, or not checkable from this evidence?
2. Does the run end with the scenario's expected verdict, for the reason the scenario describes? A failure for an
   unrelated reason, such as a launch error, doesn't count.
3. Does the evidence show something the verdict hides?
   - An opt-out marked confirmed should end on the broker's own confirmation page.
   - `matchesFound` should end on a results page, and `noMatchFound` on a results or empty-results page.
   - A Cloudflare or CAPTCHA challenge, a blank page, or an error page behind a pass or a `noMatchFound` hides a
     failure. So does an `actionFailed` on a page that loaded normally: the runner passes it as a broker outcome, but it
     usually means the broker JSON no longer fits the page.
   - A failure in the native logs that the verdict doesn't account for.

## Output

Write `verification.md` in the attempt folder. Its first line is `confirmed` when the answers to all three questions
support the run, and `disputed` when any of them doesn't. Then answer each question in one or two lines, naming the
evidence file behind each answer.

List problems outside what the scenario checks under a `## Findings` heading, one bullet each, naming the evidence
file. A finding is something someone may need to fix or follow up, such as an extract that misses a field the page shows
on every card. Observations that something went as expected, or details that didn't affect the run, aren't findings.
Leave them out or put them in the answers. Findings don't change the first line.

Report the reviewer's result next to the runner's verdict. In a baseline, keep a `disputed` run with its finding: it
records a failure the baseline build already has, so a later run that shows the same failure isn't a regression.

Snapshots and records show real people's data. Keep `verification.md` with the evidence, outside the checkout.

## Negative controls

Run these once for each new baseline build. They show the checks can fail.

- **Broken selector:** copy the broker JSON and change the scan's first `expectation` selector so it can't match. The
  runner passes the run, because it counts `actionFailed` as a broker outcome. The review must dispute it: the page
  loaded normally, so the broker didn't cause the failure.
- **No match:** use a profile fixture with no record on the broker. Expect `inconclusive`.
- **Bad token:** pass a token file containing a malformed token. Expect `fail` before any broker request.
