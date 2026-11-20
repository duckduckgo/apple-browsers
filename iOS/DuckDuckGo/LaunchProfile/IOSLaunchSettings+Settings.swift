//
//  IOSLaunchSettings+Settings.swift
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

#if DEBUG || ALPHA

import Foundation
import LaunchProfile

/// Settings screen options, written through `AppSettings` exactly as the Settings screen writes them.
extension IOSLaunchSettings {

    static func settingsScreen(_ settings: AppSettings) -> [LaunchSetting] {
        [addressBarPosition(settings),
         theme(settings),
         textZoom(settings),
         fireAnimation(settings),
         autoClearOptions(settings),
         autoClearTiming(settings)]
    }

    static func addressBarPosition(_ settings: AppSettings) -> LaunchSetting {
        .choice("settings.addressBarPosition",
                summary: "Puts the address bar at the top or bottom. iPad always uses the top.",
                options: AddressBarPosition.allCases,
                name: \.rawValue) { settings.currentAddressBarPosition = $0 }
    }

    static func theme(_ settings: AppSettings) -> LaunchSetting {
        .choice("settings.theme", summary: "App theme.", options: ThemeStyle.allCases, name: \.rawValue) { settings.currentThemeStyle = $0 }
    }

    static func textZoom(_ settings: AppSettings) -> LaunchSetting {
        .choice("settings.textZoom", summary: "Text size for websites, in percent.", options: TextZoomLevel.allCases, name: \.rawValue) {
            settings.defaultTextZoomLevel = $0
        }
    }

    static func fireAnimation(_ settings: AppSettings) -> LaunchSetting {
        .choice("settings.fireAnimation",
                summary: "Animation played by the Fire button.",
                options: FireButtonAnimationType.allCases,
                name: \.rawValue) { settings.currentFireButtonAnimation = $0 }
    }

    static func autoClearOptions(_ settings: AppSettings) -> LaunchSetting {
        let options: [String: FireRequest.Options] = ["tabs": .tabs, "data": .data, "aiChats": .aiChats]
        let allowed = options.keys.sorted().joined(separator: ", ")
        return LaunchSetting("settings.autoClear.options",
                             summary: "What Automatically Clear Data clears: any of \(allowed). An empty list turns it off.",
                             parse: { (names: [String]) in
            try names.reduce(into: FireRequest.Options()) { cleared, name in
                guard let option = options[name] else { throw LaunchSettingInvalidValue("use any of \(allowed).") }
                cleared.insert(option)
            }
        }, write: { settings.autoClearAction = $0 })
    }

    static func autoClearTiming(_ settings: AppSettings) -> LaunchSetting {
        let timings: [AutoClearSettingsModel.Timing] = [.termination, .delay5min, .delay15min, .delay30min, .delay60min]
        return .choice("settings.autoClear.timing",
                       summary: "When Automatically Clear Data runs.",
                       options: timings,
                       name: { String(describing: $0) }) { settings.autoClearTiming = $0 }
    }
}

#endif
