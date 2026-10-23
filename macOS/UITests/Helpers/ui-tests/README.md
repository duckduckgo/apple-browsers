# Optional macOS 12 test execution

The parent PR shares the existing `build-for-testing` products between native CI jobs.
It keeps their Xcode schemes, test plans and `test-without-building` invocation unchanged.
No compatibility code runs on macOS 14 or later.

`monterey.py` is a separate, explicit consumer for macOS 12. It accepts the ordinary
`Build/Products` archive from the macOS 14 / Xcode 16.2 producer. The test bundle's
`DTXcodeBuild` must be `16C5032a`; the destination must have Xcode 13.4.1 and Python 3.9+.
Other combinations fail before test-profile cleanup or app launch.

On a dedicated Monterey Mac, download the artifacts from the **same workflow run and revision**:

```bash
gh run download RUN_ID --repo duckduckgo/apple-browsers \
  --name DuckDuckGo-ui-tests-dmg-macos14-xcode16.2 --dir native-tests
mkdir -p native-tests/DerivedData
tar -xzf native-tests/ui-test-products.tar.gz -C native-tests/DerivedData
# Download and extract that run's notarized DuckDuckGo-review-*.app.tar.xz separately.
python3 macOS/UITests/Helpers/ui-tests/monterey.py \
  --products native-tests/DerivedData/Build/Products \
  --preflight-only --result results/loader
python3 macOS/UITests/Helpers/ui-tests/monterey.py \
  --products native-tests/DerivedData/Build/Products \
  --app '/absolute/path/DuckDuckGo Review.app' \
  --only AddressBarSearchQueryEditingTests --user-mode production --result results/search
```

Keep this branch's `macOS/UITests` helpers/plans and existing `macOS/clean-app.sh`
available on the Mac. `--plan` accepts another existing test-plan path; `--only` may
be repeated for classes or `Class/method`. For App Store execution, use the matching
App Store artifact and notarized application. This child PR keeps both architectures
in the app artifact so an Intel Monterey Mac can use it too.

The consumer copies the installed Xcode 13 runner, compiles the small XCTest
forwarder, changes only the copied test bundle's XCTest linkage and signs that copy.
The copied legacy runner disables its own App Sandbox for the Monterey fixture's
defaults helper; the original producer runner and notarized app are not changed.
The explicit Swift symbol bridge is custom compatibility code, not an Apple-supported
guarantee that arbitrary Xcode versions can exchange test bundles.

Loader preflight does not launch the app and does not qualify UI execution. A real run
requires a logged-in unlocked GUI account, configured UI Automation, working keychain
access and the runner's required folder permissions. This command does not grant TCC
permissions or enable Screen Sharing. Run only one UI workload in that account.

Execution resets only the selected **Review** profile once before each class, using
the existing cleanup script. Methods run in separate Xcode 13 processes, each with
a five-minute limit. Results contain per-method xcresults/logs and JSON summaries
from `xcresulttool`; missing results, setup failures and an entirely skipped suite fail.
Only the test server started by this command is stopped. `CODE`, when needed by a
provided Sync target/plan, comes from the environment and is never packaged.

Full runtime qualification of this revised adapter is still required. Earlier loader
passes and results from the superseded implementation do not establish a suite pass.
