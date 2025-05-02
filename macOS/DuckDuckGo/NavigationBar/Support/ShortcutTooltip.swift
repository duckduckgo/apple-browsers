//
//  ShortcutTooltip.swift
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

enum ShortcutTooltip {
    case back
    case forward
    case reload
    case stopLoading
    case downloads
    case home
    case bookmarkThisPage

    private var shortcut: String {
        switch self {
        case .back:
            return "⌘["
        case .forward:
            return "⌘]"
        case .reload:
            return "⌘R"
        case .downloads:
            return "⌘J"
        case .stopLoading:
            return ""
        case .home:
            return "⇧⌘H"
        case .bookmarkThisPage:
            return "⌘D"
        }
    }

    private var spacedShortcut: String {
        return " " + shortcut
    }

    var value: String {
        switch self {
        case .back:
            return UserText.navigateBackTooltipHeader + spacedShortcut + "\n" + UserText.navigateBackTooltipFooter
        case .forward:
            return UserText.navigateForwardTooltipHeader + spacedShortcut + "\n" + UserText.navigateForwardTooltipFooter
        case .reload:
            return UserText.refreshPageTooltip + spacedShortcut
        case .downloads:
            return UserText.downloadsShortcutTooltip + spacedShortcut
        case .stopLoading:
            return UserText.stopLoadingTooltip
        case .home:
            return UserText.homeButtonTooltip + spacedShortcut
        case .bookmarkThisPage:
            return UserText.addBookmarkTooltip + spacedShortcut
        }
    }
}
