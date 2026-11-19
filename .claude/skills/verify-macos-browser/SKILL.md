---
name: verify-macos-browser
description: Prove a macOS browser change works by driving the real Debug app built from this worktree, on this Mac or in a local VM, and capturing accessibility, pixel, wide-event and log evidence. Use before opening a PR or to reproduce a bug.
disable-model-invocation: true
---

# Verify macOS Browser

Prove the change on the running app, not by reading code. A proof is: the action, the resulting
state, and a second, independent read that shows it (AX state, page URL, a log line, a pixel). No
evidence, no verdict.

**How it gets used.** Agents don't pick this skill on their own (`disable-model-invocation`), so name it when you
start a task ("… and verify it with verify-macos-browser"), or invoke `/verify-macos-browser`.

## 0. Before you start

- **Ask the user where to run it**, unless they already said:
  - **In a VM** (`--target vm`, or `vm-1`/`vm-2`): never touches their screen. Offer it when one is set up
    (`ssh vm-1 true` works); otherwise mention `VM-SETUP.md` once.
  - **On this Mac** (`--target mac`): drives their screen; tell them and wait for an OK. The process running it
    needs the Accessibility and Screen Recording grants; an agent's shell often has neither.
- Read `features/README.md`, then `features/<feature>.md` for the area you're touching. Every entry point your
  change touches needs its own check or an `unverified` line.
- For state, timing or geometry claims, add temporary logs with one tag (`os.Logger` with public interpolation;
  `NSLog` doesn't reach the unified log): `Logger(subsystem: "verify", category: "verify").notice("[VERIFY] …")`.
  They land in `log.txt`; remove every `[VERIFY]` line before commit (cleanup fails while any is left).

## 1. Write and run a proof

```
V=.claude/skills/verify-macos-browser/bin/verify-macos-browser   # from the worktree root
$V new-proof cmd-t-tab [--evidence-dir <dir>]   # prints <dir>/<stamp>-<name>-<id>/proof.py; edit it
$V check <proof>                                 # compile, shape, FLAGS; no app, no build
$V prove <proof> --target vm-1 [--evidence-dir <dir>]   # vm, vm-1, vm-2 or mac
```

**Copy the closest example.** `examples/` holds worked proofs of the harness, kept passing, not feature recipes:
`t1_launch_doctor`, `t2_tabs` (Cmd+T, Cmd+W, tab count), `t3_fixture_page` (fixture page and link, no live service),
`t4_pixel` (`mark`, `expect_pixel`, `expect_no_pixel`). The docstring is the claim (report.md's Verified line);
`FLAGS`, `LIVE` and `AUTOMATION` are explained in the `new-proof` template.

`prove` reserves the VM, pins `FLAGS`, builds (incremental; uncommitted edits included), launches in en-US as an
internal user, skips onboarding in a VM, runs `doctor`, runs the proof, takes `final.png`, writes the logs and
`report.md`, and always cleans up: on pass, fail and Ctrl-C. A proof is throwaway: it stays with its evidence,
never in the repo (only `examples/` are kept).

What `mac` gives you (`scripts/harness.py`):
- **Act:** `press(target)` (AX press), `click(target)` (real click), `type(text)`, `key("cmd+t")`. A target is an AX
  id (prefer `AccessibilityIdentifiers` in `macOS/UITests/Common/XCUIApplicationExtension.swift`) or a title;
  several matches are refused unless you pass `nth=`. It never guesses.
- **Read:** `find(target)`, `tab_count()`, `url()`.
- **Assert (they wait):** `expect_tab_count(n)`, `expect_url_contains(text)`, `eventually(what, fn)`, `check(what, ok)`.
- **Telemetry:** `mark()` right before the action, then `expect_pixel(name, params=)`, `expect_no_pixel(name)`,
  `expect_wide_event(feature, status=)`. Without a mark they are refused: setup fires pixels too.
- **Evidence:** `shot(name)`, `note(text)`, `unverified(what, why)`. **Setup only:** `navigate(url)`.

Proof rules:
- Act through the user's path: menus, clicks, shortcuts. `url()` reads back; `navigate` sets up; neither
  stands in for the action under proof. Never debug setters or internal URLs.
- Pin every flag the behavior depends on. Never rely on the live privacy configuration.
- Select pixels by name and order, never by the params you expect. `Skipped` is not `Fired`.
- Shortcuts inside an `NSPopover` (Esc, Return) only fire when its window is key: test them explicitly.

**Fixture pages and LIVE.** Prefer a local page to a live site: `mac.navigate(mac.fixture_url(mac.token("x")))`
(`AUTOMATION = True`) opens `fixture/index.html`, served for this run only on 127.0.0.1 (in a VM, via an ssh tunnel to
its loopback). It shows the token, writes localStorage, links to `target.html`, and has a disabled button, two buttons
sharing a label and a long list. Name every live service the proof needs in `LIVE`. With `AUTOMATION`, the report
lists the hosts the app loaded (navigated, read by `url()`, and the front tab's resources at the end; not other tabs
or the app's own requests), says "local pages only" or "live: …", and flags in bold any host `LIVE` doesn't cover.

**Before and after (bug fixes).** Show the bug on the base revision with the same proof, then the fix. Wrap the
checks that show the bug in `with mac.on_base("fail"):`; every other check must come out the same on both.

```
$V prove <proof> --target vm-1 --base "$(git merge-base HEAD origin/main)" [--evidence-dir <dir>]
```

It proves the base in a worktree kept at `~/.ddg-verify-macos/base/<sha12>` (its own DerivedData: the first build is
cold, 5 to 20+ min; later runs on that revision are incremental; `$V clean-base` removes them), then this checkout, with
the same target, flags and language. On the base a check declared `fail` is recorded and the proof carries on; any
other error there is INCONCLUSIVE. **PASS** needs this checkout to pass and the base to do what each check declares,
with at least one declared `fail`; a `fail` check that passes on the base is **FAIL**: the proof doesn't reproduce
the bug. `report.md` shows each check and screenshot Before | After; each run's evidence is in `base/` and `change/`.
By hand: `git worktree add --detach <dir> <ref>`, then `$V prove <proof> --target vm-1 --checkout <dir>`.

## 2. Evidence and report

**Where evidence goes.** Each run writes one attempt folder, `<stamp>-<name>-<id>/`, in `--evidence-dir <dir>`
(created if missing; pass the directory your tooling publishes from) or by default in `~/.ddg-verify-macos/`
(`VERIFY_MACOS_HOME` overrides it). A directory inside a git checkout is refused (exit 2), symlinks resolved: this
repo is public. `prove` runs in the proof's own folder only while it holds nothing but the proof and sits directly
in that directory; otherwise it copies the proof to a new attempt folder, so a finished attempt is never
overwritten. Pass the same `--evidence-dir` to `new-proof` and `prove`; the manifest and rerun command record it.

The attempt folder holds `proof.py`, `report.md`, `manifest.json` (revision, dirty flag, source fingerprint, build and running-binary
hashes, launch args, flags, macOS and Xcode, VM, skill hash, checks, rerun command), your screenshots,
`final.png`, `app.log`, `log.txt`, `pixels.json`, `wide-events.json`, `transcript.jsonl` (every `verify.sh` call),
and `recording.mp4`, from after launch to `final.png`: a VM's whole screen, or on this Mac only the app's window,
cut where another app came in front. `prove --no-video` turns it off; the report says so.

`report.md` is one PR verification scenario: **Verified** (the docstring), **Evidence**, **Outcome** (label,
passed, failed, problems, warnings, notes), **Details** (revision, build and running binary, target and its
macOS, flags, language, rerun), **Unverified**. The verdict comes from what ran, by fixed rules:
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

**Run it in a subagent.** Hand the verification to a subagent briefed with the claim, the target and the evidence
folder. It writes the proof, runs `new-proof`, `check` and `prove`, and returns only the verdict, the `report.md` path and the evidence folder. The lead reads `report.md` and the screenshots.

## Exploring by hand: `verify.sh`

The low-level layer `prove` calls, for finding ids and trying steps before writing the proof:

```
S=.claude/skills/verify-macos-browser/scripts/verify.sh
$S vm <topic> [vm-1|vm-2|auto]; $S flag <topic> <Case> on|off; $S build <topic> . [--automation]
$S doctor <topic>; $S ax <topic> dump|find|press|clickel|click|type|key …; $S shot <topic> <name>; $S record <topic> start|stop
$S mark|expect-pixel|expect-no-pixel|expect-wide-event <topic> …; $S web <topic> url; $S cleanup <topic>
```

Call it as a single command (one permission rule covers it). Exit codes: `0` ok, `1` a check failed, `2` error.
`doctor` fails on `STALE SOURCE`, `REBUILT` or `OLD PROCESS`: never drive a stale build. Other state:
`set-default <topic> <key> <type> <value>` before `build` (most preferences are read at launch). Never use
`UITEST_MODE=1`. On a build failure, report the first error; after switching branches, "type X has no member Y"
for code that is there is a stale module in DerivedData: move it out and rebuild. Don't build in Xcode meanwhile.

**Changed the harness, `verify.sh`, `vhelp.py` or `ax.swift`?** Run the unit tests (`tests/`), then
`$V prove .claude/skills/verify-macos-browser/tests/must_fail.py --target vm-1`: PASS means every refusal still refuses. Then
`prove` each `examples/*.py`: each must PASS.

## Running in a VM

- `vm` reserves a free VM (a lock per VM in `~/.ddg-verify-macos/.vm-locks/`), wipes the Debug app's data there
  (the keychain stays) and copies `ax`. `cleanup` releases it. `NO VM FREE` lists who holds each lock.
- `build` compiles here (one build at a time), copies the app with `tar`, checks its hashes, launches it in the VM
  and presses Debug → Skip Onboarding (`--keep-onboarding` to test onboarding). Pixels stream back over ssh.
- Every ssh call goes to the local network, which Claude Code's sandbox blocks: run it outside the sandbox.
- `NOT LAUNCHED` in a VM is usually AMFI: its Provisioning UDID isn't in the profile (VM-SETUP.md step 4).
  `NOT READY` with no window: a keychain dialog waits in the VM (VM-SETUP.md step 5).
- A window can be frontmost without keyboard focus after the VM boots: `click` the field before `type`.

## Stop and ask the user

(When a harness runs this unattended: don't stop. Mark the claim Unverified with the reason and return.)

- A TCC prompt appears, or on this Mac nothing in the session holds the grants: ask, or offer a VM.
- A sign-in, payment or subscription purchase is required.
- The build fails in code you didn't touch.
- The same claim stays unverified after 2 attempts. Then question the premise; don't retry blindly.

## Feature map

`features/` holds one file per area, with a fixed contract (see `features/README.md`). Update the
file when a run teaches something new about reaching or observing the feature.
