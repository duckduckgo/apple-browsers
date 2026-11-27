//
//  AppStoreDockRolloutPixel.swift
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

import Foundation
import PixelKit

/// Temporary pixels for the App Store combined "Set as Default & Add to Dock" prompt rollout.
/// Remove with the rest of `AppStoreDockRollout/` once the rollout decision is made.
/// See definitions in `default-browser-and-dock-prompt-app-store-rollout.json5`.
enum AppStoreDockRolloutPixel: PixelKit.Event, Equatable {

    enum Arm: String, Codable {
        case combined
        case setAsDefault = "set-as-default"
    }

    case promptShown(Arm)
    case setAsDefaultRequested(Arm)
    case inDockAfterSevenDays(Arm)
    case notInDockAfterSevenDays(Arm)

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .promptShown(let arm):
            return "app-store-dock-rollout_\(arm.rawValue)_prompt-shown_macos"
        case .setAsDefaultRequested(let arm):
            return "app-store-dock-rollout_\(arm.rawValue)_default-requested_macos"
        case .inDockAfterSevenDays(let arm):
            return "app-store-dock-rollout_\(arm.rawValue)_in-dock-7d_macos"
        case .notInDockAfterSevenDays(let arm):
            return "app-store-dock-rollout_\(arm.rawValue)_not-in-dock-7d_macos"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var standardParameters: [PixelKitStandardParameter]? {
        nil
    }
}

enum AppStoreDockRolloutDebugPixel: PixelKit.Event {

    case storeReadFailed(error: Error)
    case storeWriteFailed(error: Error)

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .storeReadFailed:
            return "app-store-dock-rollout_store_read-failed_macos"
        case .storeWriteFailed:
            return "app-store-dock-rollout_store_write-failed_macos"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var error: NSError? {
        switch self {
        case .storeReadFailed(let error), .storeWriteFailed(let error):
            return error as NSError
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        nil
    }
}
