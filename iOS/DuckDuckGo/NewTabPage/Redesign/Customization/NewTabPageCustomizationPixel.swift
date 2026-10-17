//
//  NewTabPageCustomizationPixel.swift
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

enum NewTabPageCustomizationPixel: PixelKit.Event {

    case opened
    case favoritesToggled
    case messagesToggled
    case keyboardToggled
    case allSettingsOpened

    var name: String {
        switch self {
        case .opened: return "new-tab-page_customization_opened"
        case .favoritesToggled: return "new-tab-page_customization_favorites_toggled"
        case .messagesToggled: return "new-tab-page_customization_messages_toggled"
        case .keyboardToggled: return "new-tab-page_customization_keyboard_toggled"
        case .allSettingsOpened: return "new-tab-page_customization_all_settings_opened"
        }
    }

    var parameters: [String: String]? { nil }
    var standardParameters: [PixelKitStandardParameter]? { nil }
    var namePrefix: PixelKitNamePrefix { .none }
}
