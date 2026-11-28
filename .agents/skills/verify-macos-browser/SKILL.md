---
name: verify-macos-browser
description: Prove a macOS browser change works by driving the real debug app built from this worktree (CI configuration), on this Mac or in a local VM, and capturing accessibility, pixel, wide-event and log evidence. Use before opening a PR or to reproduce a bug.
disable-model-invocation: true
---

# Verify macOS Browser

Prove the change on the running app, not by reading code. A proof is: the action, the resulting
state, and a second, independent read that shows it (AX state, page URL, a log line, a pixel). No
evidence, no verdict.

**How it gets used.** Agents don't pick this skill on their own: name it in the task, or invoke `/verify-macos-browser`.

## 0. Before you start

- **Ask the user where to run it**, unless they already said:
  - **In a VM** (`--target vm`, or `vm-1`/`vm-2`): never touches their screen. Offer it when one is set up
    (`ssh vm-1 true` works); otherwise mention `VM-SETUP.md` once.
  - **On this Mac** (`--target mac`): drives their screen; tell them and wait for an OK. The process running it
    needs the Accessibility and Screen Recording grants; an agent's shell often has neither.
- **New Mac, checkout, Xcode or macOS, or a new VM?** `bin/verify-macos-browser selftest [--target vm-1|vm-2|mac]`
  checks each step in order and names the first that fails, why, and the fix. A new Mac also needs the signing
  assets once (see Signing).
- Read `features/README.md`, then `features/<feature>.md` for the area you're touching. Every entry point your
  change touches needs its own check or an `unverified` line.
- For state, timing or geometry claims, add temporary logs with one tag (`os.Logger` with public interpolation;
  `NSLog` doesn't reach the unified log): `Logger(subsystem: "verify", category: "verify").notice("[VERIFY] …")`.
  They land in `log.txt`; remove every `[VERIFY]` line before commit (cleanup fails while any is left).

## 1. Write and run a proof

```
V=.agents/skills/verify-macos-browser/bin/verify-macos-browser   # from the worktree root
$V new-proof cmd-t-tab [--evidence-dir <dir>]   # prints <dir>/<stamp>-<name>-<id>/proof.py; edit it
$V check <proof>                                 # compile, shape, FLAGS; no app, no build
$V prove <proof> --target vm-1 [--evidence-dir <dir>]   # vm, vm-1, vm-2 or mac
```

**Copy the closest example.** `examples/` are worked proofs of the harness, kept passing, not recipes:
`t1_launch_doctor`, `t2_tabs` (Cmd+T, Cmd+W, tab count), `t3_fixture_page` (local page, no live service),
`t4_pixel` (`mark`, `expect_pixel`, `expect_no_pixel`), `t5_dark_window` (`CONDITIONS`), `t6_duckai_tab` and
`t7_duckai_sidebar` (see `features/`). The docstring is the claim
(report.md's Verified line); the `new-proof` template explains the rest.

**Conditions.** So screenshots compare between runs and with `--base`, declare
`CONDITIONS = dict(appearance="dark", window=(40, 60, 1280, 800), language="de", locale="de_DE")`: each is set, read
back, recorded and undone after the proof. Appearance: a VM's system setting, and every VM run starts light; on this
Mac, the app's own theme setting, and an undeclared run keeps the engineer's.

`prove` reserves the VM, pins `FLAGS`, builds (incremental; uncommitted edits included), launches as an internal user
(en-US by default), skips onboarding in a VM, runs `doctor`, runs the proof, takes `final.png`, writes the logs and
`report.md`, and always cleans up: on pass, fail and Ctrl-C. A proof is throwaway: it stays with its evidence,
never in the repo (only `examples/` are kept).

What `mac` gives you (`scripts/harness.py`):
- **Act:** `press(target)` (AX press), `click(target)` (real click), `type(text)`, `key("cmd+t")`. A target is an AX
  id (prefer `AccessibilityIdentifiers` in `macOS/UITests/Common/XCUIApplicationExtension.swift`) or a title;
  `nth=` picks one of several. It never guesses.
- **Read:** `find(target)`, `tab_count()` (the front window's), `url()`.
- **Assert (they wait):** `expect_tab_count(n)`, `expect_url_contains(text)`, `eventually(what, fn)`, `check(what, ok)`.
- **Telemetry:** `mark()` right before the action, then `expect_pixel(name, params=)`, `expect_no_pixel(name)`,
  `expect_wide_event(feature, status=)`. Name a pixel as it fires: a `.daily` one fires as `<name>_daily`, so a
  negative check on the plain name can't fail. Pick a negative check the action could plausibly trigger.
- **Evidence:** `shot(name)`, `note(text)`, `unverified(what, why)`. **Setup only:** `navigate(url)`.

Proof rules:
- Act through the user's path: menus, clicks, shortcuts. `url()` reads back; `navigate` sets up; neither
  stands in for the action under proof. Never debug setters or internal URLs.
- Pin every flag the behavior depends on. Never rely on the live privacy configuration.
- Select pixels by name and order, never by the params you expect. `Skipped` is not `Fired`.
- Shortcuts inside an `NSPopover` (Esc, Return) only fire when its window is key: test them explicitly.

**Fixture pages and LIVE.** Prefer a local page to a live site: `mac.navigate(mac.fixture_url(mac.token("x")))`
(`AUTOMATION = True`) opens `fixture/index.html`, served for this run only on 127.0.0.1 (in a VM, via an ssh tunnel to
its loopback). It shows the token, writes localStorage, links to `target.html` and a download, and has a disabled
button, two buttons sharing a label and a long list. Name every live service the proof needs in `LIVE`. With `AUTOMATION`, the report
lists the hosts the app loaded (navigated, read by `url()`, and the front tab's resources at the end; not other tabs
or the app's own requests), says "no live hosts observed" or "live: …" (hosts are read at `navigate()`, `url()` and the last page), and flags in bold any host `LIVE` doesn't cover.

**Before and after (bug fixes).** Show the bug on the base revision with the same proof, then the fix. Wrap the
checks that show the bug in `with mac.on_base("fail"):`; every other check must come out the same on both.

```
$V prove <proof> --target vm-1 --base "$(git merge-base HEAD origin/main)" [--evidence-dir <dir>]
```

It proves the base in a worktree kept at `~/.ddg-verify-macos/base/<sha12>` (its own DerivedData: the first build is
cold, 5 to 20+ min, then incremental; each `--base` run removes the others unused for 3 days, `$V clean-base` all of
them), then this checkout, with
the same VM, flags and conditions (any that differ: INCONCLUSIVE), each from a reset. On the base a check declared `fail` is recorded and the proof carries on; any
other error there is INCONCLUSIVE. **PASS** needs this checkout to pass and the base to do what each check declares,
with at least one declared `fail`; a `fail` check that passes on the base is **FAIL**: the proof doesn't reproduce
the bug. `report.md` shows each check and screenshot Before | After; each run's evidence is in `base/` and `change/`.
Checks match across the runs by name, with `token()` values and local ports left out. On the base a `FLAGS` entry
its revision doesn't define is skipped, and the report says so. Different macOS versions: INCONCLUSIVE. A base older than the switch to the CI configuration writes no wide event
validation log (see Signing), so `expect_wide_event` can't pass there.
An element the bug removes can't be pressed on the base (an action error, INCONCLUSIVE): declare that with
`eventually("…", lambda: mac.find(x))` inside `on_base("fail")` and press it only after.
By hand: `git worktree add --detach <dir> <ref>`, then `$V prove <proof> --target vm-1 --checkout <dir>`.

## 2. Evidence and report

**Where evidence goes.** Each run writes one attempt folder, `<stamp>-<name>-<id>/`, in `--evidence-dir <dir>`
(pass the directory your tooling publishes from) or by default in `~/.ddg-verify-macos/`
(`VERIFY_MACOS_HOME` overrides it). A directory inside a git checkout is refused (exit 2), symlinks resolved: this
repo is public. A finished attempt is never overwritten. `prove` without `--evidence-dir` keeps a proof made with `new-proof --evidence-dir <dir>` in that directory; the
manifest and rerun command record it.

The attempt folder holds `proof.py`, `report.md`, `manifest.json` (revision, dirty flag, source fingerprint, build and running-binary
hashes, launch args, flags, macOS and Xcode, VM, skill hash, checks, rerun command), your screenshots,
`final.png`, `app.log`, `log.txt`, `pixels.json`, `wide-events.json`, `transcript.jsonl` (every `verify.sh` call),
and `recording.mp4`, from after launch to `final.png`: a VM's whole screen, or on this Mac only the app's window,
cut where another app came in front or the window moved, resized or closed (Problems: "cut short"). It is re-encoded to at
most 2048 pixels wide, 30 fps and 3 Mbit/s (`scripts/shrink.swift`), about 20 MB a minute, so it uploads. `prove --no-video` turns it off; the report says so.

`report.md` is one PR verification scenario: **Verified** (the docstring), **Evidence**, **Outcome** (label,
passed, failed, problems, warnings, notes), **Details** (revision, build and running binary, target and its
macOS, flags, conditions, rerun), **Unverified**. The verdict comes from what ran, by fixed rules:
- **PASS** (exit 0): at least one passing check, no failing check, the app still running at the end.
- **FAIL** (exit 1): a check failed, or the app was gone at the end.
- **INCONCLUSIVE** (exit 2): setup broke (VM, build, doctor, launch, readiness), an action or read failed, or
  nothing was checked. Never a pass. Ctrl-C exits 130; the report is still written.
- **Problems** (screenshot or recording failed, dead pixel stream, VM not released, cleanup failed) are always listed;
  a pass with problems exits 2.

Report to the user from `report.md`: passed, failed and unverified behavior, the revision, the rerun command and
the evidence folder. Look at the screenshots before claiming anything about appearance, and watch the recording
before claiming what the app did.

**Publishing for a PR.** Upload the whole attempt folder: `report.md` links its screenshots and telemetry by
relative path. Paths in `report.md` and `manifest.json` show your home folder as `~`; `app.log`, `log.txt` and
`transcript.jsonl` are raw and may name local paths, so check them before sharing. In the PR's verification
section, link `report.md` as the entry point, with the verdict, and the screenshots that show the claim. An entry point you
couldn't drive is `unverified`, never "verified through another path". Never fall back to "the code looks right".

**Run it in a subagent** briefed with the claim, target and evidence folder; the lead reads `report.md` and the screenshots.

## Exploring by hand: `verify.sh`

The low-level layer `prove` calls, for finding ids and trying steps before writing the proof:

```
S=.agents/skills/verify-macos-browser/scripts/verify.sh
$S vm <topic> [vm-1|vm-2|auto]; $S flag <topic> <Case> on|off; $S build <topic> . [--automation]
$S doctor <topic>; $S ax <topic> dump|find|press|clickel|click|type|key …; $S shot <topic> <name>; $S record <topic> start|stop
$S mark|expect-pixel|expect-no-pixel|expect-wide-event <topic> …; $S web <topic> url; $S cleanup <topic>
```

A `<topic>` is 14 characters at most (`prove` derives one): a longer app name quits at launch until #8345 lands.

Call it as a single command (one permission rule covers it). Exit codes: `0` ok, `1` a check failed, `2` error.
Other state: `set-default <topic> <key> <type> <value>` before `build` (most preferences are read at launch). Never use
`UITEST_MODE=1`. On a build failure, report the first error; after switching branches, "type X has no member Y"
for code that is there is a stale module in DerivedData: move it out and rebuild. Don't build in Xcode meanwhile.

## Trust guarantees (keep them)

- The build is this source: `doctor` refuses a changed source or binary, or an older process.
- Missing, ambiguous (unless `nth=`), disabled and off-window targets are refused; typing with nothing focused that
  takes text is refused; a refused action changes nothing.
- Nothing is read or acted on while the app isn't running and in front (`APP NOT RUNNING`, `NOT FRONTMOST`), so
  "gone" can't pass on a crashed app or a popover closed by losing the front.
- Every action reports whether it changed the accessibility tree; no-ops are listed under Warnings.
- Telemetry counts only after `mark()`, from a stream checked to be alive.
- Cleanup signals a recorder or log stream only while its recorded identity (pid, start time, command) still matches;
  the app is quit by its name, which carries this run's topic.

Changed the harness, `verify.sh`, `vhelp.py` or `ax.swift`? Run `tests/`, then
`$V prove .agents/skills/verify-macos-browser/tests/must_fail.py --target vm-1` (PASS: every refusal it covers still refuses;
the `--base` refusals are covered by `tests/test_base.py`),
then each `examples/*.py` must PASS.

## Running in a VM

- `vm` reserves a free VM (a lock per VM in `~/.ddg-verify-macos/.vm-locks/`), resets the app, its data,
  Downloads, pasteboard (keychain kept) and copies `ax`. `cleanup` releases it. `NO VM FREE` lists who holds each lock.
- `build` compiles here (one build at a time), copies the app with `tar`, checks its hashes, launches it in the VM
  and presses Debug → Skip Onboarding (`--keep-onboarding` to test onboarding). Pixels stream back over ssh.
- ssh goes to the local network, which Claude Code's sandbox blocks: run it unsandboxed.
- `NOT LAUNCHED` in a VM is usually AMFI: the app isn't signed with Developer ID (see Signing).
  `NOT READY` with no window: a keychain dialog waits in the VM (VM-SETUP.md step 4).

## Signing

`build` uses the **CI** configuration, not Debug: a debug build (`DEBUG` in the app target, `.debug` bundle id and
app groups, the same app data as Debug) signed with Developer ID and the match profile
`match Direct com.duckduckgo.macos.browser.debug macos`. That profile has no device list, so the app runs on any Mac
and in any VM with no device registration. The build isn't notarized. It has no quarantine attribute (built here,
copied to a VM with `tar` over ssh), so Gatekeeper doesn't assess it.

- **Setup, once per Mac:** `cd macOS && bundle exec fastlane sync_signing_ci` (read-only match). It needs read access
  to the match repo and its passphrase, and installs the Developer ID Application certificate and private key in
  your login keychain. `selftest` checks the result ("build signed with Developer ID").
- Xcode builds Swift packages in release under CI. `build` sets `SPM_FORCE_DEBUG=1`, as CI does, so AppKitExtensions
  (`isDebugBuild`: pixel dry run, AutomationServer, staging services) and WideEvent (the validation log) keep
  `DEBUG`. Other packages' `#if DEBUG` code isn't compiled: `callingSymbol()` in Common, the 2-minute privacy
  configuration refresh (30 minutes here), pixels' `test=1` (dry run, so none are sent).
- The flag reaches a package only when Xcode evaluates its manifest, and a DerivedData keeps manifests as first
  evaluated. So `build` uses its own `.build/DerivedData-verify` (the main checkout's, shared by worktrees), never
  Xcode's, and its first build is a full build. A build that compiles AppKitExtensions without `DEBUG` stops with
  `PACKAGES NOT DEBUG`: remove that DerivedData. Don't point `VERIFY_DERIVED_DATA` at one Xcode uses.

## Stop and ask the user

(When a harness runs this unattended: don't stop. Mark the claim Unverified with the reason and return.)

- A TCC prompt appears, or on this Mac nothing in the session holds the grants: ask, or offer a VM.
- A sign-in, payment or subscription purchase is required.
- The build fails in code you didn't touch.
- The same claim stays unverified after 2 attempts. Then question the premise; don't retry blindly.

## Feature map

`features/` holds only maintained files, each with a fixed contract (see `features/README.md`); today Duck.ai's tab
and sidebar. Update the
file when a run teaches something new about reaching or observing the feature.
