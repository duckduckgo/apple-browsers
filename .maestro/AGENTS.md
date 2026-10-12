# iOS end-to-end tests (Maestro)

Read this before writing, fixing or running a flow in `.maestro/`.

- Pin every flag that decides which surface a flow asserts on, as quoted `ff.<flag>: "true"` launch
  arguments; unquoted YAML booleans are ignored. An unpinned flag follows the live privacy config,
  so a privacy-configuration change can turn a flow red with no app change.
- `ff.` arguments don't make the user internal. A flag whose default is `.internalOnly` also needs
  `isInternalUser: "true"`.
- `tapOn` doesn't retry a tap the app dropped. Guard each navigation step by waiting with
  `extendedWaitUntil` for an element that only exists on the destination screen.
- Locally, `setup_ui_tests.sh` builds into the repository's `DerivedData/` and creates the iPhone 16
  and iPad 10th generation simulators on iOS 18.2; it exits unless Maestro is exactly 1.40.3.
  `run_ui_tests.sh <flow-or-folder>` then reinstalls the app for each flow and runs it on the iPad
  when the flow has the `ipad` tag.
- CI runs suites by tag on Maestro Cloud: see the matrix in `.github/workflows/ios_end_to_end.yml`.
  iPad runs exist only for the suites listed there with an iPad device, and they exclude flows
  tagged `iphone`; iPhone runs exclude flows tagged `ipad`.
- To reproduce a CI failure without building, download the run's `duckduckgo-ios-app` artifact and
  run the flow on a local iPhone 16 / iOS 18.2 simulator, which matches the Cloud device.
