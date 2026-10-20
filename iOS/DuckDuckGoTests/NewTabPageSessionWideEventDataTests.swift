//
//  NewTabPageSessionWideEventDataTests.swift
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
import Testing
import WideEvent
@testable import DuckDuckGo

@Suite("New Tab Page Session Wide Event Data")
struct NewTabPageSessionWideEventDataTests {

    private static let actionKeys = [
        "feature.data.ext.actions.tap_input_bar",
        "feature.data.ext.actions.type_in_input",
        "feature.data.ext.actions.switch_toggle_to_search",
        "feature.data.ext.actions.switch_toggle_to_ai_chat",
        "feature.data.ext.actions.tap_duckai_button",
        "feature.data.ext.actions.hit_submit",
        "feature.data.ext.actions.choose_suggestion",
        "feature.data.ext.actions.tap_favorite",
        "feature.data.ext.actions.tap_add_favorite",
        "feature.data.ext.actions.tap_customize",
        "feature.data.ext.actions.toggle_favorites_expansion",
        "feature.data.ext.actions.tap_fire_button",
        "feature.data.ext.actions.tap_return_to_last",
        "feature.data.ext.actions.tap_tab_viewer_escape_hatch",
        "feature.data.ext.actions.tap_tab_viewer_toolbar",
        "feature.data.ext.actions.tap_bookmarks_toolbar_item",
        "feature.data.ext.actions.tap_passwords_toolbar_item",
        "feature.data.ext.actions.open_menu",
        "feature.data.ext.actions.menu_bookmarks",
        "feature.data.ext.actions.menu_passwords",
        "feature.data.ext.actions.menu_chats",
        "feature.data.ext.actions.menu_downloads",
        "feature.data.ext.actions.menu_vpn",
        "feature.data.ext.actions.click_message_cta",
        "feature.data.ext.actions.click_message_dismiss",
        "feature.data.ext.actions.dismiss_keyboard",
        "feature.data.ext.actions.scroll_view",
        "feature.data.ext.actions.uti_back_arrow",
        "feature.data.ext.actions.select_bookmark",
        "feature.data.ext.actions.select_password",
        "feature.data.ext.actions.select_download",
        "feature.data.ext.actions.email_copied",
        "feature.data.ext.actions.vpn_on",
        "feature.data.ext.actions.vpn_off",
    ]

    private func makeData(trigger: NewTabPageSessionWideEventData.Trigger = .appOpen,
                          launchKeyboardMode: NewTabPageSessionWideEventData.LaunchKeyboardMode = .down,
                          toggleEnabled: Bool = false,
                          pageDesign: NewTabPageSessionWideEventData.PageDesign = .legacy,
                          startedAt: Date = Date()) -> NewTabPageSessionWideEventData {
        NewTabPageSessionWideEventData(trigger: trigger,
                                       launchKeyboardMode: launchKeyboardMode,
                                       toggleEnabled: toggleEnabled,
                                       pageDesign: pageDesign,
                                       startedAt: startedAt)
    }

    /// The per-action Bool keys that builds before actions were stored as a set wrote. Frozen: these
    /// records can still be on devices, so the list must not follow later renames.
    private static let actionFlagKeysStoredByEarlierBuilds = [
        "tapInputBar", "typeInInput", "switchToggleToSearch", "switchToggleToAiChat", "tapDuckaiButton",
        "hitSubmit", "chooseSuggestion", "tapFavorite", "tapAddFavorite", "tapCustomize", "tapFireButton",
        "tapReturnToLast", "tapTabViewerEscapeHatch", "tapTabViewerToolbar", "tapBookmarksToolbarItem",
        "tapPasswordsToolbarItem", "openMenu", "menuBookmarks", "menuPasswords", "menuChats", "menuDownloads",
        "menuVpn", "clickMessageCta", "clickMessageDismiss", "dismissKeyboard", "scrollView", "utiBackArrow",
        "selectBookmark", "selectPassword", "selectDownload", "emailCopied", "vpnOn", "vpnOff",
    ]

    /// Encodes `data` and rewrites its actions the way builds that stored one Bool per action did.
    private func storedByEarlierBuild(_ data: NewTabPageSessionWideEventData,
                                      flagsSetToTrue: [String]) throws -> Data {
        var stored = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        stored["actions"] = nil
        stored["pageDesign"] = nil
        for key in Self.actionFlagKeysStoredByEarlierBuilds {
            stored[key] = flagsSetToTrue.contains(key)
        }
        return try JSONSerialization.data(withJSONObject: stored)
    }

    // MARK: - Metadata

    @available(iOS 16, *)
    @Test("Metadata exposes expected pixel and feature names", .timeLimit(.minutes(1)))
    func metadataExposesExpectedNames() {
        #expect(NewTabPageSessionWideEventData.metadata.pixelName == "new_tab_page_session")
        #expect(NewTabPageSessionWideEventData.metadata.featureName == "new-tab-page-session")
        #expect(NewTabPageSessionWideEventData.metadata.type == "ios-new-tab-page-session")
        #expect(NewTabPageSessionWideEventData.metadata.version == "1.1.1")
    }

    @available(iOS 16, *)
    @Test("Timeout thresholds are shared as constants", .timeLimit(.minutes(1)))
    func timeoutThresholdsAreSharedAsConstants() {
        #expect(NewTabPageSessionWideEventData.noActionTimeout == 30)
        #expect(NewTabPageSessionWideEventData.maxSessionDuration == 120)
    }

    // MARK: - jsonParameters

    @available(iOS 16, *)
    @Test("Default flow emits trigger, keyboard mode, toggle and zero action count", .timeLimit(.minutes(1)))
    func defaultFlowEmitsStartOfVisitFields() {
        let params = makeData().jsonParameters()

        #expect(params["feature.data.ext.trigger"] as? String == "app_open")
        #expect(params["feature.data.ext.launch_keyboard_mode"] as? String == "down")
        #expect(params["feature.data.ext.toggle_enabled"] as? Bool == false)
        #expect(params["feature.data.ext.page_design"] as? String == "legacy")
        #expect(params["feature.data.ext.action_count_bucketed"] as? String == "0")
        #expect(params["feature.data.ext.terminal_action"] == nil)
        #expect(params["feature.data.ext.session_duration_ms_bucketed"] == nil)
        #expect(params["feature.data.ext.time_to_first_interaction_ms_bucketed"] == nil)
    }

    @available(iOS 16, *)
    @Test("New tab trigger emits new_tab_opened", .timeLimit(.minutes(1)))
    func newTabTriggerEmitsNewTabOpened() {
        let params = makeData(trigger: .newTabOpened).jsonParameters()
        #expect(params["feature.data.ext.trigger"] as? String == "new_tab_opened")
    }

    @available(iOS 16, *)
    @Test("Keyboard up mode emits up", .timeLimit(.minutes(1)))
    func keyboardUpModeEmitsUp() {
        let params = makeData(launchKeyboardMode: .up).jsonParameters()
        #expect(params["feature.data.ext.launch_keyboard_mode"] as? String == "up")
    }

    @available(iOS 16, *)
    @Test("Redesigned page emits redesign", .timeLimit(.minutes(1)))
    func redesignedPageEmitsRedesign() {
        let params = makeData(pageDesign: .redesign).jsonParameters()
        #expect(params["feature.data.ext.page_design"] as? String == "redesign")
    }

    @available(iOS 16, *)
    @Test("Enabled toggle emits true", .timeLimit(.minutes(1)))
    func enabledToggleEmitsTrue() {
        let params = makeData(toggleEnabled: true).jsonParameters()
        #expect(params["feature.data.ext.toggle_enabled"] as? Bool == true)
    }

    @available(iOS 16, *)
    @Test("Every terminal action emits its raw value", .timeLimit(.minutes(1)))
    func everyTerminalActionEmitsItsRawValue() {
        for action in NewTabPageSessionWideEventData.TerminalAction.allCases {
            let data = makeData()
            data.terminalAction = action
            #expect(data.jsonParameters()["feature.data.ext.terminal_action"] as? String == action.rawValue)
        }
    }

    @available(iOS 16, *)
    @Test("Terminal action is absent while the visit is in progress", .timeLimit(.minutes(1)))
    func terminalActionIsAbsentWhileVisitInProgress() {
        #expect(makeData().jsonParameters()["feature.data.ext.terminal_action"] == nil)
    }

    // MARK: - Action flags

    @available(iOS 16, *)
    @Test("Actions that did not happen are left out entirely", .timeLimit(.minutes(1)))
    func actionFlagsAreOmittedWhenNotPerformed() {
        let params = makeData().jsonParameters()

        for key in Self.actionKeys {
            #expect(params[key] == nil, "Expected \(key) to be absent")
        }
    }

    @available(iOS 16, *)
    @Test("Only the actions performed are emitted", .timeLimit(.minutes(1)))
    func onlyPerformedActionsAreEmitted() {
        let data = makeData()
        data.actions = [.tapFavorite]
        let params = data.jsonParameters()

        let tapFavoriteKey = "feature.data.ext.actions.tap_favorite"
        #expect(params[tapFavoriteKey] as? Bool == true)
        for key in Self.actionKeys where key != tapFavoriteKey {
            #expect(params[key] == nil, "Expected \(key) to be absent")
        }
    }

    @available(iOS 16, *)
    @Test("Every action is reported under its key in the event definition", .timeLimit(.minutes(1)))
    func actionKeysMatchDefinition() {
        let keys = NewTabPageSessionWideEventData.Action.allCases.map(WideEventParameter.NewTabPageSessionFeature.key(for:))

        #expect(keys.sorted() == Self.actionKeys.sorted())
    }

    @available(iOS 16, *)
    @Test("Action flags propagate when set", .timeLimit(.minutes(1)))
    func actionFlagsPropagateWhenSet() {
        let data = makeData()
        data.actions = Set(NewTabPageSessionWideEventData.Action.allCases)
        let params = data.jsonParameters()

        for key in Self.actionKeys {
            #expect(params[key] as? Bool == true, "Expected \(key) to be emitted as true")
        }
    }

    // MARK: - Terminal action status mapping

    @available(iOS 16, *)
    @Test("User actions map to success carrying the action as the reason", .timeLimit(.minutes(1)))
    func userActionsMapToSuccess() {
        let successActions: [NewTabPageSessionWideEventData.TerminalAction] = [
            .loadSerp,
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
            .menuItemSelected,
        ]

        #expect(successActions.count == 12)

        for action in successActions {
            // No reason attached, so the sender never writes `status_reason` for a
            // success. The detail lives in `terminal_action`, which keeps
            // `status_reason` to the single value the schema declares.
            #expect(action.status == .success)
        }
    }

    @available(iOS 16, *)
    @Test("Timeouts map to failure", .timeLimit(.minutes(1)))
    func timeoutsMapToFailure() {
        #expect(NewTabPageSessionWideEventData.TerminalAction.noActionTimeout.status == .failure)
        #expect(NewTabPageSessionWideEventData.TerminalAction.maxDurationExceeded.status == .failure)
    }

    @available(iOS 16, *)
    @Test("Backgrounding maps to cancelled", .timeLimit(.minutes(1)))
    func backgroundingMapsToCancelled() {
        #expect(NewTabPageSessionWideEventData.TerminalAction.appBackgrounded.status == .cancelled)
    }

    @available(iOS 16, *)
    @Test("Termination maps to unknown carrying the action as the reason", .timeLimit(.minutes(1)))
    func terminationMapsToUnknown() {
        #expect(NewTabPageSessionWideEventData.TerminalAction.appTerminated.status == .unknown(reason: "app_terminated"))
    }

    @available(iOS 16, *)
    @Test("Terminal action raw values match the event definition", .timeLimit(.minutes(1)))
    func terminalActionRawValuesMatchDefinition() {
        let expected: [(NewTabPageSessionWideEventData.TerminalAction, String)] = [
            (.loadSerp, "load_serp"),
            (.loadSearchSuggestion, "load_search_suggestion"),
            (.loadWebsite, "load_website"),
            (.loadDuckai, "load_duckai"),
            (.loadDuckaiResponse, "load_duckai_response"),
            (.loadPreviousChat, "load_previous_chat"),
            (.lastTabLoaded, "last_tab_loaded"),
            (.selectOtherTab, "select_other_tab"),
            (.swipeToOtherTab, "swipe_to_other_tab"),
            (.deleteData, "delete_data"),
            (.customButton, "custom_button"),
            (.menuItemSelected, "menu_item_selected"),
            (.noActionTimeout, "no_action_timeout"),
            (.maxDurationExceeded, "max_duration_exceeded"),
            (.appBackgrounded, "app_backgrounded"),
            (.appTerminated, "app_terminated"),
        ]

        #expect(NewTabPageSessionWideEventData.TerminalAction.allCases.count == expected.count)

        for (action, rawValue) in expected {
            #expect(action.rawValue == rawValue)
        }
    }

    // MARK: - Durations

    @available(iOS 16, *)
    @Test("Session duration is bucketed when sessionInterval is closed", .timeLimit(.minutes(1)))
    func sessionDurationIsBucketed() {
        let start = Date()
        let data = makeData(startedAt: start)
        data.sessionInterval.end = start.addingTimeInterval(2.5) // 2500ms → bucket "1000"

        #expect(data.jsonParameters()["feature.data.ext.session_duration_ms_bucketed"] as? String == "1000")
    }

    @available(iOS 16, *)
    @Test("First interaction duration is bucketed when interval is closed", .timeLimit(.minutes(1)))
    func firstInteractionDurationIsBucketed() {
        let start = Date()
        let data = makeData(startedAt: start)
        data.firstInteractionInterval.end = start.addingTimeInterval(0.5) // 500ms → bucket "0"

        #expect(data.jsonParameters()["feature.data.ext.time_to_first_interaction_ms_bucketed"] as? String == "0")
    }

    @available(iOS 16, *)
    @Test("Duration bucketing rounds down to the enclosing threshold", .timeLimit(.minutes(1)))
    func durationBucketingRoundsDown() {
        let start = Date()

        func bucketFor(seconds: TimeInterval) -> String? {
            let data = makeData(startedAt: start)
            data.sessionInterval.end = start.addingTimeInterval(seconds)
            return data.jsonParameters()["feature.data.ext.session_duration_ms_bucketed"] as? String
        }

        #expect(bucketFor(seconds: 0) == "0")
        #expect(bucketFor(seconds: 0.999) == "0")
        #expect(bucketFor(seconds: 1.0) == "1000")
        #expect(bucketFor(seconds: 4.999) == "1000")
        #expect(bucketFor(seconds: 5.0) == "5000")
        #expect(bucketFor(seconds: 10.0) == "10000")
        #expect(bucketFor(seconds: 30.0) == "30000")
        #expect(bucketFor(seconds: 60.0) == "60000")
        #expect(bucketFor(seconds: 300.0) == "300000")
        #expect(bucketFor(seconds: 600.0) == "600000")
        #expect(bucketFor(seconds: 9999.0) == "600000")
    }

    @available(iOS 16, *)
    @Test("Durations are absent while their intervals are open", .timeLimit(.minutes(1)))
    func durationsAreAbsentWhileIntervalsAreOpen() {
        let params = makeData().jsonParameters()
        #expect(params["feature.data.ext.session_duration_ms_bucketed"] == nil)
        #expect(params["feature.data.ext.time_to_first_interaction_ms_bucketed"] == nil)
    }

    @available(iOS 16, *)
    @Test("Both intervals and the last action share the start date", .timeLimit(.minutes(1)))
    func bothIntervalsAndLastActionShareStartDate() {
        let start = Date()
        let data = makeData(startedAt: start)

        #expect(data.sessionInterval.start == start)
        #expect(data.firstInteractionInterval.start == start)
        #expect(data.lastActionAt == start)
    }

    // MARK: - Action count bucketing

    @available(iOS 16, *)
    @Test("Action count bucketing rounds down to the enclosing threshold", .timeLimit(.minutes(1)))
    func actionCountBucketingRoundsDown() {
        func bucketFor(count: Int) -> String? {
            let data = makeData()
            data.actionCount = count
            return data.jsonParameters()["feature.data.ext.action_count_bucketed"] as? String
        }

        #expect(bucketFor(count: 0) == "0")
        #expect(bucketFor(count: 1) == "1")
        #expect(bucketFor(count: 2) == "2")
        #expect(bucketFor(count: 3) == "3")
        #expect(bucketFor(count: 4) == "3")
        #expect(bucketFor(count: 5) == "5")
        #expect(bucketFor(count: 9) == "5")
        #expect(bucketFor(count: 10) == "10")
        #expect(bucketFor(count: 19) == "10")
        #expect(bucketFor(count: 20) == "20")
        #expect(bucketFor(count: 250) == "20")
    }

    // MARK: - Completion decision

    @available(iOS 16, *)
    @Test("App launch trigger returns keepPending so the start hook handles orphan cleanup", .timeLimit(.minutes(1)))
    func appLaunchReturnsKeepPending() async {
        let decision = await makeData().completionDecision(for: .appLaunch)

        if case .keepPending = decision {
            // expected
        } else {
            Issue.record("Expected .keepPending, got \(decision)")
        }
    }

    // MARK: - Codable

    @available(iOS 16, *)
    @Test("Round-trips through JSONEncoder/Decoder preserves all fields", .timeLimit(.minutes(1)))
    func codableRoundTripPreservesAllFields() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let original = makeData(trigger: .newTabOpened,
                                launchKeyboardMode: .up,
                                toggleEnabled: true,
                                pageDesign: .redesign,
                                startedAt: start)
        original.terminalAction = .loadSerp
        original.sessionInterval.end = start.addingTimeInterval(5)
        original.firstInteractionInterval.end = start.addingTimeInterval(1)
        original.lastActionAt = start.addingTimeInterval(4)
        original.actionCount = 7
        original.actions = Set(NewTabPageSessionWideEventData.Action.allCases)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NewTabPageSessionWideEventData.self, from: encoded)

        #expect(decoded.trigger == .newTabOpened)
        #expect(decoded.launchKeyboardMode == .up)
        #expect(decoded.toggleEnabled == true)
        #expect(decoded.pageDesign == .redesign)
        #expect(decoded.terminalAction == .loadSerp)
        #expect(decoded.sessionInterval.start == start)
        #expect(decoded.sessionInterval.end == start.addingTimeInterval(5))
        #expect(decoded.firstInteractionInterval.start == start)
        #expect(decoded.firstInteractionInterval.end == start.addingTimeInterval(1))
        #expect(decoded.lastActionAt == start.addingTimeInterval(4))
        #expect(decoded.actionCount == 7)
        #expect(decoded.actions == Set(NewTabPageSessionWideEventData.Action.allCases))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Decodes every action flag stored by earlier builds", .timeLimit(.minutes(1)))
    func decodesEveryActionFlagStoredByEarlierBuilds() throws {
        let payload = try storedByEarlierBuild(makeData(), flagsSetToTrue: Self.actionFlagKeysStoredByEarlierBuilds)

        let decoded = try JSONDecoder().decode(NewTabPageSessionWideEventData.self, from: payload)

        let actionsAddedSince: Set<NewTabPageSessionWideEventData.Action> = [.toggleFavoritesExpansion]
        #expect(decoded.actions == Set(NewTabPageSessionWideEventData.Action.allCases).subtracting(actionsAddedSince))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Decodes a visit stored by an earlier build with only the actions it took", .timeLimit(.minutes(1)))
    func decodesVisitStoredByEarlierBuild() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = try storedByEarlierBuild(makeData(trigger: .appOpen, startedAt: start),
                                               flagsSetToTrue: ["tapFavorite"])

        let decoded = try JSONDecoder().decode(NewTabPageSessionWideEventData.self, from: payload)

        #expect(decoded.trigger == .appOpen)
        #expect(decoded.sessionInterval.start == start)
        #expect(decoded.pageDesign == .legacy)
        #expect(decoded.actions == [.tapFavorite])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Drops stored action names this build does not know", .timeLimit(.minutes(1)))
    func dropsUnknownStoredActionNames() throws {
        var stored = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(makeData())) as? [String: Any])
        stored["actions"] = ["tap_input_bar", "an_action_added_later"]
        let payload = try JSONSerialization.data(withJSONObject: stored)

        let decoded = try JSONDecoder().decode(NewTabPageSessionWideEventData.self, from: payload)

        #expect(decoded.actions == [.tapInputBar])
    }
}
