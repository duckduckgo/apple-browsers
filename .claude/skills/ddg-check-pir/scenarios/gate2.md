# Gate 2: publish the assisted BeenVerified JSON

Clients that can't run an assisted opt-out must reject the file without losing BeenVerified or any other broker, and
macOS must keep scanning BeenVerified while the feature is off.

`beenverified.com` below is the assisted BeenVerified JSON this branch bundles, version 0.12.0, in
`SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/`. It adds three
top-level `userAssist` steps to the opt-out, all before its `emailConfirmation` step. `main` bundles 0.11.0, which has
none. Run these scenarios against the exact file that will be published; if it differs from 0.12.0, rerun them.

## iOS rejects the assisted BeenVerified file

- tags: gate2, compatibility
- platform: iOS
- setup: `john-smith-houston`, `beenverified.com`
- action: `run`, `"optOut": false`
- verdict: fail
- expect:
  - The app rejects the file as an unsupported action before any broker request.

## An iOS fresh install loads every broker except BeenVerified

- tags: gate2, scheduler, scan, live
- platform: iOS
- setup: `john-smith-houston`, `fresh-simulator`
- action: `scheduler seed`
- expect:
  - BeenVerified isn't planned.
  - Every other bundled broker is planned, gets a fresh `scanStarted` and reaches a terminal event.

## macOS keeps scanning BeenVerified with the feature off

- tags: gate2, scheduler, scan, live
- platform: macOS
- setup: `john-smith-houston`, `signed-out-empty-store`
- action: `scheduler seed`
- expect:
  - BeenVerified is planned, gets a fresh `scanStarted` and reaches a terminal event.
  - Every other planned broker behaves as in the gate 1 scheduler scenario.

## macOS upgrades a stored BeenVerified 0.11.0 to the assisted 0.12.0

Most users get the assisted file as an update over a stored 0.11.0. Seed first on a build from a worktree of
`anh/shared/pir/verify-pir-scenarios`, which bundles 0.11.0, then switch to a build of this branch.

- tags: gate2, scheduler, scan, live, upgrade
- platform: macOS
- setup: `john-smith-houston`, `signed-out-empty-store`
- action: `scheduler seed` on the `verify-pir-scenarios` build; then, with the DEBUG browser and agent stopped, clear
  the saved local broker-version check so the next launch upserts the bundled 0.12.0:
  `defaults delete com.duckduckgo.macos.browser.debug macos.browser.data-broker-protection.LastLocalVersionChecked` and
  the same key in `com.duckduckgo.macos.DBP.backgroundAgent.debug`; then `scheduler observe` on this branch's build
  while its scans run
- expect:
  - The stored BeenVerified is 0.12.0 after the upgrade, with the same broker ID, records and history as before.
  - BeenVerified scans continue and reach terminal events.
  - No BeenVerified opt-out starts. The skill doesn't check this; read the debug server's `/api/events` for BeenVerified
    `optOutStarted` events.

## iOS keeps a stored BeenVerified 0.11.0 when the assisted 0.12.0 arrives

The same upgrade on one simulator. `--keep` leaves the seeded simulator in place, and `scheduler observe` reads any
simulator whose debug server is on.

- tags: gate2, scheduler, scan, live, upgrade
- platform: iOS
- setup: `john-smith-houston`
- action: `scheduler seed --platform ios --keep` on a build from a worktree of `anh/shared/pir/verify-pir-scenarios`,
  which bundles 0.11.0; set `UDID` to the `simulator.udid` in that seed's launch record and install this branch's iOS
  build on it; clear the saved local broker-version check so the next launch tries the bundled 0.12.0, with
  `xcrun simctl spawn "$UDID" defaults delete com.duckduckgo.mobile.ios macos.browser.data-broker-protection.LastLocalVersionChecked`;
  launch, turn on **Debug Server** in the PIR debug menu, start a scan, then `scheduler observe --platform ios` with
  BeenVerified's broker URL and profile query ID from `GET /api`
- expect:
  - The bundled 0.12.0 is skipped as unsupported, and the stored BeenVerified stays 0.11.0 with the same broker ID,
    records and history.
  - BeenVerified scans continue and reach terminal events.
  - Every other broker keeps working.
