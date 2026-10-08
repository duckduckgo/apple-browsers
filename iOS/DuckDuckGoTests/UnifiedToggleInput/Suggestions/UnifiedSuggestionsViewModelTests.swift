//
//  UnifiedSuggestionsViewModelTests.swift
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
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedSuggestionsViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()
    override func tearDown() { cancellables.removeAll(); super.tearDown() }

    func test_searchEmptyWithFavorites_publishesFavorites() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        XCTAssertEqual(sut.content, .favorites)
    }

    func test_searchTyping_publishesList() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .search, isTyping: true, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        XCTAssertEqual(sut.content, .list(.search))
    }

    func test_floatingUIViewportTracksContainerResizeDuringLogoDismiss() throws {
        let (host, hosting, container, window) = try makeWindowedHost(isFloatingUIEnabled: true)
        defer { host.tearDown(); window.isHidden = true }

        XCTAssertEqual(hosting.rootView.viewModel.logoViewportFrame, CGRect(x: 0, y: 0, width: 440, height: 733))

        host.morphLogoHomeForDismiss(matching: 0.2625)
        container.frame.size.height = 788
        container.setNeedsLayout()
        container.layoutIfNeeded()
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()

        XCTAssertEqual(hosting.rootView.viewModel.dismissBehavior, .morphHome)
        XCTAssertEqual(hosting.rootView.viewModel.logoViewportFrame, CGRect(x: 0, y: 0, width: 440, height: 661))

        // Available heights corresponding to the software keyboard showing and then hiding.
        let availableHeights: [(CGFloat, CGFloat)] = [(636, 509), (788, 661)]
        for (height, viewportHeight) in availableHeights {
            container.frame.size.height = height
            container.setNeedsLayout()
            container.layoutIfNeeded()
            hosting.view.setNeedsLayout()
            hosting.view.layoutIfNeeded()
            XCTAssertEqual(hosting.rootView.viewModel.logoViewportFrame, CGRect(x: 0, y: 0, width: 440, height: viewportHeight))
        }

        container.frame.origin.y = 62
        container.setNeedsLayout()
        container.layoutIfNeeded()
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()

        XCTAssertEqual(hosting.rootView.viewModel.logoViewportFrame, CGRect(x: 0, y: 62, width: 440, height: 661))
    }

    func test_floatingUIFlagOffDoesNotPublishLogoViewport() throws {
        let (host, hosting, container, window) = try makeWindowedHost(isFloatingUIEnabled: false)
        defer { host.tearDown(); window.isHidden = true }

        XCTAssertNil(hosting.rootView.viewModel.logoViewportFrame)

        host.morphLogoHomeForDismiss(matching: 0.2625)
        container.frame.size.height = 788
        container.setNeedsLayout()
        container.layoutIfNeeded()
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()

        XCTAssertEqual(hosting.rootView.viewModel.dismissBehavior, .morphHome)
        XCTAssertNil(hosting.rootView.viewModel.logoViewportFrame)
    }

    private func makeWindowedHost(isFloatingUIEnabled: Bool) throws
        -> (UnifiedSuggestionsHost, UIHostingController<UnifiedSuggestionsView>, UIView, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        let parent = UIViewController()
        window.rootViewController = parent
        window.isHidden = false
        window.layoutIfNeeded()

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 440, height: 860))
        parent.view.addSubview(container)
        let inputs = UnifiedSuggestionsInputs(mode: .search, isTyping: false, hasFavorites: false,
                                               hasMessages: false, hasRecents: false, resultsPending: false)
        let host = UnifiedSuggestionsHost(config: UnifiedSuggestionsHostConfig(
            source: EmptySuggestionsSource(),
            inputsPublisher: Just(inputs).eraseToAnyPublisher(),
            isAddressBarAtBottom: true,
            favoritesProvider: { nil },
            onSelectRow: { _ in },
            onDeleteRow: { _ in },
            onTapAheadRow: { _ in }))
        host.start(in: container, parentViewController: parent, isFloatingUIEnabled: isFloatingUIEnabled, textPublisher: Just(""))
        host.setContentInsets(UIEdgeInsets(top: 0, left: 0, bottom: 127, right: 0))
        container.setNeedsLayout()
        container.layoutIfNeeded()
        let hosting = try XCTUnwrap(parent.children.first as? UIHostingController<UnifiedSuggestionsView>)
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        return (host, hosting, container, window)
    }
}

private final class EmptySuggestionsSource: SuggestionsSource {
    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never> = Just([]).eraseToAnyPublisher()
    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}
}
