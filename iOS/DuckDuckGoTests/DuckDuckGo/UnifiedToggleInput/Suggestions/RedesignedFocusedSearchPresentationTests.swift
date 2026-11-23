//
//  RedesignedFocusedSearchPresentationTests.swift
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

import Combine
import SwiftUI
import XCTest
@testable import DuckDuckGo

@MainActor
final class RedesignedFocusedSearchPresentationTests: XCTestCase {
    private let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
        .init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
    private let dismissal = CurrentValueSubject<UnifiedSuggestionsViewModel.DismissBehavior, Never>(.none)
    private let fireTab = CurrentValueSubject<Bool, Never>(false)
    private let favoritesSectionVisibility = CurrentValueSubject<Bool, Never>(true)
    private let escapeHatchVisibility = CurrentValueSubject<Bool, Never>(false)

    func testWhenTypingAndClearingThenModulesHideAndReturn() {
        let presentation = makePresentation()
        XCTAssertTrue(presentation.showsSearchModules)
        inputs.send(.init(mode: .search, isTyping: true, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertFalse(presentation.showsSearchModules)
        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertTrue(presentation.showsSearchModules)
    }

    func testWhenLastFavoriteIsRemovedThenEmptyFavoritesRowKeepsModulesVisible() {
        let presentation = makePresentation()
        XCTAssertTrue(presentation.showsSearchModules)

        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))

        XCTAssertTrue(presentation.showsSearchModules)
    }

    func testWhenFavoritesSectionIsHiddenWithoutMessagesOrEscapeHatchThenModulesHideAndHostShowsLogo() {
        let presentation = makePresentation()
        let host = makeHost(inputsPublisher: inputs.eraseToAnyPublisher())
        host.setRedesignedFocusedSurface(.newTabPage)
        XCTAssertTrue(presentation.showsSearchModules)

        favoritesSectionVisibility.send(false)
        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))

        XCTAssertFalse(presentation.showsSearchModules)
        XCTAssertTrue(host.isShowingLogo)
    }

    func testWhenFocusedOverWebPageWithoutFavoritesThenHostShowsLogoInsteadOfEmptyModules() {
        let host = makeHost(inputsPublisher: inputs.eraseToAnyPublisher())
        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))

        host.setRedesignedFocusedSurface(.webPage)

        XCTAssertFalse(host.isShowingRedesignedSearchModules)
        XCTAssertTrue(host.isShowingLogo)
    }

    func testWhenFocusedOverWebPageWithSavedFavoritesThenHostShowsModules() {
        let host = makeHost(inputsPublisher: inputs.eraseToAnyPublisher())

        host.setRedesignedFocusedSurface(.webPage)

        XCTAssertTrue(host.isShowingRedesignedSearchModules)
        XCTAssertFalse(host.isShowingLogo)
    }

    func testWhenMessagesRemainWithFavoritesSectionHiddenThenModulesStayVisible() {
        let presentation = makePresentation()
        let host = makeHost(inputsPublisher: inputs.eraseToAnyPublisher())
        host.setRedesignedFocusedSurface(.newTabPage)

        favoritesSectionVisibility.send(false)
        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: false, hasMessages: true, hasRecents: false, resultsPending: false))

        XCTAssertTrue(presentation.showsSearchModules)
        XCTAssertFalse(host.isShowingLogo)
    }

    func testWhenEscapeHatchShowsWithFavoritesSectionHiddenThenModulesStayVisibleUntilTyping() {
        let presentation = makePresentation()
        favoritesSectionVisibility.send(false)
        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertFalse(presentation.showsSearchModules)

        escapeHatchVisibility.send(true)
        XCTAssertTrue(presentation.showsSearchModules)

        inputs.send(.init(mode: .search, isTyping: true, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertFalse(presentation.showsSearchModules)
    }

    func testWhenSwitchingToDuckAIOrFireThenModulesHide() {
        let presentation = makePresentation()
        inputs.send(.init(mode: .aiChat, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertFalse(presentation.showsSearchModules)
        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertTrue(presentation.showsSearchModules)
        fireTab.send(true)
        XCTAssertFalse(presentation.showsSearchModules)
        fireTab.send(false)
        XCTAssertTrue(presentation.showsSearchModules)
    }

    func testWhenDismissingThenPresentationFreezesUntilReactivation() {
        let presentation = makePresentation()
        dismissal.send(.fadeOut)
        inputs.send(.init(mode: .search, isTyping: true, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertTrue(presentation.showsSearchModules)
        dismissal.send(.none)
        XCTAssertFalse(presentation.showsSearchModules)
    }

    func testWhenContentRefreshesDuringPresentationChangeThenHostUsesEmittedModuleVisibilityInBothFlagStates() throws {
        for usesScrollableEscapeHatch in [false, true] {
            let host = makeHost(inputsPublisher: inputs.eraseToAnyPublisher(), usesScrollableEscapeHatch: usesScrollableEscapeHatch)
            let parent = UIViewController()
            host.setRedesignedFocusedSurface(.newTabPage)
            host.start(in: parent.view, parentViewController: parent, textPublisher: Just(""))
            defer { host.tearDown() }
            host.onContentChanged = {
                host.setFocusedContent(mode: .search, escapeHatchPlacement: .hidden, escapeHatch: nil, syncPromo: nil)
            }
            let hostingController = try XCTUnwrap(parent.children.compactMap { $0 as? UIHostingController<UnifiedSuggestionsView> }.first)
            XCTAssertEqual(hostingController.rootView.usesScrollableEscapeHatch, usesScrollableEscapeHatch)
            XCTAssertTrue(hostingController.rootView.showsRedesignedSearchModules)

            inputs.send(.init(mode: .search, isTyping: true, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
            XCTAssertFalse(hostingController.rootView.showsRedesignedSearchModules)

            inputs.send(.init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
            XCTAssertTrue(hostingController.rootView.showsRedesignedSearchModules)
        }
    }

    func testWhenPresentationIsReleasedThenInputSubscriptionIsCancelled() {
        var cancellations = 0
        var presentation: RedesignedFocusedSearchPresentation? = RedesignedFocusedSearchPresentation(
            inputsPublisher: inputs.handleEvents(receiveCancel: { cancellations += 1 }).eraseToAnyPublisher(),
            dismissPublisher: dismissal.eraseToAnyPublisher(),
            fireTabPublisher: fireTab.eraseToAnyPublisher(),
            favoritesSectionVisibilityPublisher: favoritesSectionVisibility.eraseToAnyPublisher(),
            escapeHatchVisibilityPublisher: escapeHatchVisibility.eraseToAnyPublisher())
        weak let weakPresentation = presentation
        XCTAssertNotNil(weakPresentation)
        presentation = nil
        XCTAssertNil(weakPresentation)
        XCTAssertEqual(cancellations, 1)
    }

    func testWhenReturningToBrowserPresentationThenLogoAndInputSubscriptionsAreRestored() {
        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        var activeSubscriptions = 0
        let publisher = inputs.handleEvents(
            receiveSubscription: { _ in activeSubscriptions += 1 },
            receiveCancel: { activeSubscriptions -= 1 }).eraseToAnyPublisher()
        var host: UnifiedSuggestionsHost? = makeHost(inputsPublisher: publisher)
        XCTAssertEqual(activeSubscriptions, 1)
        XCTAssertEqual(host?.isShowingLogo, true)

        for _ in 0..<3 {
            host?.setRedesignedFocusedSurface(.newTabPage)
            XCTAssertEqual(host?.isShowingLogo, true)
            XCTAssertEqual(activeSubscriptions, 2)
            host?.setRedesignedFocusedSurface(.newTabPage)
            XCTAssertEqual(activeSubscriptions, 2)

            host?.setRedesignedFocusedSurface(nil)
            XCTAssertEqual(host?.isShowingLogo, true)
            XCTAssertEqual(activeSubscriptions, 1)
            host?.setRedesignedFocusedSurface(nil)
            XCTAssertEqual(activeSubscriptions, 1)
        }
        host?.setRedesignedFocusedSurface(.newTabPage)
        XCTAssertEqual(activeSubscriptions, 2)
        host?.tearDown()
        XCTAssertEqual(activeSubscriptions, 1)
        host = nil
        XCTAssertEqual(activeSubscriptions, 0)
    }

    private func makeHost(inputsPublisher: AnyPublisher<UnifiedSuggestionsInputs, Never>,
                          usesScrollableEscapeHatch: Bool = true) -> UnifiedSuggestionsHost {
        UnifiedSuggestionsHost(config: UnifiedSuggestionsHostConfig(
            source: EmptySuggestionsSource(),
            inputsPublisher: inputsPublisher,
            isAddressBarAtBottom: false,
            favoritesProvider: { nil },
            onSelectRow: { _ in },
            onDeleteRow: { _ in },
            onTapAheadRow: { _ in },
            favoritesSectionVisibilityPublisher: favoritesSectionVisibility.eraseToAnyPublisher()), usesScrollableEscapeHatch: usesScrollableEscapeHatch)
    }

    private func makePresentation() -> RedesignedFocusedSearchPresentation {
        RedesignedFocusedSearchPresentation(inputsPublisher: inputs.eraseToAnyPublisher(),
                                            dismissPublisher: dismissal.eraseToAnyPublisher(),
                                            fireTabPublisher: fireTab.eraseToAnyPublisher(),
                                            favoritesSectionVisibilityPublisher: favoritesSectionVisibility.eraseToAnyPublisher(),
                                            escapeHatchVisibilityPublisher: escapeHatchVisibility.eraseToAnyPublisher())
    }
}
