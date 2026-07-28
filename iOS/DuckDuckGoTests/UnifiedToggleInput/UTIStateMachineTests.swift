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

    /// One row per display state, asserting the whole predicate vector. Adding a display state
    /// should fail to compile here (the switch is exhaustive) and force a new row — that's the point.
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

    private static let allDisplayStates: [UnifiedToggleInputDisplayState] = [
        .hidden, .contextualChat, .aiTab(.collapsed), .aiTab(.expanded), .omnibar(.active), .omnibar(.inactive)
    ]

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

    // MARK: - isToggleVisible

    func test_isToggleVisible_matrix() {
        let cases: [(displayState: UnifiedToggleInputDisplayState, hidesOnDuckAITab: Bool, isToggleEnabled: Bool, expected: Bool)] = [
            (.omnibar(.active), false, true, true),
            (.omnibar(.active), true, true, true),
            (.omnibar(.active), true, false, false),
            (.aiTab(.expanded), false, true, true),
            (.aiTab(.expanded), true, true, false),
            (.aiTab(.collapsed), true, true, false),
            (.contextualChat, true, true, true)
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
