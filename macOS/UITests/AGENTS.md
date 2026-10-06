# macOS UI tests

Read this before writing, fixing or running a test in `macOS/UITests/`. Helpers live in
`macOS/UITests/Common/` and `SharedPackages/UITestingSupport`, and accessibility identifiers in
`XCUIApplication.AccessibilityIdentifiers`; reuse them before writing new ones.

- Launch with `XCUIApplication.setUp(featureFlags:)`. Each key must be a macOS `FeatureFlag` raw
  value whose config allows local overriding; any other key crashes the app at launch.
- Full CI runs, as opposed to PR runs, compile the tests with Xcode 16.2 on macOS 14, so test code
  sticks to APIs that SDK has.
- Running the `macOS UI Tests` scheme first runs `clean-app.sh review`, which deletes the Review
  app's defaults and container data. Tell the user before running it on their machine.
- Run one class with
  `xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "macOS UI Tests" -only-testing:"UI Tests/<TestClass>"`.
