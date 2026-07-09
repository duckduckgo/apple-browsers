//
//  UserText.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

public struct UserText {

    // Sync Title
    public static let syncTitle = NSLocalizedString("sync.title", bundle: Bundle.module, value: "Sync & Backup", comment: "Sync & Backup Title")

    // Sync Passcode Required Alert
    static let syncPasscodeRequiredAlertTitle = NSLocalizedString("sync.passcode.required.alert.title", bundle: Bundle.module, value: "Secure Your Device to Use Sync & Backup", comment: "Sync passcode required alert - title")
    static let syncPasscodeRequiredAlertMessage = NSLocalizedString("sync.passcode.required.alert.message", bundle: Bundle.module, value: "A device password is required to use Sync & Backup.", comment: "Sync passcode required alert - message")
    static let syncPasscodeRequiredAlertGoToSettingsButton = NSLocalizedString("sync.passcode.required.alert.go.to.settings.button", bundle: Bundle.module, value: "Go to Settings", comment: "Sync passcode required alert - button")

    // Sync Filtered Items Errors
    static let invalidBookmarksPresentTitle = NSLocalizedString("bookmarks.invalid.objects.present.title", bundle: Bundle.module, value: "Some bookmarks are not syncing due to excessively long content in certain fields.", comment: "Alert title for invalid bookmarks being filtered out of synced data")
    static let invalidCredentialsPresentTitle = NSLocalizedString("credentials.invalid.objects.present.title", bundle: Bundle.module, value: "Some passwords are not syncing due to excessively long content in certain fields.", comment: "Alert title for invalid logins being filtered out of synced data")
    static let invalidCreditCardsPresentTitle = NSLocalizedString("creditCards.invalid.objects.present.title", bundle: Bundle.module, value: "Some credit cards are not syncing due to excessively long content in certain fields.", comment: "Alert title for invalid credit cards being filtered out of synced data")
    static let bookmarksLimitExceededAction = NSLocalizedString("prefrences.sync.bookmarks-limit-exceeded-action", value: "Manage Bookmarks", comment: "Button title for sync bookmarks limits exceeded warning to go to manage bookmarks")
    static let credentialsLimitExceededAction = NSLocalizedString("prefrences.sync.credentials-limit-exceeded-action", value: "Manage passwords…", comment: "Button title for sync credentials limits exceeded warning to go to manage passwords")
    static let creditCardsLimitExceededAction = NSLocalizedString("prefrences.sync.credit-cards-limit-exceeded-action", value: "Manage Credit Cards…", comment: "Button title for sync credit cards limits exceeded warning to go to manage credit cards")
    static func invalidBookmarksPresentDescription(_ invalidItemTitle: String, numberOfOtherInvalidItems: Int) -> String {
        let message = NSLocalizedString("bookmarks.invalid.objects.present.description", bundle: Bundle.module, comment: "Do not translate - stringsdict entry")
        return String(format: message, numberOfOtherInvalidItems, invalidItemTitle)
    }

    static func invalidCredentialsPresentDescription(_ invalidItemTitle: String, numberOfOtherInvalidItems: Int) -> String {
        let message = NSLocalizedString("credentials.invalid.objects.present.description", bundle: Bundle.module, comment: "Do not translate - stringsdict entry")
        return String(format: message, numberOfOtherInvalidItems, invalidItemTitle)
    }

    static func invalidCreditCardsPresentDescription(_ invalidItemTitle: String, numberOfOtherInvalidItems: Int) -> String {
        let message = NSLocalizedString("creditcards.invalid.objects.present.description", bundle: Bundle.module, comment: "Do not translate - stringsdict entry")
        return String(format: message, numberOfOtherInvalidItems, invalidItemTitle)
    }

    // Synced Devices
    static let syncedDevicesSectionHeader = NSLocalizedString("synced.devices.section.header", bundle: Bundle.module, value: "Synced Devices", comment: "Synced Devices - Section Header")
    static let syncedDevicesThisDeviceLabel = NSLocalizedString("synced.devices.this.device.label", bundle: Bundle.module, value: "This Device", comment: "Synced Devices - This Device Label")
    // Options
    static let unifiedFavoritesTitle = NSLocalizedString("unified.favorites.title", bundle: Bundle.module, value: "Unify Favorites Across Devices", comment: "Options - Unify Favorites Title")
    static let fetchFaviconsOptionTitle = NSLocalizedString("fetch.favicons.option.title", bundle: Bundle.module, value: "Auto-Download Icons", comment: "Options - Fetch Favicons Title")

    // Recovery Section
    static let recoverySectionHeader = NSLocalizedString("sync.settings.recovery.section.header", bundle: Bundle.module, value: "Recovery", comment: "Sync Settings - Recovery section header")

    // Auto-Restore
    static let autoRestoreSettingsRowLabel = NSLocalizedString("auto.restore.settings.row.label", bundle: Bundle.module, value: "Restore on App Reinstall", comment: "Auto-Restore Settings Row - Label")
    static let autoRestoreStatusOn = NSLocalizedString("auto.restore.settings.row.on", bundle: Bundle.module, value: "On", comment: "Auto-Restore Settings Row - On")
    static let autoRestoreStatusOff = NSLocalizedString("auto.restore.settings.row.off", bundle: Bundle.module, value: "Off", comment: "Auto-Restore Settings Row - Off")
    static let autoRestoreScreenTitle = NSLocalizedString("auto.restore.screen.title", bundle: Bundle.module, value: "Restore on App Reinstall", comment: "Auto-Restore Screen - Title")
    static let autoRestoreScreenDescription = NSLocalizedString("auto.restore.screen.description", bundle: Bundle.module, value: "If you reinstall the DuckDuckGo app, we'll ask if you want to restore your data on this device.", comment: "Auto-Restore Screen - Description")

    // Recover Synced Data Sheet
    static let recoverSyncedDataTitle = NSLocalizedString("recover.synced.data.sheet.title", bundle: Bundle.module, value: "Recover your synced data", comment: "Recover Synced Data Sheet - Title")
    static let recoverSyncedDataDescription = NSLocalizedString("recover.synced.data.sheet.description", bundle: Bundle.module, value: "You’ll need the Recovery Code you got when you set up Sync & Backup. You may have saved it as a PDF on the device you used.", comment: "Recover Synced Data Sheet - Description")
    static let recoverSyncedDataButton = NSLocalizedString("recover.synced.data.sheet.button", bundle: Bundle.module, value: "Recover Synced Data", comment: "Recover Synced Data Sheet - Button")
    static let autoRestoreReadyTitle = NSLocalizedString("auto.restore.ready.title", bundle: Bundle.module, value: "Your previous Sync & Backup session is ready.", comment: "Auto-Restore Ready Sheet - Title")
    static let autoRestoreReadyDescription = NSLocalizedString("auto.restore.ready.description", bundle: Bundle.module, value: "Resume your Sync & Backup session to restore your bookmarks, passwords, and more, or continue with a new setup.", comment: "Auto-Restore Ready Sheet - Description")
    static let autoRestoreReadyRestoreButton = NSLocalizedString("auto.restore.ready.restore.button", bundle: Bundle.module, value: "Resume Sync & Backup", comment: "Auto-Restore Ready Sheet - Restore Button")
    static let autoRestoreReadyScanCodeLink = NSLocalizedString("auto.restore.ready.scan.code.link", bundle: Bundle.module, value: "Continue Setup", comment: "Auto-Restore Ready Sheet - Scan Code Link")
    static let preparingToSyncTitle = NSLocalizedString("preparing.to.sync.title", bundle: Bundle.module, value: "Preparing to sync", comment: "Preparing to sync title")
    static let recoveringDataTitle = NSLocalizedString("recovering.data.title", bundle: Bundle.module, value: "Recovering Data", comment: "Recovering Data Sheet - Title")
    static let recoveringDataDescription = NSLocalizedString("recovering.data.description", bundle: Bundle.module, value: "Reconnecting to sync your bookmarks, saved logins, and other devices.", comment: "Recovering Data Sheet - Description")
    static let recoveringDataStatus = NSLocalizedString("recovering.data.status", bundle: Bundle.module, value: "Connecting...", comment: "Recovering Data Sheet - Status")

    // Camera View
    static let cameraPermissionRequired = NSLocalizedString("camera.permission.required", bundle: Bundle.module, value: "Camera Permission is Required", comment: "Camera View - Permission Required")
    static let cameraPermissionInstructions = NSLocalizedString("camera.permission.instructions", bundle: Bundle.module, value: "Please go to your device's settings and grant permission for this app to access your camera.", comment: "Camera View - Permission Instructions")
    static let cameraIsUnavailableTitle = NSLocalizedString("camera.is.unavailable.title", bundle: Bundle.module, value: "Camera is Unavailable", comment: "Camera View - Unavailable Title")
    static let cameraGoToSettingsButton = NSLocalizedString("camera.go.to.settings.button", bundle: Bundle.module, value: "Go to Settings", comment: "Camera View - Go to Settings Button")

    // Manually Enter Code View
    static let manuallyEnterCodeTitle = NSLocalizedString("manually.enter.code.title", bundle: Bundle.module, value: "Manually Enter Code", comment: "Manually Enter Code View - Title")

    // Edit Device View
    static let editDeviceHeader = NSLocalizedString("edit.device.header", bundle: Bundle.module, value: "Device Name", comment: "Edit Device View - Header")
    static func editDeviceTitle(_ name: String) -> String {
        let localized = NSLocalizedString("edit.device.title", bundle: Bundle.module, value: "Edit %@", comment: "Edit Device View - Title")
        return String(format: localized, name)
    }

    // Remove Device View
    static let removeDeviceTitle = NSLocalizedString("remove.device.title", bundle: Bundle.module, value: "Remove Device?", comment: "Remove Device View - Title")
    static let removeDeviceButton = NSLocalizedString("remove.device.button", bundle: Bundle.module, value: "Remove Device", comment: "Remove Device View - Button")
    static func removeDeviceMessage(_ name: String) -> String {
        let localized = NSLocalizedString("remove.device.message", bundle: Bundle.module, value: "\"%@\" will no longer be able to access your synced data.", comment: "Remove Device View - Message")
        return String(format: localized, name)
    }

    // Standard Buttons
    static let cancelButton = NSLocalizedString("cancel.button", bundle: Bundle.module, value: "Cancel", comment: "Standard Buttons - Cancel Button")
    static let doneButton = NSLocalizedString("done.button", bundle: Bundle.module, value: "Done", comment: "Standard Buttons - Done Button")
    static let backButton = NSLocalizedString("back.button", bundle: Bundle.module, value: "Back", comment: "Standard Buttons - Back Button")
    static let pasteButton = NSLocalizedString("paste.button", bundle: Bundle.module, value: "Paste", comment: "Standard Buttons - Paste Button")
    static let notNowButton = NSLocalizedString("not.now.button", bundle: Bundle.module, value: "Not Now", comment: "Standard Buttons - Not Now Button")
    static let copyButton = NSLocalizedString("copy.button", bundle: Bundle.module, value: "Copy", comment: "Standard Buttons - Copy Button")

    // Fetch favicons
    static let fetchFaviconsOnboardingTitle = NSLocalizedString("fetch.favicons.onboarding.title", bundle: Bundle.module, value: "Download Missing Icons?", comment: "Fetch Favicons Onboarding - Title")
    static let fetchFaviconsOnboardingMessage = NSLocalizedString("fetch.favicons.onboarding.message", bundle: Bundle.module, value: "Do you want this device to automatically download icons for any new bookmarks synced from your other devices? This will expose the download to your network any time a bookmark is synced.", comment: "Fetch Favicons Onboarding - Message")
    static let fetchFaviconsOnboardingButtonTitle = NSLocalizedString("fetch.favicons.onboarding.button.title", bundle: Bundle.module, value: "Keep Bookmarks Icons Updated", comment: "Fetch Favicons Onboarding - Button Title")

    // Sync Feature Flags
    static let syncUnavailableTitle = NSLocalizedString("sync.warning.sync.unavailable", bundle: Bundle.module, value: "Sync & Backup is Unavailable", comment: "Title of the warning message")
    static let syncUnavailableMessage = NSLocalizedString("sync.warning.data.syncing.disabled", bundle: Bundle.module, value: "Sorry, but Sync & Backup is currently unavailable. Please try again later.", comment: "Data syncing unavailable warning message")
    static let syncUnavailableMessageUpgradeRequired = NSLocalizedString("sync.warning.data.syncing.disabled.upgrade.required", bundle: Bundle.module, value: "Sorry, but Sync & Backup is no longer available in this app version. Please update DuckDuckGo to the latest version to continue.", comment: "Data syncing unavailable warning message")

    // Simplified Sync Settings
    static let simplifiedSyncToggleTitle = NSLocalizedString("sync.simplified.toggle.title", bundle: Bundle.module, value: "Sync & Backup", comment: "Sync & Backup enabled / disabled toggle title")
    static let simplifiedSyncToggleTitleThisDevice = NotLocalizedString("sync.simplified.toggle.title.this.device", bundle: Bundle.module, value: "Sync & Backup This Device", comment: "Sync & Backup enabled / disabled toggle title, referring to the current device")
    static let simplifiedSyncHeaderMessage = NSLocalizedString("sync.simplified.header.message", bundle: Bundle.module, value: "Save your bookmarks, autofill data, and Duck.ai chats, and sync them between your devices with end-to-end encryption.", comment: "Description of the Sync & Backup feature (when AI chat sync is available)")
    static let simplifiedSyncHeaderMessageBasic = NSLocalizedString("sync.simplified.header.message.basic", bundle: Bundle.module, value: "Save your bookmarks and autofill data, and sync them between your devices with end-to-end encryption.", comment: "Description of the Sync & Backup feature")
    static let simplifiedSyncHeaderTitle = NotLocalizedString("sync.simplified.header.title", bundle: Bundle.module, value: "Keep DuckDuckGo in sync!", comment: "Sync & Backup screen title")
    static let simplifiedSyncEnabledHeaderTitle = NotLocalizedString("sync.simplified.enabled.header.title", bundle: Bundle.module, value: "DuckDuckGo is in sync.", comment: "Sync & Backup screen title shown when Sync is enabled")
    static let simplifiedSyncEnabledHeaderMessage = NotLocalizedString("sync.simplified.enabled.header.message", bundle: Bundle.module, value: "Your bookmarks, autofill data, and Duck.ai chats are being synced with end-to-end encryption.", comment: "Description shown when Sync & Backup is enabled (when AI chat sync is available)")
    static let simplifiedSyncEnabledHeaderMessageBasic = NotLocalizedString("sync.simplified.enabled.header.message.basic", bundle: Bundle.module, value: "Your bookmarks and autofill data are being synced with end-to-end encryption.", comment: "Description shown when Sync & Backup is enabled")
    static let simplifiedMyDevicesSectionHeader = NotLocalizedString("sync.simplified.my.devices.section.header", bundle: Bundle.module, value: "My Devices", comment: "My Devices section header shown when Sync & Backup is enabled")
    static let simplifiedSyncStatusOn = NotLocalizedString("sync.simplified.status.on", bundle: Bundle.module, value: "On", comment: "Status label shown next to the title when Sync & Backup is enabled")
    static let simplifiedSyncStatusOff = NotLocalizedString("sync.simplified.status.off", bundle: Bundle.module, value: "Off", comment: "Status label shown next to the title when Sync & Backup is disabled")
    static let simplifiedSyncWithAnotherDeviceButton = NSLocalizedString("sync.simplified.with.another.device.button", bundle: Bundle.module, value: "Sync With Another Device", comment: "Sync With Another Device sync setup button label")
    static let simplifiedUseRecoveryCodeButton = NSLocalizedString("sync.simplified.use.recovery.code.button", bundle: Bundle.module, value: "Use Recovery Code", comment: "Use Recovery Code sync setup button label")
    static let simplifiedRecoverSyncedDataButton = NotLocalizedString("sync.simplified.recover.synced.data.button", bundle: Bundle.module, value: "Recover Synced Data", comment: "Recover Synced Data sync setup button label")
    static let simplifiedAlreadySetUpSectionHeader = NSLocalizedString("sync.simplified.already.set.up.section.header", bundle: Bundle.module, value: "Already set up on another device?", comment: "Sync settings 'Already set up' section header containing useful options")
    static let simplifiedGetDesktopBrowserTitle = NSLocalizedString("sync.simplified.get.desktop.browser.title", bundle: Bundle.module, value: "Get Desktop Browser", comment: "Button title to get the DuckDuckGo desktop browser.")
    static let simplifiedGetDesktopBrowserSubtitle = NSLocalizedString("sync.simplified.get.desktop.browser.subtitle", bundle: Bundle.module, value: "DuckDuckGo for Mac and Windows", comment: "Button subtitle to get the DuckDuckGo desktop browser")
    static let simplifiedSyncAnotherDeviceButton = NSLocalizedString("sync.simplified.another.device.button", bundle: Bundle.module, value: "Sync Another Device", comment: "Primary button to sync another device when sync is enabled")
    static let simplifiedBookmarksSectionHeader = NSLocalizedString("sync.simplified.bookmarks.section.header", bundle: Bundle.module, value: "Bookmarks", comment: "Bookmarks section header in sync settings")
    static let simplifiedBookmarksUnifiedFavoritesCaption = NSLocalizedString("sync.simplified.bookmarks.section.unified-favorites.caption", bundle: Bundle.module, value: "Use the same favorite bookmarks on mobile and desktop.", comment: "Caption displayed on 'unify favorites' toggle.")
    static let simplifiedBookmarksFetchFaviconsCaption = NSLocalizedString("sync.simplified.bookmarks.section.fetch-favicons.caption", bundle: Bundle.module, value: "Loads icons from websites you've bookmarked. Icon downloads are exposed to your network.", comment: "Caption displayed on 'auto-download bookmarks icons' toggle.")
    static let simplifiedDownloadRecoveryCodeButton = NSLocalizedString("sync.simplified.download.recovery.code.button", bundle: Bundle.module, value: "Download Recovery Code", comment: "Sync settings 'Download Recovery Code' button")
    static let simplifiedCopyRecoveryCodeButton = NSLocalizedString("sync.simplified.copy.recovery.code.button", bundle: Bundle.module, value: "Copy Recovery Code", comment: "Sync settings 'Copy Recovery Code' button")
    static let simplifiedRecoverySectionFooterFormat = NSLocalizedString("sync.simplified.recovery.section.footer", bundle: Bundle.module, value: "Use this code to restore your data if you lose access to this device. Sync & Backup data can’t be recovered after 18 months of inactivity. [Learn More](%@)", comment: "Sync settings data recovery section footer. %@ is replaced with the URL.")
    static let simplifiedDeleteSyncDataButton = NSLocalizedString("sync.simplified.delete.sync.data.button", bundle: Bundle.module, value: "Turn Off Sync and Delete Server Data", comment: "Sync settings action button title to turn off sync and delete server data")

    // Simplified Sync Toggle
    static let simplifiedSyncConnecting = NSLocalizedString("sync.simplified.connecting", bundle: Bundle.module, value: "Connecting...", comment: "Text shown next to toggle while sync is being set up")

    // Simplified Sync Another Device Prompt
    static let simplifiedSyncAnotherDeviceTitle = NSLocalizedString("sync.simplified.another.device.title", bundle: Bundle.module, value: "Sync your data with another device?", comment: "Prompt title after enabling sync")
    static let simplifiedSyncAnotherDeviceBody = NSLocalizedString("sync.simplified.another.device.body", bundle: Bundle.module, value: "Your bookmarks, autofill data, and Duck.ai chats are securely backed up. Now keep them in sync with your computer or tablet.", comment: "Prompt body text after enabling sync")
    static let simplifiedSyncAnotherDeviceNotNow = NSLocalizedString("sync.simplified.another.device.notnow", bundle: Bundle.module, value: "Not Now", comment: "Prompt secondary button")
    static let simplifiedSyncAnotherDeviceV2Title = NotLocalizedString("sync.simplified.another.device.v2.title", bundle: Bundle.module, value: "You’re now ready to sync with another device.", comment: "Title on the sync-another-device screen shown after Sync & Backup is enabled on this device")
    static func simplifiedSyncAnotherDeviceV2Body(_ deviceName: String) -> String {
        let format = NotLocalizedString("sync.simplified.another.device.v2.body", bundle: Bundle.module, value: "%@ is now synced.", comment: "Body on the sync-another-device screen. %@ is the name of the current device that was just synced.")
        return String(format: format, deviceName)
    }
    static let simplifiedRecoverYourDataV2Title = NotLocalizedString("sync.simplified.recover.your.data.v2.title", bundle: Bundle.module, value: "Recover Your Data Easily", comment: "Title on the recover-your-data screen shown after enabling Sync & Backup")
    static let simplifiedRecoverYourDataV2Description = NotLocalizedString("sync.simplified.recover.your.data.v2.description", bundle: Bundle.module, value: "Use this code to restore your data if you lose access to this device. Keep it safe.", comment: "Description on the recover-your-data screen explaining what the recovery code is for")
    static let simplifiedRecoveryCodeLabel = NotLocalizedString("sync.simplified.recovery.code.label", bundle: Bundle.module, value: "Recovery Code", comment: "Label above the recovery code on the recover-your-data screen")
    static let simplifiedDownloadYourRecoveryCodeButton = NotLocalizedString("sync.simplified.download.your.recovery.code.button", bundle: Bundle.module, value: "Download Your Recovery Code", comment: "Button to download the recovery code on the recover-your-data screen")

    // Simplified QR Scanning
    static let simplifiedScanTitle = NSLocalizedString("sync.simplified.scan-or-view-code.title", bundle: Bundle.module, value: "Sync Your Devices", comment: "Navigation title for simplified QR scanning screen")
    static let simplifiedScanTabScanQRCode = NSLocalizedString("sync.simplified.scan-or-view-code.tab.scan", bundle: Bundle.module, value: "Scan QR Code", comment: "Button title to show QR code scanner")
    static let simplifiedScanTabViewCode = NSLocalizedString("sync.simplified.scan-or-view-code.tab.view.code", bundle: Bundle.module, value: "View Code", comment: "Button title to view your sync code")
    static let simplifiedScanInstructions = NSLocalizedString("sync.simplified.scan-or-view-code.scan.instructions.line1", bundle: Bundle.module, value: "Open the DuckDuckGo app on your other device.", comment: "First line of QR code scanning instructions")
    static let simplifiedScanInstructionsLine2 = NSLocalizedString("sync.simplified.scan-or-view-code.scan.instructions.line2", bundle: Bundle.module, value: "Find the QR code in Settings > Sync & Backup > Sync With Another Device.", comment: "Second line of QR code scanning instructions")
    static let simplifiedScanCameraPrompt = NSLocalizedString("sync.simplified.scan-or-view-code.camera.prompt", bundle: Bundle.module, value: "Point Camera at QR to Scan", comment: "Floating prompt over QR code scanner preview")
    static let simplifiedScanManuallyEnterCode = NSLocalizedString("sync.simplified.scan-or-view-code.manually.enter.code", bundle: Bundle.module, value: "Manually Enter Code", comment: "Button to navigate to manual sync code entry")
    static let simplifiedViewCodeInstructions = NSLocalizedString("sync.simplified.scan-or-view-code.view.instructions", bundle: Bundle.module, value: "Scan or Paste this code in your other", comment: "Instructions on sync QR code display screen (will be shown above the DuckDuckGo app icon and name)")
    static let simplifiedViewCodeAppName = NSLocalizedString("sync.simplified.scan-or-view-code.app.name", bundle: Bundle.module, value: "DuckDuckGo App", comment: "Part of instruction prompt referring to the DuckDuckGo app.")
    static let simplifiedViewCodeShareButton = NSLocalizedString("sync.simplified.scan-or-view-code.share", bundle: Bundle.module, value: "Share Code", comment: "Title of button to share a sync code")
    static let simplifiedViewCodeCopyConfirmationTitle = NSLocalizedString("sync.simplified.scan-or-view-code.copy-confirmation.title", bundle: Bundle.module, value: "Paste the code on your other device", comment: "Title of the reminder shown after the user copies the sync code.")
    static let simplifiedViewCodeCopyConfirmationMessage = NSLocalizedString("sync.simplified.scan-or-view-code.copy-confirmation.message", bundle: Bundle.module, value: "Come back to this device after pasting the code.", comment: "Message of the reminder shown after the user copies the sync code.")
    static let simplifiedConnectingTitle = NSLocalizedString("sync.simplified.scan-or-view-code.connecting.title", bundle: Bundle.module, value: "End-to-end encrypted on all your devices.", comment: "Instruction shown during sync setup flow.")
    static let simplifiedConnectingStatus = NSLocalizedString("sync.simplified.scan-or-view-code.connecting.status", bundle: Bundle.module, value: "Connecting...", comment: "Status text when connecting devices to sync")
    static let simplifiedConnectingV2Title = NotLocalizedString("sync.simplified.connecting.v2.title", bundle: Bundle.module, value: "Sync & Backup is end-to-end encrypted on all your devices.", comment: "Title shown on the connecting screen while Sync & Backup is being set up on this device")
    static let simplifiedPasteCodeInstructions = NSLocalizedString("sync.simplified.scan-or-view-code.paste.code.instructions", bundle: Bundle.module, value: "Go to **Settings > Sync & Backup > Sync With Another Device** and select **View Text Code** in the DuckDuckGo App on another synced device and paste the code here to sync this device.", comment: "Instructions on manual sync code entry screen. **bold** marks are rendered as bold text.")
    static let simplifiedPasteCodeVerifying = NSLocalizedString("sync.simplified.scan-or-view-code.paste.code.verifying", bundle: Bundle.module, value: "Verifying code", comment: "Status text while verifying a pasted sync code")

    // Sync Get Other Devices
    static let syncGetOtherDevicesScreenTitle = NSLocalizedString("sync.get.other.devices.screen.title", bundle: Bundle.module, value: "Get DuckDuckGo", comment: "Title of screen with share links for users to download DuckDuckGo on other devices")
    static let syncGetOtherDevicesTitle = NSLocalizedString("sync.get.other.devices.card.title", bundle: Bundle.module, value: "Get DuckDuckGo on other devices to sync with this one", comment: "Title of card with share links for users to download DuckDuckGo on other devices")
    static let syncGetOtherDevicesMessage = NSLocalizedString("sync.get.other.devices.card.message", bundle: Bundle.module, value: "To download DuckDuckGo on desktop or another mobile device, visit:", comment: "Message before share link for downloading DuckDuckGo on other devices")
    static let syncGetOtherDevicesButtonTitle = NSLocalizedString("sync.get.other.devices.card.button.title", bundle: Bundle.module, value: "Share Download Link", comment: "Button title to share link for downloading DuckDuckGo on other devices")
    static let syncGetOtherDeviceShareLinkMessage = NSLocalizedString("sync.get.other.devices.share.link.message", bundle: Bundle.module, value: "Install the DuckDuckGo browser on your devices to start securely syncing your bookmarks and autofill data:", comment: "Message included when sharing a url via the system share sheet")

}

// Use this instead of NSLocalizedString for strings that are not supposed to be translated
// swiftlint:disable:next identifier_name
public func NotLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = Bundle.main, value: String = "", comment: String) -> String {
    return value
}
