//
//  SyncTurnOffPixel.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import SyncUI_iOS

enum SyncTurnOffPixel: PixelKit.Event {

    case sheetShown
    case optionSelected(SyncSettingsViewModel.TurnOffSyncOption)
    case deleteServerDataConfirmationConfirmed
    case deleteServerDataConfirmationDismissed

    var name: String {
        switch self {
        case .sheetShown: return "sync_turn_off_sheet_shown"
        case .optionSelected: return "sync_turn_off_option_selected"
        case .deleteServerDataConfirmationConfirmed: return "sync_delete_server_data_confirmation_confirmed"
        case .deleteServerDataConfirmationDismissed: return "sync_delete_server_data_confirmation_dismissed"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .optionSelected(let option):
            return ["option": option.rawValue]
        case .sheetShown, .deleteServerDataConfirmationConfirmed, .deleteServerDataConfirmationDismissed:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
