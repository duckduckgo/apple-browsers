//
//  MenuCommandAvailability.swift
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

struct MenuCommandAvailability {
    struct State {
        enum Presentation {
            case browser, tabSwitcher, passwords, downloads, bookmarks, settings, blockingModal
        }

        let shortcutsEnabled: Bool
        let presentation: Presentation
        var hasTab = false
        var hasWebsite = false
        var isLoading = false
        var findActive = false
        var omnibarEditing = false
        var fireModeEnabled = false
        var voiceSearchEnabled = false
        var passwordsEnabled = false
        var canHideTabs = true
        var tabCount = 0
        var canGoBack = false
        var canGoForward = false
    }

    let state: State

    func isEnabled(_ command: MainMenuCommand) -> Bool {
        guard state.shortcutsEnabled, state.presentation != .blockingModal else { return false }
        switch command {
        case .showTabs:
            return state.presentation != .tabSwitcher || state.canHideTabs
        case .showPasswords:
            return state.passwordsEnabled && (state.presentation != .tabSwitcher || state.canHideTabs)
        case .showDownloads, .showBookmarks, .importBookmarks, .exportBookmarks, .openBookmark:
            return state.presentation != .tabSwitcher || state.canHideTabs
        case .about:
            guard state.presentation != .tabSwitcher || state.canHideTabs else { return false }
            return state.presentation == .browser || state.presentation == .tabSwitcher || state.presentation == .settings
        case .settings, .feedback:
            guard state.presentation != .tabSwitcher || state.canHideTabs else { return false }
            return state.presentation == .browser || state.presentation == .tabSwitcher
        case .newTab:
            return state.presentation == .browser || state.presentation == .tabSwitcher
        case .newFireTab:
            return state.fireModeEnabled && (state.presentation == .browser || state.presentation == .tabSwitcher)
        case .closeTab:
            return state.presentation == .tabSwitcher ? state.canHideTabs : state.presentation == .browser && state.hasTab
        case .fire:
            return state.presentation == .browser || state.presentation == .tabSwitcher
        default:
            guard state.presentation == .browser else { return false }
        }
        switch command {
        case .addBookmark, .addFavorite: return state.hasWebsite
        case .voiceSearch: return state.voiceSearchEnabled
        case .location, .newTabOnRight: return true
        case .duplicateTab: return state.hasTab
        case .stop: return state.isLoading
        case .reload: return state.hasWebsite
        case .openLink, .openBackgroundLink: return false
        case .share, .printPage, .find, .zoomIn, .zoomOut, .actualSize:
            return state.hasWebsite && !state.omnibarEditing
        case .findNext, .findPrevious: return state.hasWebsite && state.findActive && !state.omnibarEditing
        case .previousTab, .nextTab: return state.tabCount > 1
        case .selectTab: return state.tabCount > 0
        case .back: return state.canGoBack && !state.omnibarEditing
        case .forward: return state.canGoForward && !state.omnibarEditing
        default: return false
        }
    }

    func title(for command: MainMenuCommand) -> String? {
        switch command {
        case .showTabs: return state.presentation == .tabSwitcher ? UserText.menuHideTabs : UserText.menuShowTabs
        case .showPasswords: return state.presentation == .passwords ? UserText.menuHidePasswords : UserText.menuShowPasswords
        case .showBookmarks: return state.presentation == .bookmarks ? UserText.menuHideBookmarks : UserText.menuShowBookmarks
        case .showDownloads: return state.presentation == .downloads ? UserText.menuHideDownloads : UserText.menuShowDownloads
        default: return nil
        }
    }
}
