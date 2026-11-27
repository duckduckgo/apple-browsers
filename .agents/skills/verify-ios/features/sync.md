# Sync & Backup

The user turns on Sync & Backup to back up bookmarks, passwords, autofill data and Duck.ai chats end-to-end encrypted,
and to share them with their other DuckDuckGo apps. They back up this device alone, pair it with another device by
exchanging a code, or recover an account on a new install with the recovery code. Once synced, they see their
devices, rename this one, remove others, choose whether favorites are shared, save the recovery code, and turn sync
off, optionally deleting the account from the server.

## Sub-features

- `sync-backup` "Sync This Device" (`SyncToggle`), then "Sync This Device Only": an account with this device alone,
  then the success screen ("<device> has been added to Sync & Backup.").
- `sync-recovery-code` the success screen shows the recovery code. "Copy Recovery Code"
  (`SyncSuccessCopyRecoveryCodeButton`) puts it on the clipboard; "Download Your Recovery Code" opens the share sheet
  with the "Sync Data Recovery - DuckDuckGo" PDF. The synced screen repeats both under Recovery.
- `sync-pair-show` "Sync With Another Device" opens the code screen; its code button ("Scan or Copy Code") shows this
  device's code with "Copy Text Code" and "Share Code".
- `sync-pair-enter` the other device enters that code (Enter Code, then Paste Sync Code). **Both** devices then ask "Sync
  new device?" (Cancel / Sync Now), each naming the other; pairing finishes only once both accept. Then both get the
  success screen.
- `sync-recover` "I Have a Recovery Code", "Recover Synced Data", then Enter Code and Paste Sync Code with a recovery
  code: "Sync & Backup enabled".
- `sync-devices` the synced screen ("DuckDuckGo is in sync") lists My Devices (`device`), this one with ", This Device".
- `sync-rename` this device's page renames it (`deviceName`).
- `sync-remove-other` another device's page: Remove Device (`removeDevice`), then Remove.
- `sync-remove-this` this device's page: "Sync This Device" off (`SyncThisDeviceToggle`), then Remove. Sync turns off
  here; the account stays on the server.
- `sync-favorites` "Share Favorites Across Devices" (`UnifiedFavoritesToggle`).
- `sync-turn-off-delete` "Turn Off Sync & Backup", "Also delete server data?" (`DeleteServerDataToggle`) on, Turn Off and
  Delete Server Data (`TurnOffAndDeleteServerDataButton`), Permanently Delete: the account is deleted.
- `sync-error-invalid-code` a pasted text that isn't a sync code: alert "This is not a valid Sync code." (Got It).
- `sync-error-switch-account` while two or more devices are synced, a code from another account: "Switch to a different
  Sync?" (Switch Sync, Cancel). With one device the app switches without asking. Seen on both devices, but it
  dismisses itself about a second after appearing, unanswered, and nothing switches: Switch Sync and Cancel can't be
  driven (likely a product bug; see Gotchas).
- `sync-promos` promos that lead into setup: bookmarks list, passwords list, data-import summary, Duck.ai input, and
  "sync another device" in the bookmarks and passwords lists once synced.

There is one setup UI. The V1 UI and the `simplifiedSyncSetupV2` flag were removed from iOS in #6653 (September 2026);
the former V2 screens are the only ones, and `FLAGS` can't select V1. Remote `syncImprovedPairingFlow` (on by default)
picks between two versions of some texts and of when the passcode is asked; everything here was driven with it on.

## How to get to it (user POV)

- **Settings > Sync & Backup.** Browsing menu (`Browser.Toolbar.Button.Menu` on iPhone,
  `Browser.OmniBar.Button.BrowsingMenu` on iPad), Settings, then the row labelled "Sync & Backup, Off" or ", On" (no
  id). Driven on both; every proof below starts here.
- **Passwords & Autofill > Sync Desktop Passwords.** Settings > Passwords & Autofill, "Import Passwords" section, "Sync
  Desktop Passwords" (iOS 18.2 and later; older iOS has "Import Passwords" open the same screen), then "How to Sync
  Desktop Passwords" > "Sync With Desktop" opens the Sync & Backup screen. The empty passwords list has the same "Sync
  Desktop Passwords" action. Driven on both.
- **Promos.** Each opens Sync & Backup; the redesigned ones (`syncPromotionRedesign`, on by default) also start "Sync This
  Device" for the user, so the "Sync This Device Only" prompt appears. Driven on both: the standard bookmarks promo
  (`syncPromotionRedesign` pinned off), and with an aged install the redesigned bookmarks promo and "sync another
  device" in the bookmarks list. Age the install with the launch-profile key `debug.daysSinceInstall` (for example 8)
  in `PROFILE`. `fresh_start` applies it, but a fresh install's first statistics request then resets the install date
  to today, so relaunch with the profile once more: `ios.d.launch(flags=ios.flags, language=ios.language,
  profile=ios.profile)` (`ios.launch()` doesn't reapply `PROFILE`). If that first request is still in flight at the
  relaunch, it can reset the date again: check Remote Messaging's "Days Since Installed", or relaunch again when a
  promo is missing. An aged install also gets launch prompts to answer first: "Set As Default Browser" (Don't Ask
  Again) and the subscription's "Did you know?" (No thanks). What each promo needs:
  - Bookmarks list header: sync off, `syncPromotionBookmarks` on, at least one bookmark, not dismissed, and with the
    redesign an install older than 3 days. Hidden while editing, searching or inside a folder. Standard: "Sync & Back Up
    Your Bookmarks", "Set Up Sync" / "No Thanks"; redesigned: "Start Syncing" and an X ("Dismiss sync promotion").
  - Passwords list header: the same with `syncPromotionPasswords` and at least one saved login. It yields to the
    survey and the import promo. "Sync & Back Up Your Passwords". Not driven: it needs a saved login.
  - "Sync another device" (bookmarks and passwords lists): sync on, `syncPromotionSyncAnotherDevice` on, fewer than 2
    synced devices, an install older than 7 days, 24 h after a setup promo was confirmed. "Sync bookmarks with your
    desktop app too?" / "Sync passwords …", "Get App" and "Connect"; Connect opens the code screen. The passwords
    one is not driven: it needs a saved login.
  - Data-import summary: after an import, with sync off and `dataImportSummarySyncPromotion` on: "Sync & Back Up Your
    Data" (or Passwords, Bookmarks, Credit Cards), "No Thanks" / "Start Syncing". Not driven: it needs a completed
    import from a file.
  - Duck.ai input (iPhone, the unified toggle input on Duck.ai): sync off, `aiChatSync` on, the remote
    `duckAiChatHistory` feature on, at least one recent chat, fewer than 5 impressions. "Access your chats across your
    devices using Sync & Backup.", "Sync With Another Device". Not driven: it needs a live Duck.ai chat and
    depends on the live configuration.
  - Settings > All debug options > "Reset Sync Promos" clears dismissals, the Duck.ai impression count and the
    setup-confirmed date; nothing forces a promo on.
- **Not entry points to set up here:** the launch prompt that offers a preserved account after a reinstall ("Your
  previous Sync & Backup session is ready.", from "Restore on App Reinstall") and sync deep links and remote messages
  (not driven).

## Driving it with verify-ios

Preconditions:

- **Dev server, never production.** Debug builds talk to production; only CI builds default to dev. Every sync proof
  sets `PROFILE = steps.SYNC_DEV_PROFILE` (`{"debug.syncEnvironment": "Development"}`), which `fresh_start` applies
  before Sync starts. The key is saved, so later relaunches stay on dev too. Proof of it: the Sync & Backup screen
  shows a red "Dev environment" badge, and Settings > All debug options > Sync > Environment reads "Development"
  ("Click to switch to Production"); `sync_backup_manage` checks both once. Declare
  `LIVE = ["dev-sync-use.duckduckgo.com"]`. A dev-server failure is environment, not a product bug. A build from
  before launch profiles (an old `--base`) ignores `PROFILE`; the launch then fails rather than run on production.
- **Pin the setup UI and pairing protocol.** `FLAGS = {**steps.SYNC_FLAGS}` pins `syncImprovedPairingFlow` (remote,
  on by default; off, texts differ and the synced screen offers the older delete action instead of Turn Off Sync &
  Backup), and `syncCanUseV2ConnectFlow` and `syncCanShowV2ConnectCode` (remote, off by default; off, the app makes
  a legacy code and neither device asks "Sync new device?"). Pass the same `FLAGS` to a peer.
- **Evidence holds dev recovery codes.** Transcripts, screenshots and recordings show recovery and pairing codes of
  dev accounts that stay active. Keep sync evidence private, or redact it before publishing it.
- **Accounts.** Every backup creates a real dev account. They can stay on the dev server: proofs don't delete them
  unless deletion is the behavior under test (`steps.turn_off_and_delete_server_data`).
- **The passcode gate.** Setup, recovery, Sync With Another Device, copying or downloading the code, opening a
  device's page and Turn Off ask for the device passcode ("Unlock device to set up Sync & Backup"); one unlock lasts a
  short while, so the next gated step may not ask. `steps.unlock_device(ios)` answers it when it shows and returns
  whether it did. Check it returned True only for the run's first gated step.
- `steps.fresh_start(ios)`.

Steps (in `lib/verify_ios/steps.py`; quirks in [shared steps](./shared-steps.md)):

- **Open.** `steps.open_sync_settings(ios)`: browsing menu, Settings, the Sync & Backup row.
- **Back up.** Tap `SyncToggle`, then `role=button label="Sync This Device Only"`, `unlock_device`, wait for
  `SyncSuccessTitle`. Proof: the title contains "has been added to Sync & Backup.", and later the device list.
- **Copy the code.** `SyncSuccessCopyRecoveryCodeButton`, `unlock_device`, then `steps.clipboard(ios)`. The copy is
  the same account as the code on screen but not the same string (the JSON keys come out in another order): compare
  them decoded, not as text.
- **PDF.** `role=button label="Download Your Recovery Code"`; the share sheet shows `label="Sync Data Recovery -
  DuckDuckGo"` and "PDF Document". Close: `header.closeButton` on iPhone; on iPad it is a popover with several
  `PopoverDismissRegion`s, only one of them on screen: `find` them and tap the hittable one.
- **Enter a code.** Codes reach the app through `steps.copy_in_app(ios, code)` (from the browser), then Sync With
  Another Device (or I Have a Recovery Code > Recover Synced Data), `unlock_device`, `steps.allow_camera(ios)`, `role=button
  label="Enter Code"`, `role=button label="Paste Sync Code"`. There is no text field.
- **Recover.** `steps.recover_with_code(ios, code)` does the above from the browser and returns True on "Sync & Backup
  enabled". On one device: back up, keep the code, remove this device, `fresh_start`, recover. Don't use the CI
  recovery code from the duckduckgo/sync_crypto action: it is a production account.
- **Pair.** Driven on both, with the other simulator as the second device. A proof drives it as a peer,
  `peer = Ios(other, f"{ios.evidence}/peer-{other}", FLAGS, profile=PROFILE)`, after creating that folder
  (`os.makedirs`). Take the peer's device lock first
  (`env.DeviceLock(other).acquire("peer")`; it raises `Busy` when another proof holds it) and release it in
  `ios.on_cleanup` after `peer.d.cleanup(delete_sim=True)`, so a proof never drives or deletes a simulator in use, and can record it with `video.Video(peer.d.udid, path)`. Device A: back up, Sync With Another
  Device, Enter Code tab, the code button `role=button label="Scan or Copy Code"`, then "Copy Text Code" (it copies a
  `https://duckduckgo.com/sync/pairing/#&code2=…` URL; the sheet shows the code without the URL). Device B, signed
  out: `copy_in_app` with that text, Sync With Another Device, Enter Code, Paste Sync Code. Then **both** devices ask
  `role=alert label="Sync new device?"`, each naming the other; answer Sync Now on each (B asks up to a minute after
  A). Unanswered on either side, both stay on "Connecting…". Proof: both show `SyncSuccessTitle`, and A lists two
  `device` rows.
- **Rename.** Tap `device` (this one), `unlock_device`, tap `deviceName`, `key("cmd+a")`, type the name, `key("return")`.
  `ios.clear` leaves part of the old name. Proof: the row reads "<name>, This Device".
- **Remove.** Other device: `device nth=1`, `removeDevice`, Remove. This device: `SyncThisDeviceToggle`, Remove. Both
  alerts are `role=alert contains="from Sync & Backup?"`.
- **Favorites.** Tap `UnifiedFavoritesToggle`; its value goes "0" to "1". It hides its label (`labelsHidden`), so a tap
  lands on the switch.
- **Turn off and delete.** `steps.turn_off_and_delete_server_data(ios)`. "Also delete server data?" starts on with one
  device and off with more; the step turns it on.
- **Errors.** Invalid code: `copy_in_app(ios, "not-a-sync-code")`, then Paste Sync Code: `role=alert label="This is not a
  valid Sync code."`. Switch account: with two devices synced, paste another account's recovery code:
  `role=alert label="Switch to a different Sync?"`. It is gone again within about a second, before it can be
  answered: prove that it appeared, and record Switch Sync / Cancel with `ios.unverified`.

Worked proofs (kept with the evidence, not committed): `sync_backup_manage` (environment, invalid code, backup, copy,
PDF, devices, favorites, rename, turn off and delete), `sync_recover` (remove this device, reinstall, recover),
`sync_pair` (pair with the other simulator, recorded on both; the switch-account alert; remove the other device),
`sync_entry_points` (Passwords & Autofill link, standard bookmarks promo), `sync_promos_aged` (redesigned bookmarks
promo and "sync another device", with `debug.daysSinceInstall`).

Already covered elsewhere: Maestro `.maestro/sync_tests/` 01 to 06 (create, login with a code, recover, data sync,
delete). They run against production with the CI recovery code; don't copy their environment.

## Gotchas

- **`MainViewController+SyncAlerts.swift` holds only the sync-paused alerts** ("Bookmark Sync is Paused", "Sync is
  Paused", "Sync & Backup Error", each with Learn More and OK), raised by the error handler after syncing fails with
  limits or an invalid login. Setup errors ("This is not a valid Sync code.", "Sync failed.", "Already synced.", "Switch
  to a different Sync?") come from the Sync screen (`SyncSettingsViewController+SyncDelegate.swift`). The paused alerts
  need server-side limits; not driven.
- **System sheets belong to SpringBoard.** The passcode field is `app=springboard id="Passcode field"` (the label exists
  on the iOS 27 simulator), submitted with `app=springboard id=Done`. The simulator takes any passcode.
- **No camera.** The code screen opens on Scan QR and asks for the camera; it can ask twice in a row.
  `steps.allow_camera` answers each time (on both devices). Scanning can't be driven; codes go through Enter Code.
- **Host clipboard doesn't reach Paste Sync Code.** `xcrun simctl pbcopy` sets the simulator's clipboard, but the app's
  paste gets nothing and nothing happens. Text the app copies itself works, hence `copy_in_app`, which uses Settings >
  All debug options > Sync > "Paste and Copy Recovery Code". Reading with `simctl pbpaste` works.
- **Pasting this account's own recovery code while synced** shows no alert: the app logs in again, registers the
  device under its default name and shows the new-account success screen.
- **Toggles with labels** spanning the whole row don't flip on a centre tap. The sync toggles hide their labels, so
  `SyncToggle`, `SyncThisDeviceToggle`, `UnifiedFavoritesToggle` and `DeleteServerDataToggle` take a plain tap.
- **Alert texts match twice**: the alert and its static text share the label. Wait with `role=alert label=…`.
- **iPad.** Settings opens as a sheet over the browser; a tap on the menu's Settings while the menu animates can do
  nothing (`open_settings` taps again). Share sheets are popovers.
- **Bookmarks list.** On iPhone a web page's toolbar has no Bookmarks button: use the browsing menu's
  `Browser.Menu.Bookmarks`. iPad: `Browser.OmniBar.Button.Bookmarks`. Add a bookmark with the browsing menu's
  "Add Bookmark" on a web page.
- **Promo flags.** `syncPromotionBookmarks` and `syncPromotionPasswords` don't take local overrides, so those promos
  follow the live configuration: runs against it are exploratory, and can change with a remote rollout. For a
  repeatable run, serve a privacy configuration with those features set and pass it as `privacyConfigURL` in
  `PROFILE` (with `"internalUser": true`; see the `ddg-ios-launch-profile` skill); `syncPromotionRedesign` can be pinned off to get the standard design, which has no
  install-age rule.
- **A removed device's account outlives it.** "Sync This Device" off and Remove Device keep the account on the server;
  only Turn Off with "Also delete server data?" deletes it.
- **The switch-account alert closes itself.** `promptToSwitchAccounts`
  (`SyncSettingsViewController+SyncDelegate.swift`) presents it from `navigationController?.presentedViewController`,
  the code scanner, and the scanner is dismissed right after, which likely takes the alert with it. Inferred from the
  code and a screen recording (alert fading out, both devices still listed), not confirmed in the debugger.
