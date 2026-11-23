# Scenarios

Each `##` section is one scenario. Its title is its name in results and comparisons.

- A batch is the scenarios selected by tag, run on one build. For example, a baseline batch runs every scenario tagged
  `baseline`, and later batches are compared against it.
- Run a scenario once on each platform it lists, separately. A pass on one platform proves nothing for the other.
- `setup` names fixtures from `fixtures.md`. `expect` is what the verifier checks against the run's evidence.
- A scenario tagged `irreversible` sends a real opt-out. It needs the user's approval.

## Running a scenario

Keep each batch's configs and evidence together outside the checkout, for example `~/pir-runs/<batch>/configs/`
and `~/pir-runs/<batch>/evidence/`. Build both platforms first. Paths below start from the worktree root; config
paths must be absolute or relative to the config file.

| Scenario line | Becomes |
| --- | --- |
| `platform: iOS, macOS` | One run per platform, `--platform ios` and `--platform macos`. iOS runs can go in parallel; macOS runs go one at a time. |
| A profile fixture, such as `john-smith-dallas` | `"profileFile"`: `.claude/skills/verify-pir/scenarios/fixtures/profiles/john-smith-dallas.json` |
| A broker, such as `peoplefinders.com` | `"brokerFile"`: the bundled `<broker>.json` in `SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/` |
| `staging-token` | `--token-file` with the path the user gives, plus `"subscriptionEnvironment": "staging"`, `"pirEnvironment": "staging"` and `"pirEndpoint": "https://dbp-staging.duckduckgo.com"` |
| `fresh-simulator` | Nothing to add. iOS runs always create one. |
| The scenario's title | `--scenario "<title>"` on every `run` and `scheduler` command, so the batch report can group attempts |
| `action: run` with JSON fields | Those fields in the config, then `pir.py run --config <config> --evidence-dir <evidence>` |
| `action: scheduler seed` | `pir.py scheduler seed --platform ios --profile-file <profile> --evidence-dir <evidence>` |
| A matched `profileUrl` from the scan | Run the scan scenario first, then pin one `profileUrl` from its `pir-final-run.json` in `"expectedFile"`, a file holding `{"profileUrl": "..."}` |

For example, "Opt-out is submitted" on macOS:

```json
{
  "brokerFile": "<worktree>/SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/peoplefinders.com.json",
  "profileFile": "<worktree>/.claude/skills/verify-pir/scenarios/fixtures/profiles/john-smith-dallas.json",
  "expectedFile": "expected.json",
  "optOut": true,
  "emailConfirmation": true,
  "subscriptionEnvironment": "staging",
  "pirEnvironment": "staging",
  "pirEndpoint": "https://dbp-staging.duckduckgo.com"
}
```

```sh
P=.claude/skills/verify-pir/pir.py
python3 "$P" run --platform macos --config ~/pir-runs/<batch>/configs/optout-peoplefinders.json \
  --token-file <token file> --check-config
python3 "$P" run --platform macos --config ~/pir-runs/<batch>/configs/optout-peoplefinders.json \
  --token-file <token file> --evidence-dir ~/pir-runs/<batch>/evidence --scenario "Opt-out is submitted"
```

These steps need judgment and aren't in the mapping:

- When a scan matches several records, pin one that fits the profile's name, place and birth year. Check the ages on the results page.
- Get the user's approval before an `irreversible` scenario.
- When a scenario that needs a match gets none, try another profile fixture and note it in the results.
- Review each run's evidence as the skill's `verify.md` describes, and report the review next to the runner's verdict.

## Batch report

After the runs and their reviews, write the batch's HTML report next to its evidence:

```sh
python3 .claude/skills/verify-pir/report.py ~/pir-runs/<batch> --baseline ~/pir-runs/<baseline batch>
```

`--baseline` is optional. It matches rows by scenario title and platform and flags any change in verdict, review or
result. The report links snapshots that show real people's data, so keep it local.
