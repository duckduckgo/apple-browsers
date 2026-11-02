---
name: verify-ios
description: Prove a change works in the DuckDuckGo iOS browser built from this worktree, on dedicated iPhone and iPad simulators, by running a short proof that acts like a user and checks the result, pixels and wide events. Produces reproducible evidence for a pull request. Invoke explicitly after implementing an iOS change, or to investigate iOS app behavior.
disable-model-invocation: true
---

# verify-ios

Proves iOS behavior in the real app. You write a **proof**: a short Python file for this one change, saved with its
evidence and never committed. `prove` checks it, runs it on each device, captures evidence, and always cleans up.

```bash
V=.claude/skills/verify-ios/bin/verify-ios      # from the worktree root; every example below uses $V
```

**How it gets used.** Only when someone asks for it: agents never pick it on their own (`disable-model-invocation`),
and nothing in the repo's agent instructions points to it. With AStack's `auto`, name it when you start, for example
"/auto fix … and use verify-ios to verify" (auto honours an explicitly named driver). Outside auto, invoke
`/verify-ios` directly.

Before writing a proof, read the feature files in [features/](features/README.md) for what you are changing: they
list the real ids, the iPhone/iPad differences and the app quirks that make a naive proof fail.

## Layers

```
proof (Python, throwaway, in the evidence folder)
  └─ library  lib/verify_ios: steps.py (DuckDuckGo steps), harness.py (the `ios` handle, assertions, prove)
       ├─ driver.py → runner/ (Swift XCUITest runner, generic: find, tap, type, wait, alert…) → the app's UI
       └─ web.py → the app's AutomationServer → page content (read-back and setup only)
bin/verify-ios: command line over the same library, for setup and for exploring by hand
```

Only `driver.py` knows how the UI is driven. A different driver means a new class with the same methods, which must
pass `tests/must_fail.py` before it is used.

## Check it works here

```bash
$V selftest                    # both devices; --devices iphone for a quicker check
```

Sets up the simulators, builds the app and runner if the build isn't current (a first build takes 3–20 minutes), runs
the tool's tests, the "must fail" trust checks and one worked proof on each device, and confirms nothing was left
running. Ends with `"ok": true` and the report paths, or names the step that failed and why. Run it on a new Mac, a
new checkout, or after an Xcode update.

## First time in a worktree

```bash
$V --device iphone setup && $V --device ipad setup   # this worktree's own simulators (created once, then reused)
$V build                                              # app (3–20 min) + runner (~20 s); rebuild the app after app changes
```

`build` targets a concrete simulator: a `generic/platform=iOS Simulator` build fails in the WebKit-workaround phase.
One app build serves both devices. `build` records a fingerprint of the source it built from (HEAD plus every
uncommitted change outside `.claude/`); `prove` refuses to run (exit 2) when the source has changed since, so a proof
can't pass against a stale build. After changing app code, `build --app-only`.

## Write and run a proof

```bash
proof=$($V --json new-proof fire-clears-tabs | python3 -c 'import json,sys; print(json.load(sys.stdin)["proof"])')
# edit "$proof", then:
$V check "$proof"                      # compile + import + shape; touches no device (fast)
$V prove "$proof"                      # every device in its DEVICES; or --devices iphone
```

A proof file:

```python
"""The Fire button closes all tabs and clears site data."""   # required: what it proves, user-visible
from verify_ios import steps

DEVICES = ["iphone", "ipad"]   # default: both
LIVE = []                      # live services it depends on, e.g. ["duck.ai"]; empty = local fixture / app only
FLAGS = {}                     # remote feature flags to pin for this proof (env.PINNED_FLAGS are always pinned)

def run(ios):
    steps.fresh_start(ios)                         # reinstall + launch: one blank tab, address bar not focused
    steps.open_fixture(ios, ios.token("fire"))     # through the address bar, like a user
    steps.new_tab(ios)                             # a second tab: "closes all tabs" needs more than one
    steps.expect_tab_count(ios, 2)
    steps.dismiss_address_bar(ios)
    ios.mark()                                     # telemetry counts from here, not from setup
    steps.fire(ios)
    steps.expect_tab_count(ios, 1, 10)             # 2 → 1
    ios.expect_no_web_page()                       # the remaining tab is a blank new-tab page
    ios.expect_pixel(f"m_forget-all-executed_daily_ios_{ios.form_factor}")
    ios.expect_wide_event("data-clearing", status="SUCCESS")
```

`examples/` has one worked proof per feature (t1–t9); start from the closest one.

**When a run passes:** the proof returned, recorded at least one passing check and no failing one (a failed check
you caught still fails the run), and the app was still in the foreground at the end. A problem before the proof's
own steps (stale build, launch, identity check, telemetry capture) is an error (exit 2), not a product failure.

What `ios` gives you (`lib/verify_ios/harness.py`):
- **Act:** `tap`, `long_press`, `type(locator | "-", text, submit=)`, `clear`, `key("cmd+t")`, `swipe`, `scroll_to`,
  `alert("accept", button=)` (an alert with more than two buttons needs `button=`).
- **Read:** `get(locator)`, `find`, `exists(locator, timeout)` (False only when absent; refusals raise), `wait`,
  `snapshot()`, `focused()`, `url()` (fails when the tab shows no web page), `page_url()` (None then), `eval(js)`,
  `handles()`.
- **Assert (they wait):** `expect_url_contains`, `expect_no_web_page`, `expect_web_text(css, value)`, `expect_visible`,
  `expect_hidden`, `expect_keyboard(shown=)`, `expect_focused`, `expect_not_focused`, `expect_no_alert`,
  `eventually(what, fn)`, `check(what, ok)`.
- **Telemetry (after `mark()`):** `mark()` just before the action under test, then `expect_pixel(name, params=)`,
  `expect_no_pixel(name)`, `expect_wide_event(feature, status=)`. Without a mark they fail: setup fires pixels too.
- **Evidence:** `shot(name)`, `note(text)`, `unverified(what, why)`.
- **Setup only:** `reset()`, `navigate(url)`, `fixture_url(token)`, `token(prefix)`.
- **Capture conditions:** `appearance("dark")`, `text_size("accessibility-large")` (see `Ios.TEXT_SIZES`; `large` is
  the iOS default), `rotate("landscapeLeft")` (fails if the app's window didn't follow), `fixed_status_bar()` (9:41,
  full battery and signal). Each is undone after the proof and recorded per device in the manifest and report.
  `fresh_start` always begins from light mode, default text size, portrait and a live status bar, even if an earlier
  run was killed before its undo ran. Text size reaches web pages on their next load. Use these so screenshots compare
  (visual-parity needs the same conditions on both sides).
- **Undo:** `on_cleanup(what, fn)` for anything the proof changes outside the app (simulator settings): undo steps
  run in reverse after the proof, pass, fail or cancel, and a failing one is reported under Problems. `reset` only
  reinstalls the app; simulator-wide settings survive it. Steps that change them register their own undo
  (`steps.reset_location_permission`, `steps.set_simulated_location`).
- Every action's `after` is checked: an action that changed nothing in the UI tree is listed under Warnings in the
  report, so you can see where the proof's own reads must carry the proof.

Shared steps (`lib/verify_ios/steps.py`) hold the app's quirks once: `fresh_start`, `open_url`, `open_fixture`,
`dismiss_address_bar`, `new_tab`, `switch_to_tab`, `close_current_new_tab`, `tab_count`, `expect_tab_count`, `fire`,
`open_duckai_new_chat`, `send_duckai_prompt`, `read_duckai_answer`. Add a step when a second proof needs the same
quirk handled; keep steps to generic actions plus feature-map ids, and document every quirk in the feature map.

Locators: `id=searchEntry`, `label="Fire Solid 24"`, `role=button label="New Tab"`, `text="Done"`, `contains="token"`,
plus `nth=<n>` when several match (otherwise the action fails with AMBIGUOUS; it never guesses). `web:css=#token` and
`web:text="…"` only read.

### Proof rules

- Act through the user's path for the behavior under proof: the address bar, buttons, menus, hardware keys.
  `navigate` / `eval` set up or read back; they never stand in for the action being proved.
- Confirm every end state with a second, independent read (URL, page value, tab count, focus, pixel). An action
  returning ok is not proof.
- Telemetry: `mark()` right before the action; select by name and emission order, never by the params you expect;
  every raw payload is kept (`pixels.json`, `wide-events.json`). A pixel reported `Skipped` (frequency rule) is not
  `Fired`; PixelKit logs Skipped lines without the `_ios_phone`/`_ios_tablet` suffix, and a failed `expect_pixel`
  lists them. `reset` clears daily pixel state. Debug builds send nothing: pixels are dry-run, wide-event POSTs are
  mocked. A dead pixel stream fails the assertion; it never passes `expect_no_pixel`.
- Feature flags: proofs must not depend on the live privacy configuration. Every launch pins `env.PINNED_FLAGS`
  (`newTabPageRedesign: true`, which the iPhone ids assume); a proof pins more with `FLAGS`. The manifest records them.
- Use a fresh token per run; the fixture page (`fixture/`) shows it, writes localStorage, and has a link, a disabled
  button, two buttons sharing one label, a location button and a long list. The simulator reaches the host at
  `127.0.0.1`.
- `navigate` fails on the new-tab page (no web view): load the first page through the address bar.
- Declare every live service in `LIVE`. The report flags any non-local host the proof saw that `LIVE` doesn't name.

## Evidence and report

`prove` writes, per attempt, `<state dir>/evidence/<stamp>-<name>-<id>/` (`$V info` prints the state dir):
`proof.py`, `manifest.json` (git revision and dirty flag, the build's source fingerprint and sha256, the running
binary's sha256 per device as verified at launch, pinned flags, skill sha256, Xcode, simulators, live services and
live hosts seen, rerun command), `report.md`, and per device `transcript.jsonl`, your screenshots, `final.png`,
`final-snapshot.txt`, `pixels.json`, `pixels.ndjson` (raw), `wide-events.json`, `result.json`.

An attempt folder is used once: a proof inside a folder that holds anything else is copied to a new folder.

With an AStack show-me-your-work decision log, pass `--decision-log <path to decisions.tsv>` to `new-proof` and
`prove`: attempt folders then go in `proofs/` next to the log, so the log can link them, and the manifest records it.

Report to the user from `report.md`: **passed, failed and unverified** behavior per device, whether the evidence used
live services or only the local fixture, the revision, the rerun command, and links to the evidence. Look at the
screenshots before claiming anything about appearance. The report's **Problems** section lists cleanup and evidence
failures; pass them on, never hide them.

Exit codes: `0` pass · `1` a check failed (the product, or the proof) · `2` error: setup, stale build, driver, a proof
rejected by `check`, or a pass with cleanup/evidence problems · `3` not supported · `75` device busy (another proof
holds it; finish that one, never delete its lock) · `130` cancelled. When setup stays blocked after a routine fix, the
report says **INCONCLUSIVE**: the run couldn't tell either way, which is never a pass.

## Exploring by hand

Use the command line to find ids and try things before writing the proof. Commands are refused (exit 75) while a
proof owns the device.

```bash
$V --device iphone launch                  # install if the build changed, start the runner, launch, wait for ready
$V snapshot [--web]                        # native tree (+ page summary): find ids here
$V find|get|wait '<locator>' [--state visible|exists|enabled|hidden]
$V tap|long-press|type|key|swipe|alert …   # same actions and refusals as proofs
$V web url | eval '<js>' | navigate <url>
$V capture screenshot --name step
$V doctor                                  # read-only: simulator, build identity, runner, web channel
$V cleanup [--all] [--shutdown] [--delete-sims]
```

`launch` is ready when AutomationServer `/contentBlockerReady` is true **and** `searchEntry` exists (no fixed sleeps),
and fails if the running binary is not this worktree's build.

## Trust guarantees (keep them)

- The build is this source: `build` records the source fingerprint, `prove` refuses a stale build, and `doctor` and
  `launch` compare the full sha256 of the running binary with the build product; a hash that can't be computed never
  matches.
- Missing, ambiguous, disabled and covered targets are refused; typing with nothing focused is refused; an action
  whose matches changed while it waited is refused; a refused action changes nothing. `wait visible` means on screen
  and hittable. Nothing is observed or acted on while the app isn't in the foreground (`APP_NOT_RUNNING`), so "gone"
  and "not focused" can't pass on a crashed app.
- Every action reports what changed (`after`); actions that changed nothing are listed in the report.
- A pass needs a passing check, no failing check, and the app in the foreground at the end.
- Telemetry counts only after `mark()`, from a stream that is checked to be alive.
- Isolation: per-worktree simulators (`verify-ios-<key>-iphone|ipad`, iPhone 17 Pro / iPad Pro 11-inch (M5),
  iOS 27.0), ports, state and evidence under `~/.ddg-verify-ios/<worktree>-<hash>/` (`VERIFY_IOS_HOME` overrides the
  root). The runner answers only to this worktree's token. Every command that changes a device holds its lock for its
  whole duration; `build` and the shared fixture server need both locks.
- Cleanup signals only processes whose recorded identity (pid + start time + command) still matches, checked again
  right before each signal; survivors stay recorded and are reported. It never deletes evidence or builds.

After changing the runner, the driver or the library, run both test suites:

```bash
python3 -m unittest discover -s .claude/skills/verify-ios/tests -p 'test_*.py'   # no simulator
$V prove .claude/skills/verify-ios/tests/must_fail.py                                # every refusal, both devices
$V prove .claude/skills/verify-ios/examples/*.py                                     # the worked proofs still pass
```

## Known environment issues (not product bugs)

- The iOS 27.0 simulator may never deliver a location fix (geolocation error 3). Location proofs cover the
  permission sheet and the deny path; record the allow path as unverified.
- A heavily loaded Mac (load average far above the core count) makes launches and actions take minutes and can fail
  waits. Check `uptime` before treating a timeout as a product bug.
- The runner skips XCTest's animation-idle wait through a private swizzle (as WebDriverAgent does). If an Xcode
  update breaks it, long-presses take ~60 s; they don't become wrong.
- A fresh Mac may ask a human once to allow UI automation.

## Files

| path | what |
|---|---|
| `bin/verify-ios` | command line: setup, build, new-proof, check, prove, explore, doctor, cleanup (`-h`) |
| `lib/verify_ios/` | library: `harness.py` (ios handle, prove, report), `steps.py`, `telemetry.py`, `device.py`, `driver.py`, `web.py`, `env.py` |
| `lib/vrunner_start.sh` | start one runner and report its pids (called by the driver, which also stops it) |
| `lib/ios_identity.sh` | running-binary sha256 vs build (called by doctor) |
| `runner/` | Swift XCUITest runner, XcodeGen spec and generated project; regenerate with `cd runner && xcodegen generate` |
| `examples/` | worked proofs t1–t9 |
| `tests/` | `test_tool.py` (no simulator), `must_fail.py` (refusals and build identity, as a proof) |
| `fixture/` | local test pages |
| `features/` | the feature map |

Swift under `runner/` must pass `mint run swiftlint lint --strict --force-exclude .claude/skills/verify-ios/runner/Sources`.
Keep the runner's fixes: the animation-idle swizzle, the `record(_:)` override, the alert handler (app + SpringBoard),
loopback-only binding and the token check.

Keep [features/](features/README.md) honest as the app changes: `/maintain-verification-skill`.
