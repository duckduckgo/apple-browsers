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
    /// `raisesKeyboard` says whether the new page brings its own keyboard, which a keyboard already up can wait for.
    func makeNewTabTransition(from start: NewTabTransitionCoordinator.Start, raisesKeyboard: Bool) -> NewTabTransitioning?
    /// Closes the presented screen without animation and out of sight.
    func closePresentedScreenUnseen(then completion: @escaping () -> Void)
    func dismissPresentedScreen(then completion: @escaping () -> Void)
}

/// How a new tab comes into view. Growing in is the default; the others name why a tab doesn't.
enum NewTabEntrance {
    case grows
    /// Arrives from another app, a widget, a shortcut or app launch, which bring their own entrance.
    case fromOutsideTheApp
    /// A swipe past the last tab already moved the new tab into place.
    case followsSwipe
    /// A screen presented over the page still covers it, so there is no page to grow from.
    case underPresentedScreen
}

/// The one way to open a new tab with the transition:
/// - From the page: `newTab()` and the other openers grow by default; `open { … }` covers several steps at once.
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
        guard let transition = begin(from: start, raisesKeyboard: true) else { return false }
        prepared = transition
        scheduleOnNextTurn { [weak self, weak transition] in
            guard let self, let transition, prepared === transition else { return }
            cancelPrepared()
        }
        return true
    }

    /// Builds the new tab with `build`, growing it in unless `entrance` says why not. Returns whether it animated.
    /// Pass `raisesKeyboard: false` for a page without its own keyboard, such as a website.
    @discardableResult
    func open(entrance: NewTabEntrance = .grows, raisesKeyboard: Bool = true, _ build: () -> Void) -> Bool {
        switch entrance {
        case .grows:
            return grow(raisesKeyboard: raisesKeyboard, build)
        case .fromOutsideTheApp, .followsSwipe, .underPresentedScreen:
            build()
            return false
        }
    }

    /// Builds the new tab under the transition when it's on, otherwise just builds it.
    private func grow(raisesKeyboard: Bool, _ build: () -> Void) -> Bool {
        guard let transition = takePrepared() ?? begin(from: .page, raisesKeyboard: raisesKeyboard) else {
            build()
            return false
        }
        reveal(transition, builtBy: build)
        return true
    }

    /// Like `open`, with the presented screen kept in the old screen and closed unseen under the cover.
    func openClosingPresentedScreen(_ build: @escaping () -> Void) {
        guard let transition = begin(from: .presentedScreen, raisesKeyboard: true) else {
            host?.dismissPresentedScreen(then: build)
            return
        }
        // Until it closes, the page sits in the presentation's dimmed container, so the tab grows only after.
        host?.closePresentedScreenUnseen { [weak self] in
            self?.reveal(transition, builtBy: build)
        }
    }


    /// Focus the input asks for waits while a new tab comes in, so the keyboard lands with it.
    func scheduleInputFocus(_ focus: @escaping () -> Void) {
        guard let current else { return scheduleOnNextTurn(focus) }
        current.keyboardGate.whenOpen { [scheduleOnNextTurn] in scheduleOnNextTurn(focus) }
    }

    private func begin(from start: Start, raisesKeyboard: Bool) -> NewTabTransitioning? {
        guard current == nil, let transition = host?.makeNewTabTransition(from: start, raisesKeyboard: raisesKeyboard) else { return nil }
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
