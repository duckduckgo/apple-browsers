# Build once, run on each macOS

The notarized Review build job opts into `build-ui-tests: true`. It selects the latest installed
stable Xcode and calls one `build-for-testing` graph for the app, UI Tests, Performance Tests and
SyncE2EUITests. App Store builds use the corresponding producer scheme. Shared dependencies resolve
and build in this graph, once per architecture/configuration; the universal products contain both
arm64 and x86_64. Existing Release/Alpha archive/export builds keep their original path.

`archive.sh` notarizes/staples the app while `artifact.py pack` copies the test runners, test server,
resources, test plans, XCTest runtime and discovered method inventory. App and test archives are
published together with a `run-review.json` (or `run-sandbox-review.json`) descriptor containing
revision and SHA-256 checksums. No credentials or recovery codes belong in the artifact.

CI consumers download the pair and use `test-without-building -xctestrun`. They do not open the
project, resolve Swift packages or compile application/test targets. Each host selects its newest
compatible installed Xcode for the test service and result tools. The OS matrix stays; the Xcode
matrix is removed. Compilation cost moves to the producer, so fan-out jobs get cheaper; producer
latency and universal artifact size increase. Packaging overlaps notarization; compiler work stays
in one dependency graph rather than racing two xcodebuild processes.

## Local Xcode

The existing workspace/schemes still build the app and tests. Scheme pre/post actions call only
`pre-run.sh` and `post-run.sh`. The pre script starts the built server and checks readiness; the post
script stops only its recorded process. A busy server port fails instead of killing another run.

`UITestCase` resets app defaults, container data, WebKit data and app-configuration group data once
before **each class**, before the subclass configures its fixture. State persists between methods
in that class. Performance and Sync classes use the same reset. Sync also retains its explicit cleanup
between methods. Only Debug/Review bundle identifiers are allowed. A local live run removes these test app
profiles, so save any Review data you need first.

## Download and run on a Mac

Copy the run descriptor URL from the producer job summary. In a fresh directory:

```bash
RUN_URL='https://<test-build-prefix>/<revision>/run-review.json'
curl -fL "${RUN_URL%/*}/run-ui-tests.py" -o runner.py
python3 runner.py download "$RUN_URL" --output run
python3 run/ui-tests/Scripts/artifact.py run run/ui-tests \
  --only AddressBarUrlEditingTests
```

Use `--suite performance`, `--suite sync`, or `--suite sync-appstore` for other suites;
`--plan 'UI Tests App Store'` selects the broader App Store plan. Without `--only`, the selected
plan runs all enabled tests. `--only Class/method` limits a method. `CODE` is supplied at runtime
for Sync tests that require it. Results include xcresult bundles, xcodebuild/server logs and JSON
summaries; zero executed tests, all skipped tests and missing result bundles fail the command.

The Mac needs a full locally compatible Xcode, Python 3, an unlocked GUI login and working developer
UI automation. Xcode's first-launch components must be installed. No Screen Sharing is required by
the launcher: commands run over SSH against the existing console session. Pass
`--xcode /Applications/Xcode13.4.1.app` if xcode-select points elsewhere.

Check `/usr/bin/automationmodetool` when provisioning a dedicated CI Mac. Apple's documented
`automationmodetool enable-automationmode-without-authentication` configures unattended activation
and requires administrator authentication in the shell (`man automationmodetool`). Do this only
on the dedicated test environment. A `ready` Virfield developer lease does not prove UI-test
readiness: qualify a real XCUITest before unattended use. In the 2026-10-21 validation, fresh
Monterey and Sonoma developer profiles still timed out enabling automation after this configuration;
loading the bundle successfully did not establish successful UI execution. `--gui` is an optional
Terminal console launcher, not an automation permission grant.

## Monterey

The test bundle deployment target remains 12.3. That setting alone is insufficient: a modern
XCTRunner/XCTest runtime requires a newer OS. On macOS 12, the consumer copies its installed Xcode
13.4.1 XCTRunner and compiles only `XCTestCompat.swift` with the local Swift 5.6 compiler. The shim
forwards newer XCTest Swift symbols to old equivalents (issue severity is not represented by old
XCTest). It rewrites/signs copied test products; the notarized app stays unchanged. Symbol loading
is checked before app state is touched. Application/test sources and package graphs are never built
on Monterey.

The old runtime runs one method per xcodebuild process because its automation event queue can
become unusable across methods. A run tracks classes and enables the full reset only for the first
method of each class. Class fixture setup still runs in each fresh process. This costs process startup
and produces one xcresult per method. A legacy method is limited to five minutes; modern batches
use `--timeout` (default one hour) and retain retry-on-failure behavior. Changes in compiler/XCTest
symbols require revalidating the adapter; this is a compatibility layer, not an Apple guarantee
that arbitrary Xcode versions can exchange UI test bundles.

## Virfield and a rented Mac mini

Use the same published pair and launcher for either host:

```bash
# Virfield: ready lease + verified/pinned SSH config obtained through its normal lease workflow.
python3 macOS/UITests/Helpers/ui-tests/remote.py \
  --ssh-config /path/to/lease/config virfield "$RUN_URL" \
  --xcode /Applications/Xcode13.4.1.app --only AddressBarUrlEditingTests

# Dedicated Mac: configure a pinned SSH alias and provision an unlocked console session.
python3 macOS/UITests/Helpers/ui-tests/remote.py monterey-mini "$RUN_URL" \
  --xcode /Applications/Xcode13.4.1.app --only AddressBarUrlEditingTests
```

The launcher uses a unique remote directory, uses the logged-in GUI session through SSH and fetches
results even after test failure. It does not provision machines, disable host-key checks, reset an
OS or release leases. Use a dedicated test account/profile and run only one UI session per Mac.
Virfield guests and physical hosts use the same protocol once a lease is ready.

[MacinCloud documents Monterey for Dedicated Server plans](https://support.macincloud.com/support/solutions/articles/8000095277-macos-monterey-12-6-7-now-supported-on-macincloud-dedicated-servers).
That announcement is from 2023; confirm current Intel/M1 Monterey stock, full Xcode 13.4.1,
admin/SSH and an interactive desktop before renting. Current stock is not established by that
article. [MacStadium offers dedicated Macs](https://macstadium.com/pricing), but Monterey inventory
also requires confirmation. Do not choose new hardware that cannot boot Monterey.

## Validation

```bash
python3 -B -m unittest discover -s macOS/scripts/tests -v
macOS/UITests/Helpers/ui-tests/build.sh dmg /tmp/ui-test-build CODE_SIGNING_ALLOWED=NO
python3 macOS/UITests/Helpers/ui-tests/artifact.py pack \
  --products /tmp/ui-test-build/Build/Products --distribution dmg --output /tmp/ui-tests.tar.gz
```

Unsigned local app builds validate compilation/packaging only; CI needs its normal signing assets
for the notarized Review app. A loader check is not a passing UI suite: qualify actual tests on each
supported OS, especially legacy XCTest, when changing the producer Xcode.
