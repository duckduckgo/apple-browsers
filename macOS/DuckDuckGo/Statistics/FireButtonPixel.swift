//
//  FireButtonPixel.swift
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

/// Making it easier to find in the codebase.
typealias FireDialogPixel = FireButtonPixel

/// This enum keeps pixels related to Fire Button and Fire Dialog.
enum FireButtonPixel: PixelKitEvent {
    case fireStarted
    case fireStartedInSession
    case fireStartedOnExit
    case fireStartedOnStartup
    case burn(_ mode: BurnMode)
    case fireDialogToggleMode
    case fireDialogChangeSettings
    case fireDialogToggleCloseTabs
    case fireDialogToggleClearHistory
    case fireDialogToggleClearSiteData
    case fireDialogToggleClearAIChats
    case fireDialogDeleteIndividualSitesClicked
    case fireDialogManageFireproofedSites
    case fireDialogCancel

    var name: String {
        switch self {
        case .fireStarted:
            return "fire_started_macos"
        case .fireStartedInSession:
            return "fire_started_in-session_macos"
        case .fireStartedOnExit:
            return "fire_started_on-exit_macos"
        case .fireStartedOnStartup:
            return "fire_started_on-startup_macos"
        case .burn(let mode):
            return "fire_burn_\(mode.rawValue)_macos"
        case .fireDialogToggleMode:
            return "fire_dialog_toggle_mode_macos"
        case .fireDialogChangeSettings:
            return "fire_dialog_change_settings_macos_u"
        case .fireDialogToggleCloseTabs:
            return "fire_dialog_toggle_close_tabs_macos"
        case .fireDialogToggleClearHistory:
            return "fire_dialog_toggle_clear_history_macos"
        case .fireDialogToggleClearSiteData:
            return "fire_dialog_toggle_clear_site_data_macos"
        case .fireDialogToggleClearAIChats:
            return "fire_dialog_toggle_clear_ai_chats_macos"
        case .fireDialogDeleteIndividualSitesClicked:
            return "fire_dialog_delete_individual_sites_clicked_macos"
        case .fireDialogManageFireproofedSites:
            return "fire_dialog_manage_fireproofed_sites_macos"
        case .fireDialogCancel:
            return "fire_dialog_cancel_macos"
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }

    var parameters: [String: String]? {
        switch self {

        case .fireStarted,
                .fireStartedInSession,
                .fireStartedOnExit,
                .fireStartedOnStartup,
                .fireDialogToggleMode,
                .fireDialogChangeSettings,
                .fireDialogToggleCloseTabs,
                .fireDialogToggleClearHistory,
                .fireDialogToggleClearSiteData,
                .fireDialogToggleClearAIChats,
                .fireDialogDeleteIndividualSitesClicked,
                .fireDialogManageFireproofedSites,
                .fireDialogCancel:
            return [:]

        case .burn(let mode):
            return mode.params
        }
    }

    // MARK: - Parameters

    enum BurnMode {
        case currentTab(CurrentTabParameters)
        case currentWindow(CurrentWindowParameters)
        case allData(AllDataParameters)
        case aiChats

        var rawValue: String {
            switch self {
            case .currentTab:
                return "current-tab"
            case .currentWindow:
                return "current-window"
            case .allData:
                return "all-sites"
            case .aiChats:
                return "ai-chats"
            }
        }

        var params: [String: String]? {
            switch self {
            case .currentTab(let params):
                return params.dictionaryRepresentation
            case .currentWindow(let params):
                return params.dictionaryRepresentation
            case .allData(let params):
                return params.dictionaryRepresentation
            case .aiChats:
                return nil
            }
        }

        struct CurrentTabParameters {
            let pinned: Bool
            let closeTab: Bool
            let clearHistory: Bool
            let clearSiteData: Bool

            var dictionaryRepresentation: [String: String] {
                [
                    "pinned": String(pinned),
                    "close_tab": String(closeTab),
                    "clear_history": String(clearHistory),
                    "clear_site_data": String(clearSiteData)
                ]
            }
        }

        struct CurrentWindowParameters: Encodable {
            let hasPinnedTabs: Bool
            let closeWindow: Bool
            let clearHistory: Bool
            let clearSiteData: Bool

            var dictionaryRepresentation: [String: String] {
                [
                    "has_pinned_tabs": String(hasPinnedTabs),
                    "close_window": String(closeWindow),
                    "clear_history": String(clearHistory),
                    "clear_site_data": String(clearSiteData)
                ]
            }
        }

        struct AllDataParameters: Encodable {
            let hasPinnedTabs: Bool
            let closeWindows: Bool
            let clearHistory: Bool
            let clearSiteData: Bool
            let clearAIChats: Bool

            var dictionaryRepresentation: [String: String] {
                [
                    "has_pinned_tabs": String(hasPinnedTabs),
                    "close_windows": String(closeWindows),
                    "clear_history": String(clearHistory),
                    "clear_site_data": String(clearSiteData),
                    "clear_ai_chats": String(clearAIChats)
                ]
            }
        }
    }
}
