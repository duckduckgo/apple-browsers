//
//  UserText.swift
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

enum UserText {

    // Generic Buttons
    static let ok = NSLocalizedString("ok", bundle: Bundle.module, value: "OK", comment: "OK button")
    static let notNow = NSLocalizedString("notnow", bundle: Bundle.module, value: "Not Now", comment: "Not Now button")
    static let cancel = NSLocalizedString("cancel", bundle: Bundle.module, value: "Cancel", comment: "Cancel button")
    static let copy = NSLocalizedString("copy", bundle: Bundle.module, value: "Copy", comment: "Copy button")
    static let share = NSLocalizedString("share", bundle: Bundle.module, value: "Share", comment: "Share button")
    static let paste = NSLocalizedString("paste", bundle: Bundle.module, value: "Paste", comment: "Paste button")
    static let done = NSLocalizedString("done", bundle: Bundle.module, value: "Done", comment: "Done button")

    // Begin Sync card.
    static let beginSyncTitle = NSLocalizedString("preferences.begin-sync-v2.card-title", bundle: Bundle.module, value: "Keep DuckDuckGo in sync!", comment: "Begin Syncing card title in sync settings")
    static let beginSyncDescription = NSLocalizedString("preferences.begin-sync-v2.card-description", bundle: Bundle.module, value: "Your autofill data, bookmarks, and Duck.ai chats, end-to-end encrypted across your DuckDuckGo apps.", comment: "Begin Syncing card description in sync settings")
    static let beginSyncButton = NSLocalizedString("preferences.begin-sync-v2.card-button", bundle: Bundle.module, value: "Sync With Another Device", comment: "Button text on the Begin Syncing card in sync settings")
    static let beginSyncFooter = NSLocalizedString("preferences.begin-sync-v2.card-footer", bundle: Bundle.module, value: "Don’t have DuckDuckGo on another device? [Get the DuckDuckGo app?](https://duckduckgo.com/app/devices)", comment: "Footer under the Begin Syncing card in sync settings. The [text](url) markdown is a link and must be preserved.")
    static let syncThisDeviceTitle = NSLocalizedString("preferences.sync-this-device-v2.title", bundle: Bundle.module, value: "Sync this Device", comment: "Title of the row to start syncing and backing up this device in sync settings")
    static let recoverSyncedDataTitle = NSLocalizedString("preferences.recover-synced-data-v2.section-title", bundle: Bundle.module, value: "Recover Synced Data", comment: "Recover Synced Data section title in sync settings")
    static let recoverCodeButton = NSLocalizedString("preferences.recover-synced-data-v2.button", bundle: Bundle.module, value: "I Have a Recovery Code", comment: "Button to recover synced data with a recovery code in sync settings")

    // Device selection prompt shown after enabling Sync.
    static let syncAnotherDevicePromptTitle = NSLocalizedString("preferences.sync.another-device-prompt-v2.title", bundle: Bundle.module, value: "Sync this device with a nearby phone.", comment: "Title of the prompt asking whether to sync with another device or just this device")
    static let syncAnotherDevicePromptSubtitle = NSLocalizedString("preferences.sync.another-device-prompt-v2.subtitle", bundle: Bundle.module, value: "We’ll help you sync your devices.", comment: "Subtitle of the prompt asking whether to sync with another device or just this device")
    static let syncThisDeviceOnlyButton = NSLocalizedString("preferences.sync.another-device-prompt-v2.this-device-only-button", bundle: Bundle.module, value: "Sync This Device Only", comment: "Button to enable Sync & Backup on the current device only, without pairing another device")
    static let syncWithAnotherDeviceButton = NSLocalizedString("preferences.sync.another-device-prompt-v2.another-device-button", bundle: Bundle.module, value: "Sync With Another Device", comment: "Button to continue to the pairing screen to sync with another device")

    // Sync with another device dialog.
    static let syncWithAnotherDeviceScanTitle = NSLocalizedString("preferences.sync.sync-with-another-device-v2.scan-title", bundle: Bundle.module, value: "Scan QR code to sync", comment: "Title of the Sync with another device dialog when showing the QR code")
    static let syncWithAnotherDeviceEnterTitle = NSLocalizedString("preferences.sync.sync-with-another-device-v2.enter-title", bundle: Bundle.module, value: "Enter the Sync Code", comment: "Title of the Sync with another device dialog when entering a sync code")
    static let syncWithAnotherDeviceScanTab = NSLocalizedString("preferences.sync.sync-with-another-device-v2.scan-tab", bundle: Bundle.module, value: "Scan Code", comment: "Tab that displays a QR code to scan from another device")
    static let syncWithAnotherDeviceEnterTab = NSLocalizedString("preferences.sync.sync-with-another-device-v2.enter-tab", bundle: Bundle.module, value: "Enter Code", comment: "Tab that lets the user paste a sync code from another device")
    static let syncWithAnotherDeviceScanStep1Prefix = NSLocalizedString("preferences.sync.sync-with-another-device-v2.scan-step-1-prefix", bundle: Bundle.module, value: "On your phone, open the", comment: "First part of the first QR scanning instruction, before the DuckDuckGo product name")
    static let syncWithAnotherDeviceScanStep1Detail = NSLocalizedString("preferences.sync.sync-with-another-device-v2.scan-step-1-detail", bundle: Bundle.module, value: "DuckDuckGo App", comment: "Emphasized DuckDuckGo product name in the first QR scanning instruction")
    static let syncWithAnotherDeviceStep2Prefix = NSLocalizedString("preferences.sync.sync-with-another-device-v2.step-2-prefix", bundle: Bundle.module, value: "Go to", comment: "First part of the second pairing instruction, before the Settings path")
    static let syncWithAnotherDeviceStep2Detail = NSLocalizedString("preferences.sync.sync-with-another-device-v2.step-2-detail", bundle: Bundle.module, value: "Settings › Sync & Backup › Sync With Another Device", comment: "Emphasized Settings path in the second pairing instruction")
    static let syncWithAnotherDeviceScanStep3 = NSLocalizedString("preferences.sync.sync-with-another-device-v2.scan-step-3", bundle: Bundle.module, value: "Scan this QR code from your phone", comment: "Third pairing instruction when showing the QR code")
    static let syncWithAnotherDeviceEnterStep3 = NSLocalizedString("preferences.sync.sync-with-another-device-v2.enter-step-3", bundle: Bundle.module, value: "Copy the QR Text Code and click ‘Paste Code’ below:", comment: "Third pairing instruction when entering a code from another device")
    static let syncWithAnotherDeviceStep4 = NSLocalizedString("preferences.sync.sync-with-another-device-v2.step-4", bundle: Bundle.module, value: "Don’t close this window while connecting", comment: "Fourth pairing instruction, reminding the user to keep the dialog open")
    static let syncWithAnotherDeviceExampleCode = NSLocalizedString("preferences.sync.sync-with-another-device-v2.example-code", bundle: Bundle.module, value: "Example Code:", comment: "Label above the example sync code in the code entry tab")
    static let syncWithAnotherDevicePasteCode = NSLocalizedString("preferences.sync.sync-with-another-device-v2.paste-code", bundle: Bundle.module, value: "Paste Code", comment: "Button that pastes a sync code from the clipboard")
    static let syncWithAnotherDeviceCopied = NSLocalizedString("preferences.sync.sync-with-another-device-v2.copied", bundle: Bundle.module, value: "Copied", comment: "Confirmation shown after copying the sync code")
    static let syncWithAnotherDeviceCopyConfirmationTitle = NSLocalizedString("preferences.sync.sync-with-another-device-v2.copy-confirmation-title", bundle: Bundle.module, value: "Don’t close this page", comment: "Title of the reminder shown after copying the sync code")
    static let syncWithAnotherDeviceCopyConfirmationMessage = NSLocalizedString("preferences.sync.sync-with-another-device-v2.copy-confirmation-message", bundle: Bundle.module, value: "Open DuckDuckGo on your other device and paste the code.", comment: "Message of the reminder shown after copying the sync code")

    // Alert shown when the user cancels the device authentication prompt while setting up Sync.
    static let syncAuthenticationCancelledTitle = NSLocalizedString("preferences.sync.authentication-cancelled-v2.title", bundle: Bundle.module, value: "Please give it another try!", comment: "Title of the alert shown when the user cancels the device authentication prompt while setting up Sync")
    static let syncAuthenticationCancelledSubtitle = NSLocalizedString("preferences.sync.authentication-cancelled-v2.subtitle", bundle: Bundle.module, value: "You need to authenticate to turn on Sync & Backup. macOS will ask for an authentication method.", comment: "Subtitle of the alert shown when the user cancels the device authentication prompt while setting up Sync")
    static let syncAuthenticationCancelledCloseButton = NSLocalizedString("preferences.sync.authentication-cancelled-v2.close-button", bundle: Bundle.module, value: "Close", comment: "Button to dismiss the alert shown when the user cancels the device authentication prompt while setting up Sync")
    static let syncAuthenticationCancelledTryAgainButton = NSLocalizedString("preferences.sync.authentication-cancelled-v2.try-again-button", bundle: Bundle.module, value: "Try Again", comment: "Button to retry device authentication from the alert shown when the user cancels the device authentication prompt while setting up Sync")

    // Sync Enabled View.
    static let syncEnabledFooter = NSLocalizedString("preferences.sync-enabled-v2.footer", bundle: Bundle.module, value: "Your bookmarks, autofill data, and Duck.ai chats, are being synced with end-to-end encryption. Support for certain data types depends on the platform. [Learn More](https://duckduckgo.com/duckduckgo-help-pages/sync-and-backup/sync-and-backup-privacy/)", comment: "Footer describing what is being synced in sync settings when sync is enabled. The [text](url) markdown is a link and must be preserved.")
    static let syncEnabledFooterWithoutAIChat = NSLocalizedString("preferences.sync-enabled-v2.footer-without-ai-chat", bundle: Bundle.module, value: "Your bookmarks and autofill data are being synced with end-to-end encryption. Support for certain data types depends on the platform. [Learn More](https://duckduckgo.com/duckduckgo-help-pages/sync-and-backup/sync-and-backup-privacy/)", comment: "Footer describing what is being synced in sync settings when sync is enabled and Duck.ai chat sync is unavailable. The [text](url) markdown is a link and must be preserved.")
    static let myDevices = NSLocalizedString("preferences.sync.my-devices-v2", bundle: Bundle.module, value: "My Devices", comment: "Synced devices section title in sync settings")
    static let myDevicesFooter = NSLocalizedString("preferences.sync.my-devices-footer-v2", bundle: Bundle.module, value: "Your data is end-to-end encrypted. Nobody but you can see your data, not even us.", comment: "Footer under the synced devices section in sync settings")
    static let bookmarksSectionTitle = NSLocalizedString("preferences.sync.bookmarks-section-title-v2", bundle: Bundle.module, value: "Bookmarks", comment: "Bookmarks options section title in sync settings")
    static let shareFavoritesOptionTitle = NSLocalizedString("preferences.sync.share-favorite-option-title-v2", bundle: Bundle.module, value: "Share Favorites Across Devices", comment: "Title for the share favorites option in sync settings")
    static let shareFavoritesOptionCaption = NSLocalizedString("preferences.sync.share-favorite-option-caption-v2", bundle: Bundle.module, value: "Use the same favorite bookmarks on mobile and desktop.", comment: "Caption for the share favorites option in sync settings")
    static let fetchFaviconsOptionTitle = NSLocalizedString("preferences.sync.fetch-favicons-option-title-v2", bundle: Bundle.module, value: "Load Bookmark Icons", comment: "Title for the load bookmark icons option in sync settings")
    static let fetchFaviconsOptionCaption = NSLocalizedString("preferences.sync.fetch-favicons-option-caption-v2", bundle: Bundle.module, value: "Loads icons from websites you’ve bookmarked. Icon downloads are exposed to your network.", comment: "Caption for the load bookmark icons option in sync settings")
    static let recoveryCodeSectionTitle = NSLocalizedString("preferences.sync.recovery-code-section-title-v2", bundle: Bundle.module, value: "Recovery Code", comment: "Recovery code section title in sync settings")
    static let recoveryInstructions = NSLocalizedString("preferences.sync.recovery-instructions-v2", bundle: Bundle.module, value: "Use this code to restore your data if you lose access to this device.", comment: "Instructions on how to restore synced data in sync settings")
    static let downloadRecoveryCodeButton = NSLocalizedString("preferences.sync.download-recovery-code-v2", bundle: Bundle.module, value: "Download Recovery Code", comment: "Button to download the recovery code in sync settings")
    static let recoveryInstructionsFooter = NSLocalizedString("preferences.sync.recovery-instructions-footer-v2", bundle: Bundle.module, value: "Sync & Backup data can’t be recovered after 18 months of inactivity. [Learn more](https://duckduckgo.com/duckduckgo-help-pages/sync-and-backup/recovery-codes-and-troubleshooting)", comment: "Footer on the recovery code section in sync settings. The [text](url) markdown is a link and must be preserved.")
    static let turnOffAndDeleteServerData = NSLocalizedString("preferences.sync.turn-off-and-delete-data-v2", bundle: Bundle.module, value: "Turn Off and Delete Server Data", comment: "Disable and delete data sync button caption")

    // Device details dialogs.
    static let deviceDetailsSyncedStatus = NSLocalizedString("preferences.sync.device-details-v2.synced-status", bundle: Bundle.module, value: "Synced", comment: "Status shown under the device name on the device details dialog")
    static let deviceDetailsNameLabel = NSLocalizedString("preferences.sync.device-details-v2.name-label", bundle: Bundle.module, value: "Name", comment: "Label of the editable device name field on the device details dialog")
    static let deviceDetailsDoneButton = NSLocalizedString("preferences.sync.device-details-v2.done-button", bundle: Bundle.module, value: "Done", comment: "Button that saves the device name and dismisses the device details dialog")
    static let deviceDetailsCloseButton = NSLocalizedString("preferences.sync.device-details-v2.close-button", bundle: Bundle.module, value: "Close", comment: "Button that dismisses the details dialog of another synced device")
    static let deviceDetailsTurnOffSyncButton = NSLocalizedString("preferences.sync.device-details-v2.turn-off-sync-button", bundle: Bundle.module, value: "Turn Off Sync & Backup", comment: "Button that turns Sync & Backup off for the current device, on the device details dialog")
    static let deviceDetailsRemoveDeviceButton = NSLocalizedString("preferences.sync.device-details-v2.remove-device-button", bundle: Bundle.module, value: "Remove Device", comment: "Button that removes another synced device, on the device details dialog")

    // Remove device confirmation dialog.
    static let removeDeviceConfirmTitle = NSLocalizedString("preferences.sync.remove-device-v2.title", bundle: Bundle.module, value: "Remove Device?", comment: "Title of the confirmation shown before removing a synced device")
    static let removeDeviceConfirmButton = NSLocalizedString("preferences.sync.remove-device-v2.button", bundle: Bundle.module, value: "Remove Device", comment: "Button that confirms removing a synced device")
    static func removeDeviceConfirmMessage(_ deviceName: String) -> String {
        let format = NSLocalizedString("preferences.sync.remove-device-v2.message",
                                       bundle: Bundle.module,
                                       value: "**%@** will no longer be able to access your synced data.\n\nYour autofill data, bookmarks, and duck.ai chats won’t sync across your other devices with DuckDuckGo.",
                                       comment: "Message of the confirmation shown before removing a synced device. The device name is inserted in place of %@ and the ** markers around it indicate bold styling, which should be preserved.")
        return String(format: format, deviceName)
    }

    // Turn off and delete server data confirmation dialog.
    static let deleteAccountConfirmTitle = NSLocalizedString("preferences.sync.delete-account-v2.title", bundle: Bundle.module, value: "Stop Sync & Backup and Delete Server Data?", comment: "Title of the confirmation shown before turning Sync off and deleting the server data")
    static let deleteAccountConfirmMessage = NSLocalizedString("preferences.sync.delete-account-v2.message", bundle: Bundle.module, value: "All devices using Sync & Backup will be disconnected and your synced data will be deleted from the server.", comment: "Message of the confirmation shown before turning Sync off and deleting the server data")
    static let deleteAccountConfirmButton = NSLocalizedString("preferences.sync.delete-account-v2.button", bundle: Bundle.module, value: "Delete Server Data", comment: "Button that confirms turning Sync off and deleting the server data")

    // Preparing to sync dialog.
    static let preparingToSyncDialogTitle = NSLocalizedString("preferences.preparing-to-sync-v2.dialog-title", bundle: Bundle.module, value: "Sync & Backup is end-to-end encrypted on all your devices.", comment: "Preparing to sync dialog title during two-device sync set up")
    static let preparingToSyncCheckOtherDeviceTitle = NSLocalizedString("preferences.preparing-to-sync-v2.check-other-device-title", bundle: Bundle.module, value: "Check your other device...", comment: "Title shown while the joining device waits for the other device during sync set up")
    static let preparingToSyncDialogAction = NSLocalizedString("preferences.preparing-to-sync-v2.dialog-action", bundle: Bundle.module, value: "Connecting...", comment: "Status text while preparing to sync")

    // Sync success dialog.
    static let syncSuccessFallbackDeviceName = NSLocalizedString("preferences.sync.success-v2.fallback-device-name", bundle: Bundle.module, value: "This device", comment: "Fallback device name in the Sync success dialog when the current device name is unavailable")
    static func syncSuccessTitle(deviceName: String) -> String {
        let format = NSLocalizedString("preferences.sync.success-v2.title", bundle: Bundle.module, value: "%@ has been added to Sync & Backup.", comment: "Title in the Sync success dialog. %@ is the name of the device that was added")
        return String(format: format, deviceName)
    }
    static let syncSuccessDescription = NSLocalizedString("preferences.sync.success-v2.description", bundle: Bundle.module, value: "Use this code to restore your synced data if you lose access to your devices. Keep it safe.", comment: "Recovery code explanation in the Sync success dialog")
    static let syncSuccessRecoveryCodeLabel = NSLocalizedString("preferences.sync.success-v2.recovery-code-label", bundle: Bundle.module, value: "Recovery Code", comment: "Recovery code label in the Sync success dialog")
    static let syncSuccessCopyCodeButton = NSLocalizedString("preferences.sync.success-v2.copy-code-button", bundle: Bundle.module, value: "Copy Code", comment: "Button to copy the recovery code in the Sync success dialog")
    static let syncSuccessCopiedCodeButton = NSLocalizedString("preferences.sync.success-v2.copied-code-button", bundle: Bundle.module, value: "Copied", comment: "Confirmation shown on the copy button after copying the recovery code in the Sync success dialog")
    static let syncSuccessDownloadPDFButton = NSLocalizedString("preferences.sync.success-v2.download-pdf-button", bundle: Bundle.module, value: "Download as PDF", comment: "Button to download the recovery code as a PDF in the Sync success dialog")

    // Enter recovery code dialog
    static let enterRecoveryCodeDialogTitle = NSLocalizedString("preferences.enter-recovery-code.dialog-title", bundle: Bundle.module, value: "Enter Code", comment: "Sync enter recovery code dialog title")
    static let enterRecoveryCodeDialogSubtitle = NSLocalizedString("preferences.enter-recovery-code.dialog-subtitle", bundle: Bundle.module, value: "Enter the code on your Recovery PDF, or another synced device, to recover your synced data.", comment: "Sync enter recovery code dialog subtitle")
    static let enterRecoveryCodeDialogAction1 = NSLocalizedString("preferences.enter-recovery-code.dialog-action1", bundle: Bundle.module, value: "Paste Code Here", comment: "Sync enter recovery code dialog first possible action")
    static let enterRecoveryCodeDialogAction2 = NSLocalizedString("preferences.enter-recovery-code.dialog-action2", bundle: Bundle.module, value: "or scan QR code with a device that is still connected", comment: "Sync enter recovery code dialog second possible action")

    // Recover synced data dialog
    static let reciverSyncedDataDialogTitle = NSLocalizedString("preferences.recover-synced-data.dialog-title", bundle: Bundle.module, value: "Recover Synced Data", comment: "Sync recover synced data dialog title")
    static let reciverSyncedDataDialogSubitle = NSLocalizedString("preferences.recover-synced-data.dialog-subtitle", bundle: Bundle.module, value: "To restore your synced data, you'll need the Recovery Code you saved when you first set up Sync. This code may have been saved as a PDF on the device you originally used to set up Sync.", comment: "Recover synced data during Sync recovery process dialog subtitle")
    static let reciverSyncedDataDialogButton = NSLocalizedString("preferences.recover-synced-data.dialog-button", bundle: Bundle.module, value: "Get Started", comment: "Sync recover synced data dialog button")

    // Sync Title
    static let sync = NSLocalizedString("preferences.sync", bundle: Bundle.module, value: "Sync & Backup", comment: "Show sync preferences")

    static let turnOff = NSLocalizedString("preferences.sync.turn-off", bundle: Bundle.module, value: "Turn Off", comment: "Turn off sync confirmation dialog button title")

    // Turn off sync dialog
    static let turnOffSyncConfirmTitle = NSLocalizedString("preferences.sync.turn-off.confirm.title", bundle: Bundle.module, value: "Turn off sync?", comment: "Turn off sync confirmation dialog title")
    static let turnOffSyncConfirmMessage = NSLocalizedString("preferences.sync.turn-off.confirm.message", bundle: Bundle.module, value: "This device will no longer be able to access your synced data.", comment: "Turn off sync confirmation dialog message")
    static let thisDevice = NSLocalizedString("preferences.sync.this-device", bundle: Bundle.module, value: "This Device", comment: "Indicator of a current user's device on the list")
    static let currentDeviceDetails = NSLocalizedString("preferences.sync.current-device-details", bundle: Bundle.module, value: "Details...", comment: "Sync Settings device details button")

    // Sync errors
    static let bookmarksLimitExceededAction = NSLocalizedString("prefrences.sync.bookmarks-limit-exceeded-action", bundle: Bundle.module, value: "Manage Bookmarks", comment: "Button title for sync bookmarks limits exceeded warning to go to manage bookmarks")
    static let credentialsLimitExceededAction = NSLocalizedString("prefrences.sync.credentials-limit-exceeded-action", bundle: Bundle.module, value: "Manage passwords…", comment: "Button title for sync credentials limits exceeded warning to go to manage passwords")
    static let creditCardsLimitExceededAction = NSLocalizedString("prefrences.sync.credit-cards-limit-exceeded-action", value: "Manage credit cards…", comment: "Button title for sync credit cards limits exceeded warning to go to manage payment methods")
    static let identitiesLimitExceededAction = NSLocalizedString("prefrences.sync.identities-limit-exceeded-action", value: "Manage identities…", comment: "Button title for sync identities limits exceeded warning to go to manage identities")
    static let invalidBookmarksPresentTitle = NSLocalizedString("prefrences.sync.invalid-bookmarks-present-title", bundle: Bundle.module, value: "Some bookmarks are not syncing due to excessively long content in certain fields.", comment: "Alert title for invalid bookmarks being filtered out of synced data")
    static let invalidCredentialsPresentTitle = NSLocalizedString("prefrences.sync.invalid-credentials-present-title", bundle: Bundle.module, value: "Some passwords are not syncing due to excessively long content in certain fields.", comment: "Alert title for invalid logins being filtered out of synced data")
    static let invalidCreditCardsPresentTitle = NSLocalizedString("prefrences.sync.invalid-credit-cards-present-title", bundle: Bundle.module, value: "Some credit cards are not syncing due to excessively long content in certain fields.", comment: "Alert title for invalid credit cards being filtered out of synced data")
    static let invalidIdentitiesPresentTitle = NSLocalizedString("prefrences.sync.invalid-identities-present-title", bundle: Bundle.module, value: "Some identities are not syncing due to excessively long content in certain fields.", comment: "Alert title for invalid identities being filtered out of synced data")

    static func invalidBookmarksPresentDescription(_ invalidItemTitle: String, numberOfInvalidItems: Int) -> String {
        guard numberOfInvalidItems > 1 else {
            let message = NSLocalizedString(
                "prefrences.sync.invalid-bookmarks-present-description-one",
                bundle: Bundle.module,
                value: "Your bookmark for %@ can't sync because one of its fields exceeds the character limit.",
                comment: "Alert message for 1 invalid bookmark being filtered out of synced data"
            )
            return String(format: message, invalidItemTitle)
        }
        let message = NSLocalizedString(
            "prefrences.sync.invalid-bookmarks-present-description-many",
            bundle: Bundle.module,
            value: "Some bookmarks (%d) can't sync because some of their fields exceed the character limit.",
            comment: "Alert message for multiple invalid bookmark being filtered out of synced data"
        )
        return String(format: message, numberOfInvalidItems)
    }

    static func invalidCredentialsPresentDescription(_ invalidItemTitle: String, numberOfInvalidItems: Int) -> String {
        guard numberOfInvalidItems > 1 else {
            let message = NSLocalizedString(
                "prefrences.sync.invalid-credentials-present-description-one",
                bundle: Bundle.module,
                value: "Your password for %@ can't sync because one of its fields exceeds the character limit.",
                comment: "Alert message for 1 invalid login being filtered out of synced data"
            )
            return String(format: message, invalidItemTitle)
        }
        let message = NSLocalizedString(
            "prefrences.sync.invalid-credentials-present-description-many",
            bundle: Bundle.module,
            value: "Some passwords (%d) can't sync because some of their fields exceed the character limit.",
            comment: "Alert message for multiple invalid logins being filtered out of synced data"
        )
        return String(format: message, numberOfInvalidItems)
    }

    static func invalidCreditCardsPresentDescription(_ invalidItemTitle: String, numberOfInvalidItems: Int) -> String {
        guard numberOfInvalidItems > 1 else {
            let message = NSLocalizedString(
                "prefrences.sync.invalid-credit-cards-present-description-one",
                bundle: Bundle.module,
                value: "Your credit card %@ can't sync because one of its fields exceeds the character limit.",
                comment: "Alert message for 1 invalid credit card being filtered out of synced data"
            )
            return String(format: message, invalidItemTitle)
        }
        let message = NSLocalizedString(
            "prefrences.sync.invalid-credit-cards-present-description-many",
            bundle: Bundle.module,
            value: "Some credit cards (%d) can't sync because some of their fields exceed the character limit.",
            comment: "Alert message for multiple invalid credit cards being filtered out of synced data"
        )
        return String(format: message, numberOfInvalidItems)
    }

    static func invalidIdentitiesPresentDescription(_ invalidItemTitle: String, numberOfInvalidItems: Int) -> String {
        guard numberOfInvalidItems > 1 else {
            let message = NSLocalizedString(
                "prefrences.sync.invalid-identities-present-description-one",
                bundle: Bundle.module,
                value: "Your identity for %@ can't sync because one of its fields exceeds the character limit.",
                comment: "Alert message for 1 invalid credit card being filtered out of synced data"
            )
            return String(format: message, invalidItemTitle)
        }
        let message = NSLocalizedString(
            "prefrences.sync.invalid-identities-present-description-many",
            bundle: Bundle.module,
            value: "Some identities (%d) can't sync because some of their fields exceed the character limit.",
            comment: "Alert message for multiple invalid identities being filtered out of synced data"
        )
        return String(format: message, numberOfInvalidItems)
    }

    static let syncErrorAlertTitle = NSLocalizedString("alert.sync-error", bundle: Bundle.module, value: "Sync & Backup Error", comment: "Title for sync error alert")
    static let syncFailedTitle = NSLocalizedString("alert.sync-failed-title", bundle: Bundle.module, value: "Sync failed.", comment: "Title for generic Sync setup failure alerts")
    static let syncFailedDescription = NSLocalizedString("alert.sync-failed-description", bundle: Bundle.module, value: "Please try again.", comment: "Description for generic Sync setup failure alerts")
    static let syncSetupErrorGotItButton = NSLocalizedString("alert.sync-setup-error-got-it-button", bundle: Bundle.module, value: "Got It", comment: "Button title for Sync setup error alerts")
    static let syncDeviceAuthenticationErrorAlertTitle = NSLocalizedString("alert.sync-device-auth-error", bundle: Bundle.module, value: "Sync & Backup Error", comment: "Title for an error alert")
    static let syncDeviceAuthenticationErrorAlertButton = NSLocalizedString("alert.sync-device-auth-error-button", bundle: Bundle.module, value: "Go to Settings", comment: "Button Title of an error alert")
    static let unableToAuthenticateDevice = NSLocalizedString("alert.unable-to-authenticate-device", bundle: Bundle.module, value: "A device password is required to use Sync & Backup.", comment: "Description for  unable to authenticate error")
    static let unableToRecognizeCodeTitle = NSLocalizedString("alert.unable-to-scan-qr-code-title", bundle: Bundle.module, value: "This is not a valid Sync code.", comment: "Title for unable to scan qr code error")
    public static let unableToRecognizeCode = NSLocalizedString("alert.unable-to-scan-qr-code-description", bundle: Bundle.module, value: "Please make sure the correct code was entered or scanned.", comment: "Description for unable to scan qr code error")
    static let syncUpdateRequiredTitle = NSLocalizedString("alert.sync-update-required-title", bundle: Bundle.module, value: "Update the DuckDuckGo browser and try again.", comment: "Title for Sync error shown when the app version does not support the scanned Sync code")
    static let syncUnsupportedThirdPartyRecoveryCodeTitle = NSLocalizedString("alert.sync-code-only-compatible-with-duckai-title", bundle: Bundle.module, value: "Scan this code using a browser other than DuckDuckGo.", comment: "Title for Sync error shown when a third-party recovery code can only be used with Duck.ai")
    static let syncUnsupportedThirdPartyRecoveryCodeDescription = NSLocalizedString("alert.sync-code-only-compatible-with-duckai-description", bundle: Bundle.module, value: "In your other browser, visit Duck.ai, go to Settings, then under “Sync & Backup” select “Turn On” and then “Sync with another device”.", comment: "Description for Sync error shown when a third-party recovery code can only be used with Duck.ai")
    static let syncThirdPartyAccountAlreadyUpgradedDescription = NSLocalizedString("alert.sync-from-another-connected-device-description", bundle: Bundle.module, value: "Please Sync this device from an already-connected DuckDuckGo browser on another device.", comment: "Description for Sync error shown when a third-party account already has a native DuckDuckGo Sync credential")
    static let syncAlreadyPairedWithAccountTitle = NSLocalizedString("alert.sync-already-paired-with-account-title", bundle: Bundle.module, value: "Already synced.", comment: "Title for Sync error shown when both devices are already paired with the same account")
    static let syncAlreadyPairedWithAccountDescription = NSLocalizedString("alert.sync-already-paired-with-account-description", bundle: Bundle.module, value: "These devices are already connected to Sync & Backup.", comment: "Description for Sync error shown when both devices are already paired with the same account")
    static let syncAlreadyPairedWithAccountButton = NSLocalizedString("alert.sync-already-paired-with-account-button", bundle: Bundle.module, value: "Got It", comment: "Button title for Sync error shown when both devices are already paired with the same account")
    static let syncCancelledFromOtherDeviceTitle = NSLocalizedString("alert.sync-cancelled-from-other-device-title", bundle: Bundle.module, value: "Sync canceled from your other device.", comment: "Title for Sync error shown when setup is canceled from the other device")
    static let syncCancelledFromOtherDeviceDescription = NSLocalizedString("alert.sync-cancelled-from-other-device-description", bundle: Bundle.module, value: "Please try again.", comment: "Description for Sync error shown when setup is canceled from the other device")
    static let syncCancelledFromOtherDeviceButton = NSLocalizedString("alert.sync-cancelled-from-other-device-button", bundle: Bundle.module, value: "Got It", comment: "Button title for Sync error shown when setup is canceled from the other device")
    static let unableToSyncToServerDescription = NSLocalizedString("alert.unable-to-sync-to-server-description", bundle: Bundle.module, value: "Unable to connect to the server.", comment: "Description for unable to sync to server error")
    static let unableToMergeTwoAccountsDescription = NSLocalizedString("alert.unable-to-merge-two-accounts-description", bundle: Bundle.module, value: "To pair these devices, turn off Sync & Backup on one device then tap \"Sync With Another Device\" on the other device.", comment: "Description for unable to merge two accounts error")
    static let unableToUpdateDeviceNameDescription = NSLocalizedString("alert.unable-to-update-device-name-description", bundle: Bundle.module, value: "Unable to update the device name.", comment: "Description for unable to update device name error")
    static let unableToTurnSyncOffDescription = NSLocalizedString("alert.unable-to-turn-sync-off-description", bundle: Bundle.module, value: "Unable to turn Sync & Backup off.", comment: "Description for unable to turn sync off error")
    static let unableToDeleteDataDescription = NSLocalizedString("alert.unable-to-delete-data-description", bundle: Bundle.module, value: "Unable to delete data on the server.", comment: "Description for unable to delete data error")
    static let unableToRemoveDeviceDescription = NSLocalizedString("alert.unable-to-remove-device-description", bundle: Bundle.module, value: "Unable to remove this device from Sync & Backup.", comment: "Description for unable to remove device error")
    static let invalidCodeDescription = NSLocalizedString("alert.invalid-code-description", bundle: Bundle.module, value: "Please make sure the correct code was entered or scanned.", comment: "Description for invalid code error")
    static let unableCreateRecoveryPdfDescription = NSLocalizedString("alert.unable-to-create-recovery-pdf-description", bundle: Bundle.module, value: "Unable to create the recovery PDF.", comment: "Description for unable to create recovery pdf error")

    public static let syncAlertSwitchAccountTitle = NSLocalizedString("alert.sync-switch-account-button", value: "Switch to a different Sync?", comment: "Switch account title in alert")
    public static let syncAlertSwitchAccountMessage = NSLocalizedString("alert.sync-switch-account-message", value: "This device is already synced, are you sure you want to sync it with a different backup or device? Switching won't remove any data already synced to this device.", comment: "Description for switching sync accounts when there's two")
    public static let syncAlertSwitchAccountButton = NSLocalizedString("alert.sync-switch-sync-button", value: "Switch Sync", comment: "Switch account button in alert")

    static let fetchFaviconsOnboardingTitle = NSLocalizedString("prefrences.sync.fetch-favicons-onboarding-title", bundle: Bundle.module, value: "Download Missing Icons?", comment: "Title for fetch favicons onboarding dialog")
    static let fetchFaviconsOnboardingMessage = NSLocalizedString("prefrences.sync.fetch-favicons-onboarding-message", bundle: Bundle.module, value: "Do you want this device to automatically download icons for any new bookmarks synced from your other devices? This will expose the download to your network any time a bookmark is synced.", comment: "Text for fetch favicons onboarding dialog")
    static let keepFaviconsUpdated = NSLocalizedString("prefrences.sync.keep-favicons-updated", bundle: Bundle.module, value: "Keep Bookmarks Icons Updated", comment: "Title of the confirmation button for favicons fetching")

    // Sync Feature Flags
    static let syncUnavailableTitle = NSLocalizedString("sync.warning.sync-unavailable", bundle: Bundle.module, value: "Sync & Backup is Unavailable", comment: "Title of the warning message that sync and backup are unavailable")
    static let syncPausedTitle = NSLocalizedString("sync.warning.sync-paused", bundle: Bundle.module, value: "Sync & Backup is Paused", comment: "Title of the warning message that Sync & Backup is Paused")
    static let syncUnavailableMessage = NSLocalizedString("sync.warning.sync-unavailable-message", bundle: Bundle.module, value: "Sorry, but Sync & Backup is currently unavailable. Please try again later.", comment: "Data syncing unavailable warning message")
    static let syncUnavailableMessageUpgradeRequired = NSLocalizedString("sync.warning.data-syncing-disabled-upgrade-required", bundle: Bundle.module, value: "Sorry, but Sync & Backup is no longer available in this app version. Please update DuckDuckGo to the latest version to continue.", comment: "Data syncing unavailable warning message")
}

// Use this instead of NSLocalizedString for strings that are not supposed to be translated
// swiftlint:disable:next identifier_name
public func NotLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = Bundle.main, value: String = "", comment: String) -> String {
    return value
}
