//
//  UTIStateMachineTests.swift
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

import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIStateMachineTests: XCTestCase {

    private func makeSUT(_ displayState: UnifiedToggleInputDisplayState,
                         host: UnifiedToggleInputHost = .omnibar,
                         hidesToggleOnDuckAITab: Bool = false) -> UTIStateMachine {
        UTIStateMachine(displayState: displayState, host: host, hidesToggleOnDuckAITab: hidesToggleOnDuckAITab)
    }

    /// One row per display state, asserting the whole predicate vector. Adding a top-level display
    /// state fails to compile here (the switch is exhaustive) and forces a new row; adding an
    /// `AITabState` / `OmnibarState` sub-case grows `allDisplayStates` on its own. That's the point.
    private struct Expectation {
        let isOmnibarSession: Bool
        let isAITabState: Bool
        let isAITabExpanded: Bool
        let isAITabCollapsed: Bool
        let isContextualChatState: Bool
        let isOmnibarEditing: Bool
        let isDuckAISurfaceForAttribution: Bool
        let isInputPaneExpanded: Bool
        let isInputEditing: Bool
        let isActive: Bool
        let omnibarState: UnifiedToggleInputDisplayState.OmnibarState?
        let pixelSurface: UnifiedToggleInputPixelSurface
    }

    private func expectation(for displayState: UnifiedToggleInputDisplayState) -> Expectation {
        switch displayState {
        case .hidden:
            return Expectation(isOmnibarSession: false, isAITabState: false, isAITabExpanded: false,
                               isAITabCollapsed: false, isContextualChatState: false, isOmnibarEditing: false,
                               isDuckAISurfaceForAttribution: false, isInputPaneExpanded: false,
                               isInputEditing: false, isActive: false, omnibarState: nil, pixelSurface: .addressBar)
        case .contextualChat:
            return Expectation(isOmnibarSession: false, isAITabState: false, isAITabExpanded: false,
                               isAITabCollapsed: false, isContextualChatState: true, isOmnibarEditing: false,
                               isDuckAISurfaceForAttribution: true, isInputPaneExpanded: true,
                               isInputEditing: true, isActive: true, omnibarState: nil, pixelSurface: .contextualChat)
        case .aiTab(.collapsed):
            return Expectation(isOmnibarSession: false, isAITabState: true, isAITabExpanded: false,
                               isAITabCollapsed: true, isContextualChatState: false, isOmnibarEditing: false,
                               isDuckAISurfaceForAttribution: true, isInputPaneExpanded: false,
                               isInputEditing: false, isActive: true, omnibarState: nil, pixelSurface: .duckAI)
        case .aiTab(.expanded):
            return Expectation(isOmnibarSession: false, isAITabState: true, isAITabExpanded: true,
                               isAITabCollapsed: false, isContextualChatState: false, isOmnibarEditing: false,
                               isDuckAISurfaceForAttribution: true, isInputPaneExpanded: true,
                               isInputEditing: true, isActive: true, omnibarState: nil, pixelSurface: .duckAI)
        case .omnibar(.active):
            return Expectation(isOmnibarSession: true, isAITabState: false, isAITabExpanded: false,
                               isAITabCollapsed: false, isContextualChatState: false, isOmnibarEditing: true,
                               isDuckAISurfaceForAttribution: false, isInputPaneExpanded: true,
                               isInputEditing: true, isActive: true, omnibarState: .active, pixelSurface: .addressBar)
        case .omnibar(.inactive):
            return Expectation(isOmnibarSession: true, isAITabState: false, isAITabExpanded: false,
                               isAITabCollapsed: false, isContextualChatState: false, isOmnibarEditing: false,
                               isDuckAISurfaceForAttribution: false, isInputPaneExpanded: false,
                               isInputEditing: true, isActive: true, omnibarState: .inactive, pixelSurface: .addressBar)
        }
    }

    /// Derived rather than hand-listed so a new `AITabState` / `OmnibarState` case can't be silently
    /// skipped by every test below.
    private static let allDisplayStates: [UnifiedToggleInputDisplayState] =
        [.hidden, .contextualChat]
        + UnifiedToggleInputDisplayState.AITabState.allCases.map { .aiTab($0) }
        + UnifiedToggleInputDisplayState.OmnibarState.allCases.map { .omnibar($0) }

    // MARK: - Full predicate vector

    func test_predicateVector_forEveryDisplayState() {
        for displayState in Self.allDisplayStates {
            let sut = makeSUT(displayState)
            let expected = expectation(for: displayState)
            let context = "\(displayState)"

            XCTAssertEqual(sut.isOmnibarSession, expected.isOmnibarSession, "isOmnibarSession — \(context)")
            XCTAssertEqual(sut.isAITabState, expected.isAITabState, "isAITabState — \(context)")
            XCTAssertEqual(sut.isAITabExpanded, expected.isAITabExpanded, "isAITabExpanded — \(context)")
            XCTAssertEqual(sut.isAITabCollapsed, expected.isAITabCollapsed, "isAITabCollapsed — \(context)")
            XCTAssertEqual(sut.isContextualChatState, expected.isContextualChatState, "isContextualChatState — \(context)")
            XCTAssertEqual(sut.isOmnibarEditing, expected.isOmnibarEditing, "isOmnibarEditing — \(context)")
            XCTAssertEqual(sut.isDuckAISurfaceForAttribution, expected.isDuckAISurfaceForAttribution, "isDuckAISurfaceForAttribution — \(context)")
            XCTAssertEqual(sut.isInputPaneExpanded, expected.isInputPaneExpanded, "isInputPaneExpanded — \(context)")
            XCTAssertEqual(sut.isInputEditing, expected.isInputEditing, "isInputEditing — \(context)")
            XCTAssertEqual(sut.isActive, expected.isActive, "isActive — \(context)")
            XCTAssertEqual(sut.omnibarState, expected.omnibarState, "omnibarState — \(context)")
            XCTAssertEqual(sut.pixelSurface, expected.pixelSurface, "pixelSurface — \(context)")
        }
    }

    func test_transition_movesToTheNewStateAndItsPredicates() {
        let sut = makeSUT(.hidden)
        XCTAssertFalse(sut.isActive)

        sut.transition(to: .aiTab(.collapsed))

        XCTAssertTrue(sut.isAITabCollapsed)
        XCTAssertFalse(sut.isAITabExpanded)
        XCTAssertTrue(sut.isActive)
    }

    // MARK: - isSearchOnAITab

    /// Deliberately requires `.aiTab(.expanded)`, not any AI-tab state: a collapsed Duck.ai tab has no
    /// input pane for a mode to apply to. Widening this to `isAITabState` would make consumers fire on
    /// collapsed tabs, so the collapsed rows below are the ones that matter.
    func test_isSearchOnAITab_isTrueOnlyForExpandedAITabInSearchMode() {
        for displayState in Self.allDisplayStates {
            for inputMode in TextEntryMode.allCases {
                let sut = makeSUT(displayState)
                let expected = displayState == .aiTab(.expanded) && inputMode == .search

                XCTAssertEqual(sut.isSearchOnAITab(inputMode: inputMode), expected,
                               "isSearchOnAITab — \(displayState) / \(inputMode)")
            }
        }
    }

    func test_isSearchOnAITab_isFalseOnCollapsedAITabEvenInSearchMode() {
        let sut = makeSUT(.aiTab(.collapsed))

        XCTAssertFalse(sut.isSearchOnAITab(inputMode: .search))
    }

    // MARK: - isInputEditing

    /// One assertion per composed term, each labelled with the term it covers, so dropping a term
    /// fails a named test here rather than only shifting a row of the predicate vector.
    func test_isInputEditing_isTrueForEveryEditableState() {
        XCTAssertTrue(makeSUT(.omnibar(.active)).isInputEditing, "isOmnibarSession term")
        XCTAssertTrue(makeSUT(.omnibar(.inactive)).isInputEditing, "isOmnibarSession term — inactive still counts as editing")
        XCTAssertTrue(makeSUT(.aiTab(.expanded)).isInputEditing, "isAITabExpanded term")
        XCTAssertTrue(makeSUT(.contextualChat).isInputEditing, "isContextualChatState term")
    }

    func test_isInputEditing_isFalseWhenHiddenOrOnACollapsedAITab() {
        XCTAssertFalse(makeSUT(.hidden).isInputEditing)
        XCTAssertFalse(makeSUT(.aiTab(.collapsed)).isInputEditing, "collapsed is the discriminating half of the isAITabExpanded term")
    }

    /// `.omnibar(.inactive)` is editing but not expanded — the one state that separates the two,
    /// so it's what keeps them from being folded together.
    func test_isInputEditing_andIsInputPaneExpanded_divergeOnInactiveOmnibar() {
        let sut = makeSUT(.omnibar(.inactive))

        XCTAssertTrue(sut.isInputEditing)
        XCTAssertFalse(sut.isInputPaneExpanded)
    }

    // MARK: - isDuckAISurfaceForAttribution

    func test_isDuckAISurfaceForAttribution_coversBothAITabSubStatesAndContextualChat() {
        XCTAssertTrue(makeSUT(.aiTab(.collapsed)).isDuckAISurfaceForAttribution, "isAITabState term")
        XCTAssertTrue(makeSUT(.aiTab(.expanded)).isDuckAISurfaceForAttribution, "isAITabState term — expansion is irrelevant to attribution")
        XCTAssertTrue(makeSUT(.contextualChat).isDuckAISurfaceForAttribution, "isContextualChatState term")
    }

    func test_isDuckAISurfaceForAttribution_isFalseForAddressBarStates() {
        XCTAssertFalse(makeSUT(.hidden).isDuckAISurfaceForAttribution)
        XCTAssertFalse(makeSUT(.omnibar(.active)).isDuckAISurfaceForAttribution)
        XCTAssertFalse(makeSUT(.omnibar(.inactive)).isDuckAISurfaceForAttribution)
    }

    // MARK: - pixelSurface

    /// The precedence isn't observable from the predicate vector — no display state hits two
    /// branches — so pin the ordering and the fallback here.
    func test_pixelSurface_prefersContextualChatThenDuckAIThenAddressBar() {
        XCTAssertEqual(makeSUT(.contextualChat).pixelSurface, .contextualChat, "contextual chat is checked first")
        XCTAssertEqual(makeSUT(.aiTab(.collapsed)).pixelSurface, .duckAI)
        XCTAssertEqual(makeSUT(.aiTab(.expanded)).pixelSurface, .duckAI)
    }

    func test_pixelSurface_fallsBackToAddressBarForOmnibarAndHidden() {
        XCTAssertEqual(makeSUT(.omnibar(.active)).pixelSurface, .addressBar)
        XCTAssertEqual(makeSUT(.omnibar(.inactive)).pixelSurface, .addressBar)
        XCTAssertEqual(makeSUT(.hidden).pixelSurface, .addressBar, "hidden has no surface of its own")
    }

    // MARK: - isAITabCollapsed

    func test_isAITabCollapsed_isTrueOnlyForTheCollapsedAITab() {
        XCTAssertTrue(makeSUT(.aiTab(.collapsed)).isAITabCollapsed)
        XCTAssertFalse(makeSUT(.aiTab(.expanded)).isAITabCollapsed, "differs only in the AI-tab sub-state")
        XCTAssertFalse(makeSUT(.hidden).isAITabCollapsed, "hidden is not a collapsed Duck.ai tab")
    }

    // MARK: - isToggleVisible

    /// Full `hidesToggleOnDuckAITab` × `isToggleEnabled` cross on an AI-tab state and on the two
    /// non-AI surfaces. Expectations are literals, not a restatement of the implementation's formula.
    func test_isToggleVisible_matrix() {
        let cases: [(displayState: UnifiedToggleInputDisplayState, hidesOnDuckAITab: Bool, isToggleEnabled: Bool, expected: Bool)] = [
            (.omnibar(.active), false, false, false),
            (.omnibar(.active), false, true, true),
            (.omnibar(.active), true, false, false),
            (.omnibar(.active), true, true, true),
            (.contextualChat, false, false, false),
            (.contextualChat, false, true, true),
            (.contextualChat, true, false, false),
            (.contextualChat, true, true, true),
            (.aiTab(.expanded), false, false, false),
            (.aiTab(.expanded), false, true, true),
            (.aiTab(.expanded), true, false, false),
            (.aiTab(.expanded), true, true, false),
            (.aiTab(.collapsed), false, false, false),
            (.aiTab(.collapsed), false, true, true),
            (.aiTab(.collapsed), true, false, false),
            (.aiTab(.collapsed), true, true, false)
        ]

        for testCase in cases {
            let sut = makeSUT(testCase.displayState, hidesToggleOnDuckAITab: testCase.hidesOnDuckAITab)

            XCTAssertEqual(sut.isToggleVisible(isToggleEnabled: testCase.isToggleEnabled), testCase.expected,
                           "\(testCase.displayState) / hidesOnDuckAITab \(testCase.hidesOnDuckAITab) / enabled \(testCase.isToggleEnabled)")
        }
    }

    // MARK: - Disjointness relied on by call sites

    /// `MainViewController.adjustUI` ANDs `!isAITabCollapsed` with `isOmnibarSession`; that term is only
    /// redundant (rather than wrong) because the two can never be true at once.
    func test_isAITabCollapsed_andIsOmnibarSession_areNeverBothTrue() {
        for displayState in Self.allDisplayStates {
            let sut = makeSUT(displayState)

            XCTAssertFalse(sut.isAITabCollapsed && sut.isOmnibarSession, "\(displayState)")
        }
    }

    func test_aiTabCollapsedAndExpanded_areMutuallyExclusive() {
        for displayState in Self.allDisplayStates {
            let sut = makeSUT(displayState)

            XCTAssertFalse(sut.isAITabCollapsed && sut.isAITabExpanded, "\(displayState)")
            if sut.isAITabCollapsed || sut.isAITabExpanded {
                XCTAssertTrue(sut.isAITabState, "\(displayState)")
            }
        }
    }

    /// `dismissOmnibarKeyboard` replaced a three-case switch with `guard isInputPaneExpanded`, so this
    /// set is now load-bearing for keyboard dismissal.
    func test_isInputPaneExpanded_coversExactlyContextualChatExpandedAITabAndOmnibarEditing() {
        let expectedTrue: [UnifiedToggleInputDisplayState] = [.contextualChat, .aiTab(.expanded), .omnibar(.active)]

        for displayState in Self.allDisplayStates {
            let sut = makeSUT(displayState)

            XCTAssertEqual(sut.isInputPaneExpanded, expectedTrue.contains(displayState), "\(displayState)")
        }
    }

    // MARK: - omnibarState

    func test_omnibarState_isNilForEveryNonOmnibarState() {
        for displayState in Self.allDisplayStates where sutIsNotOmnibar(displayState) {
            let sut = makeSUT(displayState)

            XCTAssertNil(sut.omnibarState, "\(displayState)")
        }
    }

    private func sutIsNotOmnibar(_ displayState: UnifiedToggleInputDisplayState) -> Bool {
        if case .omnibar = displayState { return false }
        return true
    }
}
