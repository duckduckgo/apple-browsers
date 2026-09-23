//
//  AIChatContextualSuggestionsStrip.swift
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
import UIKit

/// A container that only claims touches landing on a chip, so taps in the gaps pass through.
final class ChipHitTestingView: UIView {
    var containsChip: ((CGPoint) -> Bool)?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        containsChip?(point) ?? false
    }
}

/// The input the strip hangs off. Implemented by the UTI host, which owns the bar the strip sits above.
@MainActor
protocol AIChatContextualSuggestionsStripAnchoring: AnyObject {
    var inputCardTopAnchor: NSLayoutYAxisAnchor { get }
    var inputCardLeadingAnchor: NSLayoutXAxisAnchor { get }
    var inputCardTrailingAnchor: NSLayoutXAxisAnchor { get }
    /// The mounted input bar, so the scrim can be layered beneath it.
    var mountedInputView: UIView? { get }
    var isInputExpanded: Bool { get }
}

/// The row of suggestion chips shown above the input card.
///
/// One strip serves both contextual surfaces, borrowed by whichever is up the same way the input bar is:
/// it reads the session's view state itself, so a surface only says that it holds it and in which style.
@MainActor
final class AIChatContextualSuggestionsStrip {

    /// How a surface wears the strip. The two differ together, so they travel as one value.
    enum Style {
        /// Over the page, which the surface already dims. Carries the attach offer, its only one.
        case floating
        /// Over a chat transcript, which needs scrimming. The input card's placeholder chip already
        /// carries the attach offer here, so the strip must not repeat it.
        case activeChat

        var isDimmed: Bool { self == .activeChat }
        var offersQuickActions: Bool { self == .floating }
    }

    /// The content of one emission, so view-state changes that leave the chips alone don't rebuild them.
    private struct Content: Equatable {
        let suggestions: [ContextualSuggestedPrompt]
        let quickActions: [AIChatContextualQuickAction]
        let isLoaded: Bool

        init(viewState: SheetViewState) {
            suggestions = viewState.suggestions
            quickActions = viewState.quickActions
            isLoaded = viewState.suggestionsLoadState == .loaded
        }
    }

    private let controller: AIChatContextualInputViewController
    private unowned let input: AIChatContextualSuggestionsStripAnchoring

    /// The surface currently holding the strip, so it can be detached before it moves to another.
    private weak var parent: UIViewController?
    private var style: Style = .floating
    /// True once the strip has shown for the current mount: the first batch appears instantly (riding the
    /// input's entrance), later ones fade. Reset when the strip leaves a surface.
    private var hasShown = false
    private var cancellable: AnyCancellable?
    /// Kept while unmounted: the subscription is made once, so a surface taking the strip would otherwise
    /// wait for the next emission to learn what to show.
    private var latestContent: Content?

    private lazy var container: ChipHitTestingView = {
        let view = ChipHitTestingView()
        view.backgroundColor = .clear
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.containsChip = { [weak self] point in
            guard let self else { return false }
            return self.controller.containsStartAction(at: point, from: self.container)
        }
        return view
    }()

    /// Scrims the content above the input while the strip is up, so the chips read against a bright
    /// transcript. Only `.activeChat` enables it; `.floating` already dims the whole page.
    private lazy var dimView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(controller: AIChatContextualInputViewController, input: AIChatContextualSuggestionsStripAnchoring) {
        self.controller = controller
        self.input = input
    }

    /// The strip's container, so a hosting surface can move it with the input.
    var containerView: UIView { container }

    /// The single writer: the strip follows the session's view state rather than being pushed at by each
    /// surface, so a dismissed-but-retained surface can't overwrite what the current one is showing.
    func bind(to viewState: AnyPublisher<SheetViewState, Never>) {
        cancellable = viewState
            .map(Content.init(viewState:))
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] content in
                self?.latestContent = content
                self?.apply(content)
            }
    }

    // MARK: - Mounting

    /// Mounts the strip above the input card in `parent`. Taps in the gaps pass through. The strip is
    /// shared across surfaces, so mounting it here first detaches it from wherever it was.
    func embed(in parent: UIViewController, style: Style) {
        guard self.parent !== parent else { return }
        detachFromCurrentParent()
        self.parent = parent
        self.style = style
        parent.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.clearStartActionsHorizontalInset()
        container.addSubview(controller.view)
        if style.isDimmed {
            embedDimView(in: parent)
        }
        parent.view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(greaterThanOrEqualTo: parent.view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: input.inputCardLeadingAnchor),
            container.trailingAnchor.constraint(equalTo: input.inputCardTrailingAnchor),
            container.bottomAnchor.constraint(equalTo: input.inputCardTopAnchor),
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        controller.didMove(toParent: parent)
        if let latestContent { apply(latestContent) }
    }

    /// Detaches from `parent`, but only if it still holds the strip: a surface animating out finishes
    /// after the next one may already have taken it.
    func detach(from parent: UIViewController) {
        guard self.parent === parent else { return }
        detachFromCurrentParent()
    }

    /// A full-screen scrim layered below the input card, so the card and the strip float on top of it —
    /// one continuous dim rather than a band that ends in a hard line above the input.
    private func embedDimView(in parent: UIViewController) {
        if let inputView = input.mountedInputView, inputView.superview === parent.view {
            parent.view.insertSubview(dimView, belowSubview: inputView)
        } else {
            parent.view.addSubview(dimView)
        }
        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: parent.view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
        ])
    }

    private func detachFromCurrentParent() {
        // Reused across mounts, so it is handed back the way it started: no slide transform, invisible,
        // and empty. Otherwise the next surface mounts it showing the previous one's chips.
        container.transform = .identity
        container.alpha = 0
        container.removeFromSuperview()
        if style.isDimmed {
            dimView.alpha = 0
            dimView.removeFromSuperview()
        }
        parent = nil
        // The next surface's first batch should appear instantly again.
        hasShown = false
        guard controller.parent != nil else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        setChips(suggestions: [], quickActions: [], isLoading: false)
    }

    // MARK: - Content

    private func apply(_ content: Content) {
        // Nothing to show it in: the surface that takes the strip next gets the state current then.
        guard parent != nil else { return }

        guard content.isLoaded else {
            // Loader alone while suggestions resolve. Passing the actions through here would flash the
            // placeholder chip beside it, then replace it.
            setChips(suggestions: [], quickActions: [], isLoading: true)
            return
        }

        let quickActions = style.offersQuickActions ? content.quickActions : []
        guard !content.suggestions.isEmpty || !quickActions.isEmpty else {
            controller.updateSuggestionsLoading(false)
            // Cleared only once invisible: removing them collapses the stack into the input's own animation.
            fade(to: 0) { [weak self] in
                self?.controller.updateStartActions(suggestions: [], quickActions: [])
            }
            return
        }
        setChips(suggestions: content.suggestions, quickActions: quickActions, isLoading: false)
        showIfNeeded()
    }

    private func setChips(suggestions: [ContextualSuggestedPrompt],
                          quickActions: [AIChatContextualQuickAction],
                          isLoading: Bool) {
        controller.updateStartActions(suggestions: suggestions, quickActions: quickActions)
        controller.updateSuggestionsLoading(isLoading)
    }

    // MARK: - Visibility

    /// Collapsing the input hides the strip without clearing it, so it returns when the input expands again.
    func setInputExpanded(_ expanded: Bool) {
        if expanded {
            showIfNeeded()
        } else {
            fade(to: 0)
        }
    }

    /// Chips arrive asynchronously with the page context, so this waits for the first batch with content
    /// rather than showing at mount. They ride the input's entrance the first time and fade in thereafter.
    private func showIfNeeded() {
        guard controller.startActionCount > 0, input.isInputExpanded else { return }
        guard !hasShown else {
            fade(to: 1)
            return
        }
        hasShown = true
        container.alpha = 1
        if style.isDimmed { dimView.alpha = ContextualSurfaceScrim.alpha }
        controller.showStartActions()
    }

    private func fade(to alpha: CGFloat, completion: (() -> Void)? = nil) {
        guard container.alpha != alpha else {
            completion?()
            return
        }
        let dimAlpha: CGFloat = style.isDimmed ? (alpha > 0 ? ContextualSurfaceScrim.alpha : 0) : 0
        UIView.animate(withDuration: 0.2, animations: {
            self.container.alpha = alpha
            if self.style.isDimmed { self.dimView.alpha = dimAlpha }
        }, completion: { finished in
            // An interrupted fade was overtaken; its clear would empty the row coming back.
            guard finished else { return }
            completion?()
        })
    }

#if DEBUG
    /// Test-only: the chips the strip is actually showing.
    var chipCountForTesting: Int { controller.startActionCount }
#endif
}
