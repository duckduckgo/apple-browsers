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
import WideEvent

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
        version: "1.1.1"
    )

    enum Trigger: String, Codable, CaseIterable {
        case appOpen = "app_open"
        case newTabOpened = "new_tab_opened"
        /// Separate from `newTabOpened` because the user asked to burn, not for a blank page.
        case newTabOpenedAfterFire = "new_tab_opened_after_fire"
    }

    /// The keyboard state the app chooses when a New Tab page appears.
    /// Includes automatic focus just after the page appears. Later keyboard changes do not update this state.
    enum LaunchKeyboardMode: String, Codable, CaseIterable {
        case up
        case down
    }

    /// Which New Tab Page design the visit was shown.
    enum PageDesign: String, Codable, CaseIterable {
        case legacy
        case redesign
    }

    /// A user action on the New Tab Page. The raw value is its parameter name under
    /// `feature.data.ext.actions.`, so renaming a case renames the reported field.
    enum Action: String, Codable, CaseIterable {
        case tapInputBar = "tap_input_bar"
        case typeInInput = "type_in_input"
        case switchToggleToSearch = "switch_toggle_to_search"
        case switchToggleToAiChat = "switch_toggle_to_ai_chat"
        case tapDuckaiButton = "tap_duckai_button"
        case hitSubmit = "hit_submit"
        case chooseSuggestion = "choose_suggestion"
        case tapFavorite = "tap_favorite"
        case tapAddFavorite = "tap_add_favorite"
        case tapCustomize = "tap_customize"
        case tapFireButton = "tap_fire_button"
        case tapReturnToLast = "tap_return_to_last"
        /// Reached through the return-to-tab card rather than the toolbar's tab button.
        case tapTabViewerEscapeHatch = "tap_tab_viewer_escape_hatch"
        case tapTabViewerToolbar = "tap_tab_viewer_toolbar"
        case tapBookmarksToolbarItem = "tap_bookmarks_toolbar_item"
        case tapPasswordsToolbarItem = "tap_passwords_toolbar_item"
        case openMenu = "open_menu"
        case menuBookmarks = "menu_bookmarks"
        case menuPasswords = "menu_passwords"
        case menuChats = "menu_chats"
        case menuDownloads = "menu_downloads"
        case menuVpn = "menu_vpn"
        case clickMessageCta = "click_message_cta"
        case clickMessageDismiss = "click_message_dismiss"
        case dismissKeyboard = "dismiss_keyboard"
        case scrollView = "scroll_view"
        /// The back arrow that leaves search mode, in the omnibar's unified text input.
        case utiBackArrow = "uti_back_arrow"
        case selectBookmark = "select_bookmark"
        case selectPassword = "select_password"
        case selectDownload = "select_download"
        case emailCopied = "email_copied"
        case vpnOn = "vpn_on"
        case vpnOff = "vpn_off"

        /// Arrives as one call per keystroke or scroll tick, so an uninterrupted run is one step.
        var arrivesAsStream: Bool {
            self == .typeInInput || self == .scrollView
        }
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
        /// A top level browsing menu entry with no terminal of its own, such as New Tab or
        /// Settings, or All Settings from the customization sheet. Those replace the New Tab
        /// Page for good, so the visit ends here.
        case menuItemSelected = "menu_item_selected"
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
                 .customButton,
                 .menuItemSelected:
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
    var pageDesign: PageDesign

    /// Carried explicitly rather than derived from `feature.status`, because the sender
    /// only writes a status reason for SUCCESS and UNKNOWN outcomes.
    var terminalAction: TerminalAction?

    var sessionInterval: WideEvent.MeasuredInterval
    var firstInteractionInterval: WideEvent.MeasuredInterval

    /// Lets the inactivity timeout be evaluated from the next observed event instead of
    /// keeping a timer running for the length of the visit.
    var lastActionAt: Date

    var actionCount: Int = 0

    /// Every action taken during the visit. A set, because the event reports which actions
    /// happened, never their order or how often.
    var actions: Set<Action> = []

    init(trigger: Trigger,
         launchKeyboardMode: LaunchKeyboardMode,
         toggleEnabled: Bool,
         pageDesign: PageDesign,
         startedAt: Date = Date(),
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.trigger = trigger
        self.launchKeyboardMode = launchKeyboardMode
        self.toggleEnabled = toggleEnabled
        self.pageDesign = pageDesign
        self.sessionInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.firstInteractionInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.lastActionAt = startedAt
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    /// Decodes a visit stored by any earlier version of the app.
    init(from decoder: Decoder) throws {
        // A visit left open when the app died is decoded after an update to be reported. Fields
        // added since the event shipped would otherwise fail that decode, and the storage skips
        // records it cannot decode, so the visit would never be reported or deleted.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        globalData = try container.decode(WideEventGlobalData.self, forKey: .globalData)
        contextData = try container.decode(WideEventContextData.self, forKey: .contextData)
        appData = try container.decode(WideEventAppData.self, forKey: .appData)
        errorData = try container.decodeIfPresent(WideEventErrorData.self, forKey: .errorData)
        trigger = try container.decode(Trigger.self, forKey: .trigger)
        launchKeyboardMode = try container.decode(LaunchKeyboardMode.self, forKey: .launchKeyboardMode)
        toggleEnabled = try container.decode(Bool.self, forKey: .toggleEnabled)
        // Builds without this field could only show the legacy page in production.
        pageDesign = try container.decodeIfPresent(PageDesign.self, forKey: .pageDesign) ?? .legacy
        terminalAction = try container.decodeIfPresent(TerminalAction.self, forKey: .terminalAction)
        sessionInterval = try container.decode(WideEvent.MeasuredInterval.self, forKey: .sessionInterval)
        firstInteractionInterval = try container.decode(WideEvent.MeasuredInterval.self, forKey: .firstInteractionInterval)
        lastActionAt = try container.decode(Date.self, forKey: .lastActionAt)
        actionCount = try container.decodeIfPresent(Int.self, forKey: .actionCount) ?? 0
        actions = try container.decodeIfPresent([String].self, forKey: .actions).map(Self.actions(named:))
            ?? Self.actionsStoredAsFlags(in: decoder)
    }

    /// Actions stored by name. A name this build does not know, written by a newer one, is dropped.
    private static func actions(named names: [String]) -> Set<Action> {
        Set(names.compactMap(Action.init(rawValue:)))
    }

    /// Actions stored by builds that kept one Bool property per action, named after its case.
    private static func actionsStoredAsFlags(in decoder: Decoder) throws -> Set<Action> {
        let container = try decoder.container(keyedBy: ActionFlagKey.self)
        return try Set(Action.allCases.filter { action in
            try container.decodeIfPresent(Bool.self, forKey: ActionFlagKey(action)) == true
        })
    }

    private struct ActionFlagKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(_ action: Action) {
            stringValue = String(describing: action)
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
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
        var parameters: [String: Encodable] = Dictionary(compacting: [
            (WideEventParameter.NewTabPageSessionFeature.trigger, trigger.rawValue),
            (WideEventParameter.NewTabPageSessionFeature.launchKeyboardMode, launchKeyboardMode.rawValue),
            (WideEventParameter.NewTabPageSessionFeature.toggleEnabled, toggleEnabled),
            (WideEventParameter.NewTabPageSessionFeature.pageDesign, pageDesign.rawValue),
            (WideEventParameter.NewTabPageSessionFeature.terminalAction, terminalAction?.rawValue),
            (WideEventParameter.NewTabPageSessionFeature.actionCountBucketed, String(Self.actionCountBucket(actionCount))),
            (WideEventParameter.NewTabPageSessionFeature.timeToFirstInteractionMsBucketed, firstInteractionInterval.stringValue(bucket)),
            (WideEventParameter.NewTabPageSessionFeature.sessionDurationMsBucketed, sessionInterval.stringValue(bucket)),
        ])
        // Actions not taken are omitted: thirty `false` flags per visit are payload without information.
        for action in actions {
            parameters[WideEventParameter.NewTabPageSessionFeature.key(for: action)] = true
        }
        return parameters
    }
}

extension WideEventParameter {

    enum NewTabPageSessionFeature {
        static let trigger = "feature.data.ext.trigger"
        static let launchKeyboardMode = "feature.data.ext.launch_keyboard_mode"
        static let toggleEnabled = "feature.data.ext.toggle_enabled"
        static let pageDesign = "feature.data.ext.page_design"
        static let terminalAction = "feature.data.ext.terminal_action"
        static let actionCountBucketed = "feature.data.ext.action_count_bucketed"
        static let timeToFirstInteractionMsBucketed = "feature.data.ext.time_to_first_interaction_ms_bucketed"
        static let sessionDurationMsBucketed = "feature.data.ext.session_duration_ms_bucketed"

        /// The parameter an action is reported under.
        static func key(for action: NewTabPageSessionWideEventData.Action) -> String {
            "feature.data.ext.actions.\(action.rawValue)"
        }
    }
}
