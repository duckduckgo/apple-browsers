# Gate 2: publish the assisted BeenVerified JSON

Publishing 0.12.0 brings BeenVerified back. `main` bundles 0.11.0 with `removedAt` set (2026-07-24), and the remote
update serves the same, so no build scans BeenVerified today. 0.12.0 has no `removedAt`, so clients that accept it
start scanning BeenVerified again, and clients that can't run an assisted opt-out must reject it without disturbing any
other broker.

`beenverified.com` below is the assisted BeenVerified JSON this branch bundles, version 0.12.0, in
`SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/`. It adds three
top-level `userAssist` steps to the opt-out, all before its `emailConfirmation` step, and drops `removedAt`. `main`
bundles 0.11.0, which has neither. Run these scenarios against the exact file that will be published; if it differs from 0.12.0, rerun them.

0.12.0 also limits who scans it. Its scan step gains a `generateEmail` action, nested in the condition for highly
populated states. The app treats a scan with `generateEmail` as needing a subscription
(`DataBroker.scanRequiresSubscription`), so on macOS subscribers scan the returned BeenVerified and signed-out Freemium
users don't. iOS rejects 0.12.0 and keeps its removed 0.11.0, so nothing changes there. Scheduler seeds
are always Freemium; the subscriber side is covered by a `run` with a token, which uses the same scan steps but not the
scheduler's eligibility.

## iOS rejects the assisted BeenVerified file

- tags: gate2, compatibility
- platform: iOS
- setup: `john-smith-houston`, `beenverified.com`
- action: `run`, `"optOut": false`
- verdict: fail
- expect:
  - The app rejects the file as an unsupported action before any broker request.

## An iOS fresh install loads every broker except BeenVerified

The seed scans one broker to keep the run short; the check is on the brokers the app loaded, which the first
`pir-http-*.json` with path `/api` lists with their versions and `isRemoved`.

- tags: gate2, scheduler, scan, live
- platform: iOS
- setup: `john-smith-houston`, `fresh-simulator`
- action: `scheduler seed --broker searchpeoplefree.com`
- expect:
  - `/api` lists no BeenVerified 0.12.0. It lists no BeenVerified at all, or only a version that a remote broker update
    stored.
  - Every other bundled broker is listed.
  - searchpeoplefree.com gets a fresh `scanStarted` and reaches a terminal event.

## macOS stores the assisted BeenVerified 0.12.0 as an active broker

- tags: gate2, scheduler, scan, live, freemium
- platform: macOS
- setup: `john-smith-houston`, `empty-store`
- action: `scheduler seed --broker searchpeoplefree.com`
- expect:
  - The first `/api` response lists beenverified.com at version 0.12.0 with `isRemoved` false.
  - searchpeoplefree.com gets a fresh `scanStarted` and reaches a terminal event.

## macOS Freemium doesn't scan BeenVerified 0.12.0

Run after the previous scenario; the reseed replaces its test profile.

- tags: gate2, scheduler, scan, live, freemium
- platform: macOS
- setup: `john-smith-houston`, the profile the previous scenario saved
- action: `scheduler reseed --broker beenverified.com --broker searchpeoplefree.com`
- verdict: inconclusive
- expect:
  - The seed stops before any scan with the `unknownBroker` receipt error, because Freemium eligibility leaves
    BeenVerified 0.12.0 out of the plan.

## macOS subscriber scans BeenVerified 0.12.0

A Texas profile takes BeenVerified's path for highly populated states, which runs the new `generateEmail`.

- tags: gate2, scan, live, subscriber
- platform: macOS
- setup: `john-smith-houston`, `beenverified.com`, `staging-token`
- action: `run`, `"optOut": false`
- expect:
  - The scan reaches the comprehensive form, fills the generated email, and ends in `matchesFound` or `noMatchFound`.
  - No `emailError` or token error.

## main doesn't scan the removed BeenVerified 0.11.0

The baseline for the previous three scenarios, on a build from a worktree of `anh/shared/pir/verify-pir-extras`.

- tags: gate2, scheduler, scan, live, freemium
- platform: macOS
- setup: `john-smith-houston`, `empty-store`
- action: `scheduler seed --broker searchpeoplefree.com` on the `verify-pir-extras` build
- expect:
  - The first `/api` response lists beenverified.com at version 0.11.0 with `isRemoved` true.
  - searchpeoplefree.com gets a fresh `scanStarted` and reaches a terminal event.

## macOS reactivates a stored, removed BeenVerified 0.11.0 as 0.12.0

Existing users get the assisted file as an update over their stored, removed 0.11.0. Each step scans one control
broker. The upgrade scans a broker the seed didn't, because Freemium runs a broker's first scan but never a rescan.
BeenVerified isn't forced, because whether a Freemium account scans it is what this checks.

- tags: gate2, scheduler, scan, live, upgrade, freemium
- platform: macOS
- setup: `john-smith-houston`, `empty-store`
- action: `scheduler seed --broker searchpeoplefree.com --step seed` from a worktree of
  `anh/shared/pir/verify-pir-extras`, which bundles 0.11.0; then `scheduler upgrade --broker freepeopledirectory.com
  --step upgrade` from this branch's worktree
- expect:
  - After the seed, `/api` lists beenverified.com 0.11.0 with `isRemoved` true.
  - After the upgrade's refresh, `upgrade-refresh.json` lists beenverified.com 0.12.0 with `isRemoved` false and the same
    broker ID.
  - `upgrade-scans.json` queues freepeopledirectory.com with nothing in `notQueued`, and it reaches a terminal event.
  - BeenVerified gets no fresh `scanStarted`, because the account is Freemium. The skill doesn't check this; read
    `/api/brokers/beenverified.com` from the upgrade's evidence.

## iOS keeps a stored, removed BeenVerified 0.11.0 when the assisted 0.12.0 arrives

- tags: gate2, scheduler, scan, live, upgrade
- platform: iOS
- setup: `john-smith-houston`
- action: `scheduler seed --platform ios --keep --broker searchpeoplefree.com --step seed` from a worktree of
  `anh/shared/pir/verify-pir-extras`, which bundles 0.11.0; then, from this branch's worktree,
  `scheduler upgrade --platform ios --broker freepeopledirectory.com --step upgrade`, with `--simulator` set to the
  `simulator.udid` in the seed's `launch.json`
- expect:
  - After the seed, `/api` lists beenverified.com 0.11.0 with `isRemoved` true.
  - After the upgrade's refresh, `upgrade-refresh.json` still lists beenverified.com 0.11.0 with `isRemoved` true and the
    same broker ID; the native logs show the bundled 0.12.0 skipped as unsupported.
  - `upgrade-scans.json` queues freepeopledirectory.com with nothing in `notQueued`, and it reaches a terminal event.
