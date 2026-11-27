"""Sync & Backup on the dev server: "Sync This Device Only" creates an account and shows the success screen with the
recovery code (copy and PDF); the synced screen lists this device, renames it and flips Share Favorites; a pasted
non-code shows "This is not a valid Sync code."; Turn Off with "Also delete server data" deletes the account."""
import base64
import json

from verify_ios import steps

DEVICES = ["iphone", "ipad"]
LIVE = ["dev-sync-use.duckduckgo.com"]
FLAGS = {**steps.SYNC_FLAGS}
PROFILE = steps.SYNC_DEV_PROFILE


def decode(code):
    return json.loads(base64.urlsafe_b64decode(code + "=" * (-len(code) % 4)))


def run(ios):
    steps.fresh_start(ios)
    ios.note("entry point: Settings > Sync & Backup; setup: Sync This Device Only; server: dev")

    steps.copy_in_app(ios, "not-a-sync-code")
    ios.scroll_to('label="All debug options"')
    ios.tap('role=button label="All debug options"')
    ios.scroll_to('role=button label="Sync"')
    ios.tap('role=button label="Sync"')
    ios.scroll_to('contains="Click to switch to"')
    ios.expect_visible('label="Development"')
    ios.expect_visible('label="Click to switch to Production"')
    ios.shot("debug-environment-development")
    ios.tap("id=BackButton")
    ios.tap("id=BackButton")

    ios.scroll_to('contains="Sync & Backup,"')
    ios.tap('role=button label="Sync & Backup, Off"')
    ios.expect_visible('label="Dev environment"')
    ios.check("Sync starts off", ios.get("id=SyncToggle") == "0")
    ios.shot("sync-off")

    ios.tap('role=button label="Sync With Another Device"')
    ios.check("the passcode sheet gates Sync With Another Device", steps.unlock_device(ios, 10))
    steps.allow_camera(ios)
    steps.tap_first_present(ios, ['role=button label="Enter Code"'], 10)
    ios.tap('role=button label="Paste Sync Code"')
    ios.wait('role=alert label="This is not a valid Sync code."', "exists", 15)
    ios.expect_visible('label="Please make sure the correct code was entered or scanned."')
    ios.shot("invalid-code-alert")
    ios.alert("accept", button="Got It")
    ios.expect_visible("id=SyncToggle")

    ios.tap("id=SyncToggle")
    ios.wait('role=button label="Sync This Device Only"', "visible", 10)
    ios.shot("another-device-prompt")
    ios.tap('role=button label="Sync This Device Only"')
    steps.unlock_device(ios)
    ios.wait("id=SyncSuccessTitle", "exists", 60)
    ios.expect_visible('contains="has been added to Sync & Backup."')
    ios.expect_visible('label="Recovery Code"')
    ios.shot("success")

    ios.tap("id=SyncSuccessCopyRecoveryCodeButton")
    steps.unlock_device(ios)
    code = ios.eventually("recovery code on the clipboard", lambda: steps.clipboard(ios).startswith("eyJyZWNvdmVyeSI6")
                          and steps.clipboard(ios), 10)
    shown = ios.get('role=text contains="eyJyZWNvdmVyeSI6"', "label")
    ios.check("the copied code decodes to the account shown on screen", decode(code) == decode(shown), [code, shown])

    ios.tap('role=button label="Download Your Recovery Code"')
    steps.unlock_device(ios)
    ios.wait('id=LP.CaptionBar.TopCaption', "exists", 15)
    ios.expect_visible('label="Sync Data Recovery - DuckDuckGo"')
    ios.expect_visible('label="PDF Document"')
    ios.shot("recovery-pdf-share-sheet")
    if ios.exists("id=header.closeButton", 2):
        ios.tap("id=header.closeButton")
    else:
        regions = ios.find("id=PopoverDismissRegion")
        ios.tap(f"id=PopoverDismissRegion nth={next(i for i, m in enumerate(regions) if m['hittable'])}")
    ios.tap("id=SyncSuccessDoneButton")

    ios.wait('label="DuckDuckGo is in sync"', "exists", 10)
    ios.expect_visible('contains=", This Device"')
    ios.shot("synced")
    ios.check("Share Favorites starts off", ios.get("id=UnifiedFavoritesToggle") == "0")
    ios.tap("id=UnifiedFavoritesToggle")
    ios.eventually("Share Favorites is on", lambda: ios.get("id=UnifiedFavoritesToggle") == "1", 5)

    ios.tap("id=device")
    steps.unlock_device(ios)
    ios.wait("id=deviceName", "visible", 10)
    ios.tap("id=deviceName")
    ios.key("cmd+a")
    ios.type("-", "Renamed by verify-ios")
    ios.key("return")
    ios.tap("id=BackButton")
    ios.eventually("the device list shows the new name",
                   lambda: ios.exists('label="Renamed by verify-ios, This Device"', 1), 15)
    ios.shot("renamed")

    ios.scroll_to('role=button label="Turn Off Sync & Backup"')
    ios.tap('role=button label="Turn Off Sync & Backup"')
    steps.unlock_device(ios)
    ios.wait("id=TurnOffAndDeleteServerDataButton", "visible", 10)
    ios.check("Also delete server data is on with one device", ios.get("id=DeleteServerDataToggle") == "1")
    ios.shot("turn-off-sheet")
    ios.tap("id=TurnOffAndDeleteServerDataButton")
    ios.wait('role=alert label="You Can’t Undo This Action."', "exists", 10)
    ios.shot("delete-confirm")
    steps.answer_alert(ios, "Permanently Delete")
    ios.wait('role=button label="I Have a Recovery Code"', "visible", 30)
    ios.check("Sync is off again", ios.get("id=SyncToggle") == "0")
    ios.shot("deleted")
