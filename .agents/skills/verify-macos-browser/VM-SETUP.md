# Verification VM setup

Run `verify-macos-browser` inside a macOS VM so it never takes your screen. You keep using your Mac while the
agent drives the app in the VM over ssh. Tested 2026-11-18 on macOS 27.2.1 (host and guest), VirtualBuddy, Apple
silicon.

What you get: the agent builds on your Mac, copies the app to the VM, and drives it there with `ax` (real clicks and
keys), `screencapture` and `log stream`. All of it works with the VM window minimized.

Two limits:
- At most 2 macOS VMs running at once per Mac: the macOS license allows two virtual copies, and Apple's
  Virtualization framework (which VirtualBuddy uses) refuses to start a third. You can keep more VMs on disk.
- Your Mac must not sleep (the VM pauses). Don't click inside the VM window while a verification runs.

## 1. Create the VM

1. Install [VirtualBuddy](https://github.com/insidegui/VirtualBuddy).
2. Create a macOS VM with **the same macOS version as your Mac**. A newer host can't install an older guest from
   IPSW (VirtualBuddy error 10007, "failed to clean NAND").
3. Finish Setup Assistant with a local account. These steps use `virtualmachine`; use any name. Turn FileVault off.

## 2. Configure the VM (inside the VM)

System Settings:

| Where | Setting |
|---|---|
| General → Sharing | **Remote Login** on (only this one; Remote Management and Remote Application Scripting stay off) |
| Users & Groups | "Automatically log in as" → your VM user. Greyed out means FileVault is on |
| Lock Screen | Screen saver → Never · Turn display off → Never · Require password → Never |
| Privacy & Security → Accessibility | add `/usr/libexec/sshd-keygen-wrapper` |
| Privacy & Security → Screen & System Audio Recording | add `/usr/libexec/sshd-keygen-wrapper` |

To add the path: press **+**, then **⌘⇧G** in the file picker, type the path, Enter, **Open**.

Why `sshd-keygen-wrapper`: every ssh session inherits the grants of this binary, so `ax` and `screencapture` run
over ssh need no grant of their own. Don't grant `ax` itself: its ad-hoc signature changes on every rebuild and the
grant is lost.

Don't install Xcode or Command Line Tools in the VM. It has no `python3`; the stub opens an install dialog — cancel
it.

## 3. ssh from your Mac

Find the VM's IP (inside the VM: `ipconfig getifaddr en0`; usually `192.168.64.x`) and short user name (`whoami`).

```bash
ssh-keygen -t ed25519 -f ~/.ssh/verify_vm_ed25519 -N "" -C verify-vm
```

Add to `~/.ssh/config`:

```
Host vm-1
  HostName 192.168.64.2
  User virtualmachine
  IdentityFile ~/.ssh/verify_vm_ed25519
  IdentitiesOnly yes
```

Copy the key (asks for the VM password once). Copy-paste into the VM window doesn't work, so do it from your Mac:

```bash
ssh-copy-id -i ~/.ssh/verify_vm_ed25519.pub vm-1
```

Check: `ssh vm-1 true` returns without a prompt. Then turn off password login (asks for the VM password for
sudo):

```bash
ssh -t vm-1 'printf "PasswordAuthentication no\nKbdInteractiveAuthentication no\n" | sudo tee /etc/ssh/sshd_config.d/100-verify.conf'
```

**Claude Code:** its sandbox blocks TCP to the local network (`No route to host`), so ssh to the VM runs outside the
sandbox and asks for permission.

No device registration: the app is signed with Developer ID, whose profile has no device list (SKILL.md, Signing).
Your Mac needs the signing assets once; `selftest` checks them. Re-signing ad hoc doesn't work: without a team ID
the app gets no app group container and crashes in `FileManager.configurationDirectory()`.

## 4. If a keychain dialog appears

If a run stops with `NOT READY: no window after 60 s; <app> is in front: answer its prompt`, a dialog waits in the
VM: open the VM window and answer it. For a keychain dialog, click **Always Allow**. The agent can't answer it. Left
unanswered, the app shows no window; cancelled, it quits.

## 5. Save `vm-default`

Once steps 1–3 pass, keep a copy of the configured VM so you never redo them:

1. Shut the VM down.
2. In Finder, duplicate its `.vbvm` bundle (VirtualBuddy library → right-click the VM → Show in Finder) and name the
   copy `vm-default`. Never run `vm-default` itself: run copies of it (`vm-1`, `vm-2`).

To run two verifications at once, make two copies and start both. VirtualBuddy notices they share a MAC address and
offers to change it on the second one: accept. That copy then gets its own IP: add a `Host` entry for it:

```
Host vm-2
  HostName 192.168.64.3
  User virtualmachine
  IdentityFile ~/.ssh/verify_vm_ed25519
  IdentitiesOnly yes
```

Keep `vm-1` and `vm-2` once they work.

`--target vm-1` and `--target vm-2` use these `Host` names. `--target vm` takes the first free VM in `VERIFY_VMS`
(default `vm-1 vm-2`). Keep both on the same macOS version: with `--target vm`, `--base` can run the base and the
change on different VMs, and different versions make the pair INCONCLUSIVE. `--target vm-N` pins one.

## 6. Check the VM

From your Mac, each line must pass:

```bash
ssh vm-1 true                                    # no prompt
ssh vm-1 'pmset -g | grep displaysleep'          # 0
ssh vm-1 'sysadminctl -screenLock status'        # off
ssh vm-1 'defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser'   # your VM user
```

Accessibility and Screen Recording: `ssh vm-1 '~/verify/ax grants'` must print
`accessibility=true screen-recording=true`. `~/verify/ax` is there after the first run or selftest copied it.

Or run all of it, and a launch and two proofs: `bin/verify-macos-browser selftest --target vm-1` names the first step
that fails and points back into this file. Run it for `vm-2` too.

## Gotchas

- **Onboarding.** After each launch in a VM, `build` presses Debug → Skip Onboarding (`--keep-onboarding` to test
  it). It stops with `ONBOARDING NOT SKIPPED` when the app isn't frontmost or the VM's screen is locked.
- **`ax` matches across windows.** A target that matches several elements is refused (`AMBIGUOUS`). Target elements
  by `id` (`NewTabButton`), not by visible text: "New Tab" also matches a tab's title.
- **Logs:** `log stream` / `log show` work over ssh. Pixel checks (`vhelp.py`) run on your Mac, on logs copied back.
- **A window can be frontmost without keyboard focus** (seen after a VM boot). Typing is then refused
  (`NOT FOCUSED`): click into the field first.

## Not verified yet

- Whether the keychain dialog appears in a fresh VM at all. Seen once, after an ad-hoc signed copy had run in the
  same VM.
- Whether "Always Allow" holds for a build signed by another engineer's certificate.
