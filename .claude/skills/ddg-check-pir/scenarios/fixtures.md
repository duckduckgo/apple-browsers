# Fixtures

Scenarios name these in their `setup` line. Keep fixtures for your own scenarios in `fixtures.local.md` next to this
file, with the same tables. It and local profiles are gitignored.

## Profiles

| Name | File |
| --- | --- |
| `example` | `fixtures/profiles/example.json`, a made-up person |
| `john-smith-houston` | `fixtures/profiles/john-smith-houston.json`, a made-up person (John Smith, born 1974, Houston TX) |

Every match on a live broker is a real person's record, so an opt-out always targets a pinned `profileUrl`. Which
records a profile matches changes over time. If a scenario that needs a match gets none, try another profile and note it
in the results. Don't commit a profile taken from a real record.

## Brokers

Brokers are named by URL and run from the bundled JSON of the build under test, in
`SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/<url>.json`. Scenarios
don't copy broker JSON, so each run uses the JSON that branch ships. A scenario that needs an edited broker JSON names
the file and how it was made.

A local broker is named by its JSON file instead. `fakebroker.com` is the PIR fake broker's assisted broker, in
`docs/assisted-opt-out-broker.json` of a `duckduckgo/pir-fake-broker` checkout that serves its test assist endpoint.

## Credentials

| Name | What it is | Needed for |
| --- | --- | --- |
| `staging-token` | A staging access token passed with `--token-file` or `--token-env`. Never stored in the checkout or in a configuration file. | Opt-outs, and scans that need the CAPTCHA service. |

## App states

| Name | What it is | Needed for |
| --- | --- | --- |
| `fresh-simulator` | A simulator ddg-check-pir creates for one iOS attempt and deletes afterwards. | Every iOS scenario. |
| `fake-broker-john-doe` | The PIR fake broker running locally (web on port 3000, API on 3001) with one record seeded: `curl -X POST http://localhost:3001/api/profiles -H 'Content-Type: application/json' -d '{"firstName":"John","lastName":"Doe","middleName":"Michael","age":41,"city":"Springfield","state":"IL"}'` | The gate 3 scenarios. Its opt-out removes the record, so seed it again before each run. |
| `empty-store` | No saved PIR profile in the macOS DEBUG store. The seed signs the DEBUG account out itself; use `reseed`, with approval, to replace an existing profile. | `scheduler seed` on macOS. |
