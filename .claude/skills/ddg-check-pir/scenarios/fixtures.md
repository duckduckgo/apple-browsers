# Fixtures

Scenarios name these in their `setup` line. Keep fixtures for your own scenarios in `fixtures.local.md` next to this
file, with the same tables. It and local profiles are gitignored.

## Profiles

| Name | File |
| --- | --- |
| `example` | `fixtures/profiles/example.json`, a made-up person |

Every match on a live broker is a real person's record, so an opt-out always targets a pinned `profileUrl`. Which
records a profile matches changes over time. If a scenario that needs a match gets none, try another profile and note it
in the results. Don't commit a profile taken from a real record.

## Brokers

Brokers are named by URL and run from the bundled JSON of the build under test, in
`SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/<url>.json`. Scenarios
don't copy broker JSON, so each run uses the JSON that branch ships. A scenario that needs an edited broker JSON names
the file and how it was made.

## Credentials

| Name | What it is | Needed for |
| --- | --- | --- |
| `staging-token` | A staging access token passed with `--token-file` or `--token-env`. Never stored in the checkout or in a configuration file. | Opt-outs, and scans that need the CAPTCHA service. |

## App states

| Name | What it is | Needed for |
| --- | --- | --- |
| `fresh-simulator` | A simulator ddg-check-pir creates for one iOS attempt and deletes afterwards. | Every iOS scenario. |
| `signed-out-empty-store` | The macOS DEBUG account signed out, with no saved PIR profile. | `scheduler seed` on macOS. |

An iOS app state can name a launch profile, which the scenario passes with `--launch-profile`.
