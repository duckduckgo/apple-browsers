//
//  PinnedTabsPixel.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/**
 * This enum keeps pixels related to pinned tabs
 */
enum PinnedTabsPixel: PixelKitEvent {

    case userPinnedTab
    case userUnpinnedTab
    case userSwitchedToPerWindowPinnedTabs
    case userSwitchedToSharedPinnedTabs

    var name: String {
        switch self {
        case .userPinnedTab:
            return "user_pinned_tab"
        case .userUnpinnedTab:
            return "user_unpinned_tab"
        case .userSwitchedToPerWindowPinnedTabs:
            return "user_switched_to_per_window_pinned_tabs"
        case .userSwitchedToSharedPinnedTabs:
            return "user_switched_to_shared_pinned_tabs"
        }
    }

    var parameters: [String: String]? {
        nil
    }

}
