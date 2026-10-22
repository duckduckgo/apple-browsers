# macOS UI tests

Read this before writing, fixing or running a test in `macOS/UITests/`. Helpers live in
`macOS/UITests/Common/` and `SharedPackages/UITestingSupport`, and accessibility identifiers in
`XCUIApplication.AccessibilityIdentifiers`; reuse them before writing new ones.

- Launch with `XCUIApplication.setUp(featureFlags:)`. Each key must be a macOS `FeatureFlag` raw
  value whose config allows local overriding; any other key crashes the app at launch.
- CI builds test artifacts once per macOS/Xcode environment. Consumers use the same native Xcode
  version and build as their producer. The optional macOS 12 adapter lives only in Helpers/ui-tests/monterey.py and monterey/. Never extend it to native macOS 14+ execution.
- Class setup resets the Review app defaults and container data before the class configures its
  fixture. State persists between methods of that class. Tell the user before a local live run.
- Scheme pre/post actions and portable artifacts share `Helpers/ui-tests/pre-run.sh` and
  `post-run.sh`; these own only their tests-server process.
- Run one class with
  `xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "macOS UI Tests" -only-testing:"UI Tests/<TestClass>"`.
