# macOS UI tests

Read this before writing, fixing or running a test in `macOS/UITests/`. Helpers live in
`macOS/UITests/Common/` and `SharedPackages/UITestingSupport`, and accessibility identifiers in
`XCUIApplication.AccessibilityIdentifiers`; reuse them before writing new ones.

- Launch with `XCUIApplication.setUp(featureFlags:)`. Each key must be a macOS `FeatureFlag` raw
  value whose config allows local overriding; any other key crashes the app at launch.
- CI builds app and test artifacts together with the latest stable Xcode. Test code keeps a macOS
  12.3 deployment target; new XCTest APIs also need coverage in the legacy runtime adapter.
- Class setup resets the Review app defaults and container data before the class configures its
  fixture. State persists between methods of that class. Tell the user before a local live run.
- Scheme pre/post actions and portable artifacts share `Helpers/ui-tests/pre-run.sh` and
  `post-run.sh`; these own only their tests-server process.
- Run one class with
  `xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "macOS UI Tests" -only-testing:"UI Tests/<TestClass>"`.
