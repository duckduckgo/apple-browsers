//
//  SyncPixels.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import PixelKit
import DDGSync

enum SyncFeatureUsagePixels: PixelKitEventV2 {
    private enum ParameterKeys {
        static let connectedDevices = "connected_devices"
    }

    case syncDisabled
    case syncDisabledAndDeleted(connectedDevices: Int)

    var name: String {
        switch self {
        case .syncDisabled: return "sync_disabled"
        case .syncDisabledAndDeleted: return "sync_disabledanddeleted"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .syncDisabledAndDeleted(let connectedDevices):
            return [ParameterKeys.connectedDevices: String(connectedDevices)]
        case .syncDisabled:
            return nil
        }
    }

    var error: (any Error)? {
        nil
    }
}

enum SyncSwitchAccountPixelKitEvent: PixelKitEventV2 {
    case syncAskUserToSwitchAccount
    case syncUserAcceptedSwitchingAccount
    case syncUserCancelledSwitchingAccount
    case syncUserSwitchedAccount
    case syncUserSwitchedLogoutError
    case syncUserSwitchedLoginError

    var name: String {
        switch self {
        case .syncAskUserToSwitchAccount: return "sync_ask_user_to_switch_account"
        case .syncUserAcceptedSwitchingAccount: return "sync_user_accepted_switching_account"
        case .syncUserCancelledSwitchingAccount: return "sync_user_cancelled_switching_account"
        case .syncUserSwitchedAccount: return "sync_user_switched_account"
        case .syncUserSwitchedLogoutError: return "sync_user_switched_logout_error"
        case .syncUserSwitchedLoginError: return "sync_user_switched_login_error"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var error: (any Error)? {
        nil
    }

    var withoutMacPrefix: NonStandardEvent {
        NonStandardEvent(self)
    }
}

enum SyncSetupPixelKitEvent: PixelKitEventV2 {

    enum ParameterKey {
        static let source = "source"
    }

    case syncSetupBarcodeScreenShown(SyncSetupSource)
    case syncSetupBarcodeCodeCopied(SyncSetupSource)
    case syncSetupManualCodeEntryScreenShown
    case syncSetupManualCodeEnteredSuccess(SyncSetupSource)
    case syncSetupManualCodeEnteredFailed
    case syncSetupEndedAbandoned(SyncSetupSource)
    case syncSetupEndedSuccessful(SyncSetupSource)

    var name: String {
        switch self {
        case .syncSetupBarcodeScreenShown: return "sync_setup_barcode_screen_shown"
        case .syncSetupBarcodeCodeCopied: return "sync_setup_barcode_code_copied"
        case .syncSetupManualCodeEntryScreenShown: return "sync_setup_manual_code_entry_screen_shown"
        case .syncSetupManualCodeEnteredSuccess: return "sync_setup_manual_code_entered_success"
        case .syncSetupManualCodeEnteredFailed: return "sync_setup_manual_code_entered_failed"
        case .syncSetupEndedAbandoned: return "sync_setup_ended_abandoned"
        case .syncSetupEndedSuccessful: return "sync_setup_ended_successful"
        }
    }

    var parameters: [String: String]? {
        guard let source else { return nil }
        return [ParameterKey.source: source.rawValue]
    }

    var error: (any Error)? {
        nil
    }

    var withoutMacPrefix: NonStandardEvent {
        NonStandardEvent(self)
    }

    private var source: SyncSetupSource? {
        switch self {
        case
            .syncSetupBarcodeScreenShown(let source),
            .syncSetupBarcodeCodeCopied(let source),
            .syncSetupManualCodeEnteredSuccess(let source),
            .syncSetupEndedAbandoned(let source),
            .syncSetupEndedSuccessful(let source):
            return source
        case
            .syncSetupManualCodeEntryScreenShown,
            .syncSetupManualCodeEnteredFailed:
            return nil
        }
    }
}
