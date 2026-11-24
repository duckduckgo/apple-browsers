# Scenarios

Each `##` section is one scenario. Its file and title, as `<file>: <title>`, name it in results and comparisons.

- A batch is the scenarios selected by tag, run on one build. For example, a baseline batch runs every scenario tagged
  `baseline`, and later batches are compared against it.
- Run a scenario once on each platform it lists, separately. A pass on one platform proves nothing for the other.
- `setup` names fixtures from `fixtures.md`, and from `fixtures.local.md` when it exists. `expect` is what the reviewer checks against the run's evidence.
- A scenario tagged `irreversible` sends a real opt-out. It needs the user's approval.

## Running a scenario

Keep each batch's configs and evidence together outside the checkout, for example `~/pir-runs/<batch>/configs/`
and `~/pir-runs/<batch>/evidence/`. Build both platforms first. Paths below start from the worktree root; config
paths must be absolute or relative to the config file.

| Scenario line | Becomes |
| --- | --- |
| `platform: iOS, macOS` | One run per platform, `--platform ios` and `--platform macos`. iOS runs can go in parallel; macOS runs go one at a time. |
| A profile fixture, such as `john-smith-dallas` | `"profileFile"`: `.claude/skills/ddg-check-pir/scenarios/fixtures/profiles/john-smith-dallas.json` |
| A broker, such as `peoplefinders.com` | `"brokerFile"`: the bundled `<broker>.json` in `SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/` |
| `staging-token` | `--token-file` with the path the user gives, plus `"subscriptionEnvironment": "staging"`, `"pirEnvironment": "staging"` and `"pirEndpoint": "https://dbp-staging.duckduckgo.com"` |
| `fresh-simulator` | Nothing to add. iOS runs always create one. |
| The scenario's file and title | `--scenario "<file>: <title>"` on every `run` and `scheduler` command, such as `--scenario "peoplefinders.com: Scan finds the profile's record"`. The report groups results by file. |
| `verdict: fail` (or `inconclusive`) | `--expect fail`. Without the line the scenario expects `pass`. A run whose verdict differs from the expected one needs attention. |
| `action: run` with JSON fields | Those fields in the config, then `pir.py run --config <config> --evidence-dir <evidence>` |
| `action: scheduler seed` | `pir.py scheduler seed --platform ios --profile-file <profile> --evidence-dir <evidence>` |
| A matched `profileUrl` from the scan | Run the scan scenario first, then pin one `profileUrl` from its `pir-final-run.json` in `"expectedFile"`, a file holding `{"profileUrl": "..."}` |

For example, "Opt-out is submitted" on macOS:

```json
{
  "brokerFile": "<worktree>/SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/peoplefinders.com.json",
  "profileFile": "<worktree>/.claude/skills/ddg-check-pir/scenarios/fixtures/profiles/john-smith-dallas.json",
  "expectedFile": "expected.json",
  "optOut": true,
  "emailConfirmation": true,
  "subscriptionEnvironment": "staging",
  "pirEnvironment": "staging",
  "pirEndpoint": "https://dbp-staging.duckduckgo.com"
}
```

```sh
P=.claude/skills/ddg-check-pir/pir.py
python3 "$P" run --platform macos --config ~/pir-runs/<batch>/configs/optout-peoplefinders.json \
  --token-file <token file> --check-config
python3 "$P" run --platform macos --config ~/pir-runs/<batch>/configs/optout-peoplefinders.json \
  --token-file <token file> --evidence-dir ~/pir-runs/<batch>/evidence --scenario "peoplefinders.com: Opt-out is submitted"
```

These steps need judgment and aren't in the mapping:

- When a scan matches several records, pin one of them. Prefer one whose card shows an age.
- Get the user's approval before an `irreversible` scenario.
- When a scenario that needs a match gets none, try another profile fixture and note it in the results.
- Review each run's evidence as the skill's `review.md` describes, and report the review next to the runner's verdict.

## Batch report

Each `run` or `scheduler` attempt with `--scenario` and `--evidence-dir ~/pir-runs/<batch>/evidence` rewrites
`~/pir-runs/<batch>/report.html` when it finishes, so the page can be reloaded during the batch. After the reviews, write
it once more so it picks them up:

```sh
python3 .claude/skills/ddg-check-pir/report.py ~/pir-runs/<batch>
```

Compare against an earlier batch only when the user names one: add `--baseline <that batch's folder>`. Don't pick a
baseline on your own. The batch remembers it, so later refreshes keep the comparison until `report.py` runs without
`--baseline`. Rows are matched by scenario, broker and platform, and a run counts as needing attention when it
is worse than the baseline's run, not merely different. The report links snapshots that show real people's data, so
keep it local.
