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
            return "m_mac_fire_started"
        case .fireStartedInSession:
            return "m_mac_fire_started_in-session"
        case .burn(let mode):
            return "m_mac_fire_burn_\(mode.rawValue)"
        case .fireDialogToggleMode:
            return "m_mac_fire_dialog_toggle_mode"
        case .fireDialogChangeSettings:
            return "m_mac_fire_dialog_change_settings"
        case .fireDialogToggleCloseTabs:
            return "m_mac_fire_dialog_toggle_close_tabs"
        case .fireDialogToggleClearHistory:
            return "m_mac_fire_dialog_toggle_clear_history"
        case .fireDialogToggleClearSiteData:
            return "m_mac_fire_dialog_toggle_clear_site_data"
        case .fireDialogToggleClearAIChats:
            return "m_mac_fire_dialog_toggle_clear_ai_chats"
        case .fireDialogDeleteIndividualSitesClicked:
            return "m_mac_fire_dialog_delete_individual_sites_clicked"
        case .fireDialogManageFireproofedSites:
            return "m_mac_fire_dialog_manage_fireproofed_sites"
        case .fireDialogCancel:
            return "m_mac_fire_dialog_cancel"
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }

    var parameters: [String : String]? {
        switch self {

        case .fireStarted,
                .fireStartedInSession,
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
            let closeTab: Bool
            let clearHistory: Bool
            let clearSiteData: Bool

            var dictionaryRepresentation: [String: String] {
                [
                    "has_pinned_tabs": String(hasPinnedTabs),
                    "close_tab": String(closeTab),
                    "clear_history": String(clearHistory),
                    "clear_site_data": String(clearSiteData)
                ]
            }
        }

        struct AllDataParameters: Encodable {
            let hasPinnedTabs: Bool
            let closeTab: Bool
            let clearHistory: Bool
            let clearSiteData: Bool
            let clearAIChats: Bool

            var dictionaryRepresentation: [String: String] {
                [
                    "has_pinned_tabs": String(hasPinnedTabs),
                    "close_tab": String(closeTab),
                    "clear_history": String(clearHistory),
                    "clear_site_data": String(clearSiteData),
                    "clear_ai_chats": String(clearAIChats)
                ]
            }
        }
    }
}
