//
//  NewTabTransitionCoordinator.swift
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

import UIKit

/// A new-tab transition as the coordinator drives it.
@MainActor
protocol NewTabTransitioning: AnyObject {
    var keyboardGate: NewTabKeyboardGate { get }
    func revealNewPage(_ page: UIView, builtBy build: () -> Void)
    /// Runs once the transition is over, whether it finished or was cancelled.
    func addCompletion(_ completion: @escaping () -> Void)
    func cancel()
}

/// Lets UI that is shared by every tab react to a new tab coming in, without knowing about the transition.
@MainActor
protocol NewTabOpeningObserving: AnyObject {
    var isOpeningNewTab: Bool { get }
    /// Runs `action` once the opening new tab has fully appeared, or right away if none is opening.
    func afterNewTabOpens(_ action: @escaping () -> Void)
}

/// What the coordinator needs from the screen it opens new tabs on.
@MainActor
protocol NewTabTransitionHost: AnyObject {
    /// The view the new tab grows into.
    var newPageView: UIView { get }
    func makeNewTabTransition(from start: NewTabTransitionCoordinator.Start) -> NewTabTransitioning?
    /// Closes the presented screen without animation and out of sight.
    func closePresentedScreenUnseen(then completion: @escaping () -> Void)
    func dismissPresentedScreen(then completion: @escaping () -> Void)
}

/// The one way to open a new tab with the transition:
/// - From the page: `open { newTab() }`.
/// - From a presented screen such as a sheet: `openClosingPresentedScreen { ... }`.
/// - From a screen that dismisses first, like the tab manager: `prepare(from: .tabManager)`, then `open` as usual.
/// One transition runs at a time; a tab opened while one runs is built without its own.
@MainActor
final class NewTabTransitionCoordinator: NewTabOpeningObserving {

    enum Start {
        /// The browser page.
        case page
        /// The browser with a presented screen still over it, which stays in the snapshot.
        case presentedScreen
        /// The tab manager, frozen before it dismisses.
        case tabManager
    }

    private weak var host: NewTabTransitionHost?
    private let scheduleOnNextTurn: (@escaping () -> Void) -> Void
    private(set) var current: NewTabTransitioning?
    private var prepared: NewTabTransitioning?

    init(host: NewTabTransitionHost,
         scheduleOnNextTurn: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.host = host
        self.scheduleOnNextTurn = scheduleOnNextTurn
    }

    var isOpeningNewTab: Bool { current != nil }

    func afterNewTabOpens(_ action: @escaping () -> Void) {
        guard let current else { return action() }
        current.addCompletion(action)
    }

    /// Freezes the screen now for a new tab that `open` builds later this turn.
    /// If nothing opens one, the transition is cancelled so its cover never stays.
    @discardableResult
    func prepare(from start: Start) -> Bool {
        cancelPrepared()
        guard let transition = begin(from: start) else { return false }
        prepared = transition
        scheduleOnNextTurn { [weak self, weak transition] in
            guard let self, let transition, prepared === transition else { return }
            cancelPrepared()
        }
        return true
    }

    /// Builds the new tab with `build` under the transition when it's on, otherwise just builds it.
    /// Returns whether it animated.
    @discardableResult
    func open(_ build: () -> Void) -> Bool {
        guard let transition = takePrepared() ?? begin(from: .page) else {
            build()
            return false
        }
        reveal(transition, builtBy: build)
        return true
    }

    /// Like `open`, with the presented screen kept in the old screen and closed unseen under the cover.
    func openClosingPresentedScreen(_ build: @escaping () -> Void) {
        guard let transition = begin(from: .presentedScreen) else {
            host?.dismissPresentedScreen(then: build)
            return
        }
        // A keyboard raised while a screen is still being dismissed skips its slide.
        host?.closePresentedScreenUnseen(then: transition.keyboardGate.hold())
        reveal(transition, builtBy: build)
    }

    /// The user acts while a tab comes in, so it lands at once instead of making them wait.
    /// A prepared transition is left alone: the tab it's for hasn't been built yet.
    func finishCurrent() {
        guard let current, current !== prepared else { return }
        current.cancel()
    }

    /// Focus the input asks for waits while a new tab comes in, so the keyboard lands with it.
    func scheduleInputFocus(_ focus: @escaping () -> Void) {
        guard let current else { return scheduleOnNextTurn(focus) }
        current.keyboardGate.whenOpen { [scheduleOnNextTurn] in scheduleOnNextTurn(focus) }
    }

    private func begin(from start: Start) -> NewTabTransitioning? {
        guard current == nil, let transition = host?.makeNewTabTransition(from: start) else { return nil }
        current = transition
        transition.addCompletion { [weak self, weak transition] in
            guard let self, current === transition else { return }
            current = nil
        }
        return transition
    }

    private func reveal(_ transition: NewTabTransitioning, builtBy build: () -> Void) {
        guard let page = host?.newPageView else {
            build()
            transition.cancel()
            return
        }
        transition.revealNewPage(page, builtBy: build)
    }

    private func takePrepared() -> NewTabTransitioning? {
        defer { prepared = nil }
        return prepared
    }

    private func cancelPrepared() {
        takePrepared()?.cancel()
    }
}
