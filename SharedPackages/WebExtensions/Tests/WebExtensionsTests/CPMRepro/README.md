# CPM repro harness

Reproduces Cookie Pop-up Management (CPM) messaging failures on system WebKit. The production
embedded extension, `WebExtensionManager`, `WebExtensionLifecycleCoordinator` and
`CPMMessagingHealthMonitor` run against real web views. Faults are injected only through seams:
the native handler interceptor, a JavaScript prelude prepended to the background script, and
WebKit process control (`CPMReproWebKitSPI`). Each test asserts what users need (a navigation gets
a CPM response), so a failing test means the problem reproduced.

The harness runs on macOS only. The app-hosted iOS test run cannot find the package's resource bundle
(`Bundle.module`), which crashes the test process, so the tests skip on iOS and are only compiled there.

## Tiers

- **CI**: tests run once per CI run and finish in seconds. A test that proves a fix is committed
  twice in its pull request: first the test alone (CI red), then the fix (CI green).
- **Local** (`requireLocalRun()`): slow tests, and `CPMReproWebKitTests`, which characterize system
  WebKit with every protection off. They only run with `CPM_REPRO=1`; the WebKit ones also need
  `CPM_REPRO_WEBKIT=1`.

```
CPM_REPRO=1 CPM_REPRO_ITERATIONS=20 swift test --filter CPMRepro
CPM_REPRO=1 CPM_REPRO_WEBKIT=1 swift test --filter CPMReproWebKitTests
```

Knobs: `CPM_REPRO_ITERATIONS` (default 1), `CPM_REPRO_IDLE`, `CPM_REPRO_FREEZE`,
`CPM_REPRO_OBSERVE`, `CPM_REPRO_GAP`, `CPM_REPRO_INSTALL_DIR`.

## Keeping it trustworthy

- A fault that cannot be injected must fail the test, never skip the fault silently
  (`CPMReproWebKitSPI` throws `SPIUnavailable`).
- Assert the precondition of every scenario (tabs worked before the fault) so a test cannot pass
  without having exercised the failure.
- `CPMReproWebKitTests` are the canary for system WebKit: when one starts failing on a new OS, the
  WebKit bug is fixed and the matching app mitigation can be reconsidered.
