//
//  SyncDeviceDetailsPixel.swift
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

enum SyncDeviceDetailsPixel: PixelKit.Event {

    case thisDeviceScreenShown
    case thisDeviceNameUpdated
    case thisDeviceTurnOffSyncTapped
    case otherDeviceScreenShown
    case otherDeviceRemoveDeviceTapped

    var name: String {
        switch self {
        case .thisDeviceScreenShown: return "sync_settings_this_device_details_screen_shown"
        case .thisDeviceNameUpdated: return "sync_settings_this_device_details_name_updated"
        case .thisDeviceTurnOffSyncTapped: return "sync_settings_this_device_details_turn_off_sync_tapped"
        case .otherDeviceScreenShown: return "sync_settings_other_device_details_screen_shown"
        case .otherDeviceRemoveDeviceTapped: return "sync_settings_other_device_details_remove_device_tapped"
        }
    }

    var parameters: [String: String]? { nil }
    var standardParameters: [PixelKitStandardParameter]? { nil }
    var namePrefix: PixelKitNamePrefix { .none }
}
