//
//  NewTabPageSessionWideEventData.swift
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

import Foundation
import FoundationExtensions
import PixelKit

/// Wide-event payload for the New Tab Page session pixel
/// (`m_ios_wide_new_tab_page_session`). Captures one New Tab Page visit: which
/// actions the user took while it was on screen, and how the visit ended.
final class NewTabPageSessionWideEventData: WideEventData {

    static let metadata = WideEventMetadata(
        pixelName: "new_tab_page_session",
        featureName: "new-tab-page-session",
        mobileMetaType: "ios-new-tab-page-session",
        // API requires both; only mobileMetaType is read on iOS.
        desktopMetaType: "macos-new-tab-page-session",
        version: "1.1.0"
    )

    enum Trigger: String, Codable, CaseIterable {
        case appOpen = "app_open"
        case newTabOpened = "new_tab_opened"
        /// Separate from `newTabOpened` because the user asked to burn, not for a blank page.
        case newTabOpenedAfterFire = "new_tab_opened_after_fire"
    }

    /// The keyboard mode the app decided on when the visit started, not the live
    /// keyboard state later in the visit.
    enum LaunchKeyboardMode: String, Codable, CaseIterable {
        case up
        case down
    }

    /// The single action that ended the visit.
    enum TerminalAction: String, Codable, CaseIterable {
        case loadSerp = "load_serp"
        case loadSearchSuggestion = "load_search_suggestion"
        case loadWebsite = "load_website"
        case loadDuckai = "load_duckai"
        case loadDuckaiResponse = "load_duckai_response"
        case loadPreviousChat = "load_previous_chat"
        case lastTabLoaded = "last_tab_loaded"
        case selectOtherTab = "select_other_tab"
        case swipeToOtherTab = "swipe_to_other_tab"
        case deleteData = "delete_data"
        /// The customizable toolbar button, when set to something other than Fire.
        /// Only reachable while the New Tab Page icon customization flag is on.
        case customButton = "custom_button"
        case noActionTimeout = "no_action_timeout"
        case maxDurationExceeded = "max_duration_exceeded"
        case appBackgrounded = "app_backgrounded"
        case appTerminated = "app_terminated"

        /// Keeps the action-to-outcome mapping in one place rather than at each site
        /// that ends a visit.
        var status: WideEventStatus {
            switch self {
            case .loadSerp,
                 .loadSearchSuggestion,
                 .loadWebsite,
                 .loadDuckai,
                 .loadDuckaiResponse,
                 .loadPreviousChat,
                 .lastTabLoaded,
                 .selectOtherTab,
                 .swipeToOtherTab,
                 .deleteData,
                 .customButton:
                // No reason attached: the sender would copy it into
                // `status_reason`, duplicating `terminal_action` and forcing every
                // success value into the schema's `status_reason` enum.
                return .success
            case .noActionTimeout, .maxDurationExceeded:
                return .failure
            case .appBackgrounded:
                return .cancelled
            case .appTerminated:
                return .unknown(reason: rawValue)
            }
        }
    }

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var errorData: WideEventErrorData?

    var trigger: Trigger
    var launchKeyboardMode: LaunchKeyboardMode
    var toggleEnabled: Bool

    /// Carried explicitly rather than derived from `feature.status`, because the sender
    /// only writes a status reason for SUCCESS and UNKNOWN outcomes.
    var terminalAction: TerminalAction?

    var sessionInterval: WideEvent.MeasuredInterval
    var firstInteractionInterval: WideEvent.MeasuredInterval

    /// Lets the inactivity timeout be evaluated from the next observed event instead of
    /// keeping a timer running for the length of the visit.
    var lastActionAt: Date

    var actionCount: Int = 0

    var tapInputBar: Bool = false
    var typeInInput: Bool = false
    var switchToggleToSearch: Bool = false
    var switchToggleToAiChat: Bool = false
    var tapDuckaiButton: Bool = false
    var hitSubmit: Bool = false
    var chooseSuggestion: Bool = false
    var tapFavorite: Bool = false
    var tapFireButton: Bool = false
    var tapReturnToLast: Bool = false
    var tapTabViewerEscapeHatch: Bool = false
    var tapTabViewerToolbar: Bool = false
    var tapBookmarksToolbarItem: Bool = false
    var tapPasswordsToolbarItem: Bool = false
    var openMenu: Bool = false
    var menuBookmarks: Bool = false
    var menuPasswords: Bool = false
    var menuChats: Bool = false
    var menuDownloads: Bool = false
    var menuVpn: Bool = false
    var clickMessageCta: Bool = false
    var clickMessageDismiss: Bool = false
    var dismissKeyboard: Bool = false
    var scrollView: Bool = false
    var utiBackArrow: Bool = false
    var menuItemSelected: Bool = false
    var selectBookmark: Bool = false
    var selectPassword: Bool = false
    var selectDownload: Bool = false
    var emailCopied: Bool = false
    var vpnOn: Bool = false
    var vpnOff: Bool = false

    init(trigger: Trigger,
         launchKeyboardMode: LaunchKeyboardMode,
         toggleEnabled: Bool,
         startedAt: Date = Date(),
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.trigger = trigger
        self.launchKeyboardMode = launchKeyboardMode
        self.toggleEnabled = toggleEnabled
        self.sessionInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.firstInteractionInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.lastActionAt = startedAt
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    /// Orphaned visits are cleaned up by the instrumentation's own start hook, which runs
    /// synchronously before creating a new flow. This avoids a race with
    /// `WideEventService.resume()` where the launch cleanup task would complete a freshly
    /// created flow as UNKNOWN before the user has done anything.
    func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        .keepPending
    }

    /// After this long without a user action a visit counts as abandoned. It is still
    /// reported when it actually leaves the screen, so its duration can exceed this.
    static let noActionTimeout: TimeInterval = 30

    /// A visit is capped at this length, so a continuously active one cannot run forever.
    static let maxSessionDuration: TimeInterval = 120
}

extension NewTabPageSessionWideEventData {

    static let durationBucket: DurationBucket = .bucketed { ms in
        let thresholds = [0, 1000, 5000, 10_000, 30_000, 60_000, 300_000, 600_000]
        return thresholds.last(where: { $0 <= ms }) ?? 0
    }

    /// A plain closure rather than a `DurationBucket`, because action counts are not
    /// intervals and `DurationBucket` can only be applied through `MeasuredInterval`.
    static let actionCountBucket: (Int) -> Int = { count in
        let thresholds = [0, 1, 2, 3, 5, 10, 20]
        return thresholds.last(where: { $0 <= count }) ?? 0
    }

    func jsonParameters() -> [String: Encodable] {
        let bucket = Self.durationBucket
        return Dictionary(compacting: [
            (WideEventParameter.NewTabPageSessionFeature.trigger, trigger.rawValue),
            (WideEventParameter.NewTabPageSessionFeature.launchKeyboardMode, launchKeyboardMode.rawValue),
            (WideEventParameter.NewTabPageSessionFeature.toggleEnabled, toggleEnabled),
            (WideEventParameter.NewTabPageSessionFeature.terminalAction, terminalAction?.rawValue),
            (WideEventParameter.NewTabPageSessionFeature.actionCountBucketed, String(Self.actionCountBucket(actionCount))),
            (WideEventParameter.NewTabPageSessionFeature.timeToFirstInteractionMsBucketed, firstInteractionInterval.stringValue(bucket)),
            (WideEventParameter.NewTabPageSessionFeature.sessionDurationMsBucketed, sessionInterval.stringValue(bucket)),
            (WideEventParameter.NewTabPageSessionFeature.tapInputBar, tapInputBar),
            (WideEventParameter.NewTabPageSessionFeature.typeInInput, typeInInput),
            (WideEventParameter.NewTabPageSessionFeature.switchToggleToSearch, switchToggleToSearch),
            (WideEventParameter.NewTabPageSessionFeature.switchToggleToAiChat, switchToggleToAiChat),
            (WideEventParameter.NewTabPageSessionFeature.tapDuckaiButton, tapDuckaiButton),
            (WideEventParameter.NewTabPageSessionFeature.hitSubmit, hitSubmit),
            (WideEventParameter.NewTabPageSessionFeature.chooseSuggestion, chooseSuggestion),
            (WideEventParameter.NewTabPageSessionFeature.tapFavorite, tapFavorite),
            (WideEventParameter.NewTabPageSessionFeature.tapFireButton, tapFireButton),
            (WideEventParameter.NewTabPageSessionFeature.tapReturnToLast, tapReturnToLast),
            (WideEventParameter.NewTabPageSessionFeature.tapTabViewerEscapeHatch, tapTabViewerEscapeHatch),
            (WideEventParameter.NewTabPageSessionFeature.tapTabViewerToolbar, tapTabViewerToolbar),
            (WideEventParameter.NewTabPageSessionFeature.tapBookmarksToolbarItem, tapBookmarksToolbarItem),
            (WideEventParameter.NewTabPageSessionFeature.tapPasswordsToolbarItem, tapPasswordsToolbarItem),
            (WideEventParameter.NewTabPageSessionFeature.openMenu, openMenu),
            (WideEventParameter.NewTabPageSessionFeature.menuBookmarks, menuBookmarks),
            (WideEventParameter.NewTabPageSessionFeature.menuPasswords, menuPasswords),
            (WideEventParameter.NewTabPageSessionFeature.menuChats, menuChats),
            (WideEventParameter.NewTabPageSessionFeature.menuDownloads, menuDownloads),
            (WideEventParameter.NewTabPageSessionFeature.menuVpn, menuVpn),
            (WideEventParameter.NewTabPageSessionFeature.clickMessageCta, clickMessageCta),
            (WideEventParameter.NewTabPageSessionFeature.clickMessageDismiss, clickMessageDismiss),
            (WideEventParameter.NewTabPageSessionFeature.dismissKeyboard, dismissKeyboard),
            (WideEventParameter.NewTabPageSessionFeature.scrollView, scrollView),
            (WideEventParameter.NewTabPageSessionFeature.utiBackArrow, utiBackArrow),
            (WideEventParameter.NewTabPageSessionFeature.menuItemSelected, menuItemSelected),
            (WideEventParameter.NewTabPageSessionFeature.selectBookmark, selectBookmark),
            (WideEventParameter.NewTabPageSessionFeature.selectPassword, selectPassword),
            (WideEventParameter.NewTabPageSessionFeature.selectDownload, selectDownload),
            (WideEventParameter.NewTabPageSessionFeature.emailCopied, emailCopied),
            (WideEventParameter.NewTabPageSessionFeature.vpnOn, vpnOn),
            (WideEventParameter.NewTabPageSessionFeature.vpnOff, vpnOff),
        ])
    }
}

extension WideEventParameter {

    enum NewTabPageSessionFeature {
        static let trigger = "feature.data.ext.trigger"
        static let launchKeyboardMode = "feature.data.ext.launch_keyboard_mode"
        static let toggleEnabled = "feature.data.ext.toggle_enabled"
        static let terminalAction = "feature.data.ext.terminal_action"
        static let actionCountBucketed = "feature.data.ext.action_count_bucketed"
        static let timeToFirstInteractionMsBucketed = "feature.data.ext.time_to_first_interaction_ms_bucketed"
        static let sessionDurationMsBucketed = "feature.data.ext.session_duration_ms_bucketed"

        static let tapInputBar = "feature.data.ext.actions.tap_input_bar"
        static let typeInInput = "feature.data.ext.actions.type_in_input"
        static let switchToggleToSearch = "feature.data.ext.actions.switch_toggle_to_search"
        static let switchToggleToAiChat = "feature.data.ext.actions.switch_toggle_to_ai_chat"
        static let tapDuckaiButton = "feature.data.ext.actions.tap_duckai_button"
        static let hitSubmit = "feature.data.ext.actions.hit_submit"
        static let chooseSuggestion = "feature.data.ext.actions.choose_suggestion"
        static let tapFavorite = "feature.data.ext.actions.tap_favorite"
        static let tapFireButton = "feature.data.ext.actions.tap_fire_button"
        static let tapReturnToLast = "feature.data.ext.actions.tap_return_to_last"
        static let tapTabViewerEscapeHatch = "feature.data.ext.actions.tap_tab_viewer_escape_hatch"
        static let tapTabViewerToolbar = "feature.data.ext.actions.tap_tab_viewer_toolbar"
        static let tapBookmarksToolbarItem = "feature.data.ext.actions.tap_bookmarks_toolbar_item"
        static let tapPasswordsToolbarItem = "feature.data.ext.actions.tap_passwords_toolbar_item"
        static let openMenu = "feature.data.ext.actions.open_menu"
        static let menuBookmarks = "feature.data.ext.actions.menu_bookmarks"
        static let menuPasswords = "feature.data.ext.actions.menu_passwords"
        static let menuChats = "feature.data.ext.actions.menu_chats"
        static let menuDownloads = "feature.data.ext.actions.menu_downloads"
        static let menuVpn = "feature.data.ext.actions.menu_vpn"
        static let clickMessageCta = "feature.data.ext.actions.click_message_cta"
        static let clickMessageDismiss = "feature.data.ext.actions.click_message_dismiss"
        static let dismissKeyboard = "feature.data.ext.actions.dismiss_keyboard"
        static let scrollView = "feature.data.ext.actions.scroll_view"
        static let utiBackArrow = "feature.data.ext.actions.uti_back_arrow"
        static let menuItemSelected = "feature.data.ext.actions.menu_item_selected"
        static let selectBookmark = "feature.data.ext.actions.select_bookmark"
        static let selectPassword = "feature.data.ext.actions.select_password"
        static let selectDownload = "feature.data.ext.actions.select_download"
        static let emailCopied = "feature.data.ext.actions.email_copied"
        static let vpnOn = "feature.data.ext.actions.vpn_on"
        static let vpnOff = "feature.data.ext.actions.vpn_off"
    }
}
