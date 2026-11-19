---
name: verify-macos-browser
description: Prove a macOS browser change works by driving the real Debug app built from this worktree, on this Mac or in a local VM, and capturing accessibility, pixel, wide-event and log evidence. Use before opening a PR or to reproduce a bug.
disable-model-invocation: true
---

# Verify macOS Browser

Prove the change on the running app, not by reading code. A proof is: the action, the resulting
state, and a second, independent read that shows it (AX state, page URL, a log line, a pixel). No
evidence, no verdict.

Bundle id (Debug, DeveloperID): `com.duckduckgo.macos.browser.debug`

**How it gets used.** Agents don't pick this skill on their own (`disable-model-invocation`), so name it when you
start a task ("… and verify it with verify-macos-browser"), or invoke `/verify-macos-browser`.

## 0. Before you start

- **Ask the user where to run it**, unless they already said:
  - **On this Mac:** drives the user's screen; they can't use the Mac meanwhile.
  - **In a VM:** runs in a macOS VM over ssh, never touching their screen. Offer it only when one is set up
    (`ssh vm-1 true` works); otherwise mention `VM-SETUP.md` once. In a VM, run `verify.sh vm <topic>` first;
    every later step then runs there, and the screen and grant points below don't apply.
- On this Mac, tell the user you're about to take over the screen and wait for an OK (unless a harness's
  approved plan covers it). Ask them not to switch apps while you drive.
- On this Mac, the process that runs `verify.sh ax` needs the Accessibility and Screen Recording grants. An
  agent's own shell often has neither (`osascript`: "not allowed assistive access"; `screencapture`: "could not
  create image from display"): drive with computer use, or put the `ax` steps in a script and run it from a
  terminal that holds both grants, output to a file. The other commands need no grant.
- Pick a short `<topic>` (e.g. `ntp-promo`): it names the build, the log filter and the evidence folder.
- Read `features/README.md`, then `features/<feature>.md` for the area you're touching. Every entry point your
  change touches needs its own check or an Unverified line.

## 1. Instrument (only if needed)

For state, timing or geometry claims, add temporary logs with one fixed tag. Use `os.Logger` with
public interpolation; `NSLog` lines don't reach the unified log in this app.

```swift
import os
Logger(subsystem: "verify", category: "verify").notice("[VERIFY] <what>: \(String(describing: value), privacy: .public)")
```

Remove every `[VERIFY]` line before commit (step 6).

## Run every step through `verify.sh`

Every shell step below goes through one script, so one permission rule covers the whole run:

```
.claude/skills/verify-macos-browser/scripts/verify.sh <command> <topic> [args]   # from the worktree root
```

Call it as a single command: no `&&`, `;`, pipes, `cd`, variables or redirects around it. Anything
compound, or any command you write by hand, asks the user for approval again. If you need something
the script can't do, add a subcommand to it instead of a one-off command. Evidence lands in
`~/.ddg-verify-macos/<topic>/`, outside the checkout (`VERIFY_MACOS_HOME` overrides the root). Exit codes:
`0` ok, `1` a check failed, `2` error or can't tell.

## 2. Set state (before build: the app reads it at launch)

- **Feature flags:** pin every flag the behavior depends on, on or off. Never rely on what the
  remote privacy configuration says today.
  ```
  verify.sh flag <topic> <FeatureFlagCaseName> on|off
  ```
  It reads `FeatureFlag.swift` in the checkout (run it from the worktree root, or set
  `VERIFY_WORKTREE`) and refuses an unknown case or one with `supportsLocalOverriding: false`, whose
  override the app would ignore.
- **Other state:** `verify.sh set-default <topic> <key> <type> <value>` with the exact key; it is
  remembered for cleanup. Never `defaults delete` the whole domain.
  Most preferences are read once at launch (e.g. `TabsPreferences` is `@Published`, loaded in `AppDelegate`):
  a `defaults write` while the app runs doesn't reach it. To change one mid-run, set it and run `build` again
  (a no-change build only relaunches), or change it through Settings.
- Never use `UITEST_MODE=1`: it switches the app's run type and changes behavior in over 100 places.

## 3. Build and launch

```
verify.sh build <topic> <path-to-checkout> [--automation]
```

- Quits this topic's previous build, builds with `xcodebuild` (uncommitted edits included), records the source
  fingerprint and the binaries' sha256, and launches with `-AppleLanguages (en) -AppleLocale en_US
  -isInternalUser true`. Locators match English; pass `--language <l> --locale <l>` only to test localization.
- Waits until the app is ready (a main window, or the content blocker with `--automation`) and starts the
  PixelKit stream. Full output in `build.log`.
- `--automation` starts the AutomationServer so `web` can read the URL, run JS and `web navigate <url>` for
  setup (never the action under proof). It **turns off popup blocking and the quit survey**: never use it to
  verify either.
- DerivedData is found, not configured: this checkout's Xcode folder, else the main checkout's, else a new
  `<checkout>/.build/DerivedData` (full build). `VERIFY_DERIVED_DATA=<path>` forces one.
- About 23–40 s incremental. Don't build in Xcode at the same time. On a build failure, report the first error
  and stop; don't fix unrelated build issues. Exception: after switching branches, "type X has no member Y"
  for code that is there is a stale module in DerivedData: move that module out and rebuild.

## 4. Doctor (always, before driving)

```
verify.sh doctor <topic>
```

It checks three things against what `build` recorded and fails (exit 2) on any mismatch:
- the worktree's source fingerprint (HEAD plus every uncommitted change): `STALE SOURCE`;
- the sha256 of the binary and its `.debug.dylib` (Debug keeps the app code there): `REBUILT`;
- the process started after the build ended: `OLD PROCESS`.

It also counts `[VERIFY]` strings in the `.debug.dylib`: above 0 if you instrumented. Never drive a
stale build; rebuild.

## 5. Drive and capture

- Drive the `DuckDuckGo - verify-<topic>` window only: computer use, or `verify.sh ax <topic> …` (`dump`,
  `find`, `press`, `clickel`, `click <x> <y> [cmd|shift|opt|ctrl|middle]`, `type`, `key`; see
  `scripts/ax.swift`). `find` matches across windows: pick the element inside the window you mean by its frame.
- Prefer AX ids (`AccessibilityIdentifiers` in `macOS/UITests/Common/XCUIApplicationExtension.swift`) over
  titles, and titles over coordinates.
- Take the user's real path: menus, clicks, shortcuts. `web` reads back and never stands in for the action
  being proved. Never debug setters or internal URLs.
- Confirm every end state with a second, independent read. An action that returned ok proves nothing.
  `ax press` prints AX's code, which isn't the outcome: a press on the tab bar's new-tab button reports
  `-25200` and still opens the tab.
- Screenshots only for visual or layout claims: `verify.sh shot <topic> NN-<step>`, the app's window only;
  it refuses when another app is in front. Capture before and after the action.
- Shortcuts inside an `NSPopover` (Esc, Return) only fire when its window is key: test them explicitly.
- Deadlines: `verify.sh wait <topic> <seconds>`, then read AX state and logs.
- `verify.sh logs <topic>`: the run's `[VERIFY]` lines to `log.txt`, the app's log since launch to `app.log`.

### Telemetry

Debug builds send nothing: pixels are dry-run and logged on subsystem `PixelKit`
(`👾[<freq>-Fired] <name> [params]`, or `Skipped` when a frequency rule suppressed it); wide events go
to `wide-event-validation-log.jsonl`. Setup fires pixels too, so:

```
verify.sh mark <topic>                       # right before the action under test
verify.sh expect-pixel <topic> <name> [key=value…] [--timeout 10]
verify.sh expect-no-pixel <topic> <name> [--within 3]
verify.sh expect-wide-event <topic> <feature> [--status SUCCESS]
```

- Without a mark they fail. A dead pixel stream fails (exit 2); it never passes `expect-no-pixel`.
- Select by name and order, never by the params you expect. `Skipped` is not `Fired`; a failed
  `expect-pixel` lists the skipped ones.
- Raw payloads are kept: `pixels.ndjson`, `pixels.json`, `wide-events.json`.

## 6. Cleanup

1. `verify.sh cleanup <topic>`: writes `app.log` and `manifest.json` (revision, dirty flag, source
   fingerprint, build hashes, launch args, flags and defaults, macOS and Xcode versions, skill hash,
   rerun command), stops the pixel stream, kills this topic's build by PID, deletes every default
   it wrote, and fails while `[VERIFY]` lines are left in the checkout.
2. Remove those `[VERIFY]` lines and run cleanup again until it passes.
3. Confirm the evidence folder still exists.

## 7. Report

Write `report.md` in the evidence folder as one PR verification scenario, in this order:

```
## Verified
<one line a reviewer reads: what the user sees, under which conditions>

## Evidence
<relative links: screenshots, log.txt, app.log, pixels.json, wide-events.json>

## Outcome
Passed: <each check, with its evidence line>
Failed: <each check>
Problems: <cleanup or evidence failures; never hide them>

## Details
revision <sha> (dirty: yes/no) · flags · language · automation on/off · macOS · rerun command
(from manifest.json)

## Unverified
- <entry point or claim> — <why>
```

- **Pass** needs at least one passing check, no failing check, and the app still running at the end.
- A problem before the action under test (build, doctor, launch, readiness, a permission prompt) is
  **INCONCLUSIVE**: it couldn't tell either way, which is never a pass.
- An entry point you couldn't drive goes to Unverified, never "verified through another path".
- Never fall back to "the code looks right".

Tell the user the passed, failed and unverified behavior, the revision, the rerun command and the
evidence folder. Look at the screenshots before claiming anything about appearance.

## Stop and ask the user

(When a harness runs this unattended: don't stop. Mark the claim Unverified with the reason and
return.)

- A TCC prompt appears (Screen Recording, Accessibility, Notifications, etc.).
- On this Mac, nothing in the session holds the Accessibility and Screen Recording grants: ask the user, or
  offer a VM.
- A sign-in, payment or subscription purchase is required.
- The build fails in code you didn't touch.
- The same claim stays unverified after 2 attempts. Then question the premise; don't retry blindly.

## Running in a VM

```
verify.sh vm <topic> [vm-1|vm-2|auto]      # before flag/set-default/build
```

- Reserves a free VM (a lock per VM in `~/.ddg-verify-macos/.vm-locks/`), wipes the Debug app's data
  there (the keychain stays) and copies `ax`. `cleanup` releases it. `NO VM FREE` lists who holds each lock.
- `flag` and `set-default` write the VM's defaults. `build` compiles on this Mac (one build at a time across
  topics: they share DerivedData), copies the app with `tar` and checks its hashes, launches it in the VM and
  presses Debug → Skip Onboarding (pass `--keep-onboarding` to test onboarding).
- `ax`, `shot` and `logs` run in the VM. Pixels stream back over ssh; wide events are mirrored with `tail -F`;
  `web` goes through an ssh tunnel. `doctor` compares the VM's process start with the VM's launch time.
- Every ssh call goes to the local network, which Claude Code's sandbox blocks: run `verify.sh` outside it.
- `NOT LAUNCHED` in a VM is usually AMFI: that VM's Provisioning UDID isn't in the development profile
  (VM-SETUP.md step 4). `NOT READY` with no window: a keychain dialog waits in the VM; ask the user to
  answer it (VM-SETUP.md step 5).
- A window can be frontmost without keyboard focus after the VM boots: `clickel` the field before `type`.

## Feature map

`features/` holds one file per area, with a fixed contract (see `features/README.md`). Update the
file when a run teaches something new about reaching or observing the feature.
