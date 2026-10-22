# Native macOS test artifacts

The notarized application uses the existing archive/export workflow. Test artifacts are built
separately, once per macOS/Xcode environment and app flavor, with `build-for-testing`.
The artifact schemes build only test targets and tests-server (`TEST_TARGET_NAME=`); they do not
compile the application. UI classes and both user modes share that environment's test artifact.
Sync and Performance each have one workload per environment, so they build native tests in their
own job before executing them.

CI pins Xcode using the existing select-xcode-version action. UI uses macOS 14 / Xcode 16.2,
macOS 15 / Xcode 26.2 and macOS 27 / Xcode 27.0. Sync also uses macOS 26 / Xcode 26.6.
The app archive remains universal; test products use the producer's native architecture.
Consumers must match the producer's macOS major version, architecture, and exact Xcode build.
A mismatch fails before an app is launched or its state is reset.

There are no XCTest binary patches, symbol forwarders, replacement runners or copied XCTest
runtimes. Xcode creates its own runner; the consumer uses that runner and the installed native
frameworks. Updating Xcode means changing the normal CI version setting, rebuilding the test
artifact, and running qualification on that environment. These checks do not establish that
arbitrary Xcode versions can exchange test bundles.

## Local Xcode

The normal app workspace and schemes remain available. Scheme pre/post actions and artifacts
use the same pre-run.sh / post-run.sh scripts for tests-server readiness and owned-process cleanup.
An occupied port fails instead of stopping an unrelated server.

UITestCase resets the selected Debug/Review app profile once before each class configures its
fixture. State persists between methods. Performance and Sync reset at class setup too; Sync
retains its per-method cleanup. A local live run removes the selected test profile's data.

## Dedicated Mac or SSH

The native UI producer publishes a run-native.json URL in its job summary. Select the producer
for the destination Mac's OS, architecture and Xcode; a macOS 14 artifact cannot run on macOS 12.
The manifest pairs the notarized app and native test archive using revision and SHA-256 checksums.

```bash
python3 remote.py --ssh-config /path/to/pinned-config \
  --results /path/to/results test-mac https://example.com/path/run-native.json \
  --only AddressBarUrlEditingTests
```

The remote Mac needs the matching full Xcode, Python 3, a logged-in unlocked desktop and configured
UI Automation. The launcher runs a native UI probe first, then the test workload with a temporary
keychain. It restores the prior SSH/GUI keychain selection and fetches results even on failure.
It does not enable unattended Automation or grant folder permissions. Provision those explicitly
on the dedicated test host. Only one UI workload may use an account at a time.
The default remote directory is ~/workspace/ddg-ui-tests; --remote-root selects a lease workspace.

To download and run directly on the matching Mac:

```bash
curl -fL https://example.com/path/run-ui-tests.py -o runner.py
python3 runner.py download https://example.com/path/run-native.json --output run
python3 run/ui-tests/Scripts/prepare-host.py --result readiness
python3 run/ui-tests/Scripts/with-keychain.py --result keychain-session -- \
  python3 run/ui-tests/Scripts/artifact.py run run/ui-tests --only AddressBarUrlEditingTests
```

Use --suite performance, --suite sync, or --suite sync-appstore for the other targets.
--plan 'UI Tests App Store' selects the broader App Store plan; --only Class/method filters a method.
Sync recovery CODE is supplied at runtime and is not included in artifacts. Results include
xcresults, logs and JSON summaries. Missing results, incomplete execution or all-skipped runs fail.

## Validation

```bash
python3 -B -m unittest discover -s macOS/scripts/tests -v
bash macOS/UITests/Helpers/ui-tests/build.sh dmg /absolute/path/to/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

On each environment, verify a real UI execution with the native runtime, the full selected suite,
and the App Store sandbox leg. Loader checks and old cross-version CI results are insufficient.
