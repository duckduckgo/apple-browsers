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
    enum Source: String {
        case exchange
        case connect
    }

    enum ParameterKey {
        static let source = "source"
    }

    case syncSetupBarcodeScreenShown(Source)
    case syncSetupBarcodeScannerSuccess(Source)
    case syncSetupBarcodeScannerFailed(Source)
    case syncSetupBarcodeCodeCopied(Source)
    case syncSetupManualCodeEntryScreenShown(Source)
    case syncSetupManualCodeEntered(Source)
    case syncSetupManualCodeEnteredFailed(Source)
    case syncSetupEndedAbandoned(Source)
    case syncSetupEndedSuccessful(Source)

    var name: String {
        switch self {
        case .syncSetupBarcodeScreenShown: return "sync_setup_barcode_screen_shown"
        case .syncSetupBarcodeScannerSuccess: return "sync_setup_barcode_scanner_success"
        case .syncSetupBarcodeScannerFailed: return "sync_setup_barcode_scanner_failed"
        case .syncSetupBarcodeCodeCopied: return "sync_setup_barcode_code_copied"
        case .syncSetupManualCodeEntryScreenShown: return "sync_setup_manual_code_entry_screen_shown"
        case .syncSetupManualCodeEntered: return "sync_setup_manual_code_entered"
        case .syncSetupManualCodeEnteredFailed: return "sync_setup_manual_code_entered_failed"
        case .syncSetupEndedAbandoned: return "sync_setup_ended_abandoned"
        case .syncSetupEndedSuccessful: return "sync_setup_ended_successful"
        }
    }

    var parameters: [String: String]? {
        return [ParameterKey.source: source.rawValue]
    }

    var error: (any Error)? {
        nil
    }

    var withoutMacPrefix: NonStandardEvent {
        NonStandardEvent(self)
    }

    private var source: Source {
        switch self {
        case
            .syncSetupBarcodeScreenShown(let source),
            .syncSetupBarcodeScannerSuccess(let source),
            .syncSetupBarcodeScannerFailed(let source),
            .syncSetupBarcodeCodeCopied(let source),
            .syncSetupManualCodeEntryScreenShown(let source),
            .syncSetupManualCodeEntered(let source),
            .syncSetupManualCodeEnteredFailed(let source),
            .syncSetupEndedAbandoned(let source),
            .syncSetupEndedSuccessful(let source):
            return source
        }
    }
}
