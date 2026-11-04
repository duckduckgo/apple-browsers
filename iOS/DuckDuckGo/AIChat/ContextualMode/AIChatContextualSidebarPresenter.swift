//
//  AIChatContextualSidebarPresenter.swift
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

import DesignResourcesKit
import UIKit

/// Shows the contextual Duck.ai surface in a column beside the page, where the window has room for one.
@MainActor
protocol AIChatContextualSidebarHosting: AnyObject {

    /// When false the surface is presented as a sheet instead.
    var canPresentContextualSidebar: Bool { get }

    /// - Parameter coversPage: False when the window is resizing, which reflows the page anyway; an image of it at
    ///   its old size would show as a second copy.
    func presentContextualSidebar(_ viewController: UIViewController, animated: Bool, coversPage: Bool)

    /// False once `viewController` starts sliding out, though it stays in the column until it is gone.
    func isContextualSidebarShowing(_ viewController: UIViewController) -> Bool

    /// `completion` runs once `viewController` has left the sidebar, or straight away when it isn't in it.
    func dismissContextualSidebar(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)?)

    /// Takes `viewController` out of the sidebar at once, so it can be presented elsewhere while the column closes.
    func detachContextualSidebar(_ viewController: UIViewController, animated: Bool)
}

/// Slides a child view controller in and out of the iPad sidebar column. The page's trailing edge is pinned to the
/// column's leading edge, so moving the column also narrows or widens the page, in the same animation.
@MainActor
final class AIChatContextualSidebarPresenter {

    private enum Metrics {
        static let slideDuration: TimeInterval = 0.45
        static let pageDissolveDelay: TimeInterval = 0.08
        static let pageDissolveDuration: TimeInterval = 0.3
    }

    /// Traces a critically damped spring, which never overshoots and so never reflows the page twice, but ends
    /// with the movement instead of its long tail, so whatever waits on the slide isn't held up by it.
    private static var slideTiming: UICubicTimingParameters {
        UICubicTimingParameters(controlPoint1: CGPoint(x: 0.2, y: 0.15), controlPoint2: CGPoint(x: 0.25, y: 1))
    }

    private weak var parent: UIViewController?
    /// The page beside the column, which re-lays out for its new width as soon as the column starts moving.
    private weak var pageView: UIView?
    private let pageBackgroundColor: () -> UIColor?
    private let container: UIView
    /// Pins the column's trailing edge to the window's trailing edge.
    private let shownConstraint: NSLayoutConstraint
    /// Pins the column's leading edge to the window's trailing edge, just off screen.
    private let hiddenConstraint: NSLayoutConstraint

    private lazy var separator: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .lines)
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var animator: UIViewPropertyAnimator?
    /// An image of a detached view controller, closing the column in its place.
    private var standIn: UIView?
    private var pageSnapshot: UIView?
    private var pageDissolveAnimator: UIViewPropertyAnimator?
    private var dismissalCompletions: [() -> Void] = []

    /// The view controller in the column, including one still sliding out.
    private(set) var hostedViewController: UIViewController?

    /// True from the moment the column starts coming in until it starts leaving.
    private(set) var isPresenting = false

    init(parent: UIViewController,
         pageView: UIView?,
         pageBackgroundColor: @escaping () -> UIColor? = { nil },
         container: UIView,
         shownConstraint: NSLayoutConstraint,
         hiddenConstraint: NSLayoutConstraint) {
        self.parent = parent
        self.pageView = pageView
        self.pageBackgroundColor = pageBackgroundColor
        self.container = container
        self.shownConstraint = shownConstraint
        self.hiddenConstraint = hiddenConstraint
    }

    func present(_ viewController: UIViewController, animated: Bool = true, coversPage: Bool = true) {
        guard let parent, !(isPresenting && hostedViewController === viewController) else { return }
        if hostedViewController === viewController {
            reverseDismissal(of: viewController, animated: animated)
            return
        }
        // A different surface already filling the column is swapped in place rather than slid out and back.
        let isReplacingShownSurface = isPresenting
        removeStandIn()
        removeHostedViewController()
        embed(viewController, in: parent)
        isPresenting = true
        move(toShown: true, animated: animated && !isReplacingShownSurface, coversPage: coversPage) { [weak viewController] in
            UIAccessibility.post(notification: .screenChanged, argument: viewController?.view)
        }
    }

    /// - Parameter coversPage: False when the page has already changed under the column, as when its tab closed,
    ///   so a snapshot would show the old page.
    func dismiss(_ viewController: UIViewController,
                 animated: Bool,
                 coversPage: Bool = true,
                 completion: (() -> Void)?) {
        guard hostedViewController === viewController else {
            completion?()
            return
        }
        if let completion {
            dismissalCompletions.append(completion)
        }
        guard isPresenting else {
            // Already sliding out; a request that can't wait cuts the slide short.
            if !animated {
                finishDismissal()
            }
            return
        }
        isPresenting = false
        // The keyboard leaves with the column rather than after it, and nothing in it takes a tap on the way out.
        viewController.view.endEditing(true)
        viewController.view.isUserInteractionEnabled = false
        move(toShown: false, animated: animated, coversPage: coversPage) { [weak self] in
            self?.finishDismissal()
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
    }

    /// The column slides out as usual, but with an image of `viewController` in it, so the view controller itself is
    /// free straight away, for example to carry on as a sheet when a window shrinks past the sidebar.
    func detach(_ viewController: UIViewController, animated: Bool) {
        guard hostedViewController === viewController else { return }
        guard animated, isPresenting, let image = container.snapshotView(afterScreenUpdates: false) else {
            dismiss(viewController, animated: false, completion: nil)
            return
        }
        image.frame = container.bounds
        image.isUserInteractionEnabled = false
        container.addSubview(image)
        standIn = image
        removeHostedViewController()
        isPresenting = false
        // Detaching is for a resizing window, which reflows the page anyway: an image of it would show as a second copy.
        move(toShown: false, animated: true, coversPage: false) { [weak self] in
            self?.finishDismissal()
        }
    }

    /// A view controller asked back while it slides out turns around, and what was waiting on its exit is dropped.
    private func reverseDismissal(of viewController: UIViewController, animated: Bool) {
        dismissalCompletions.removeAll()
        isPresenting = true
        viewController.view.isUserInteractionEnabled = true
        move(toShown: true, animated: animated) { [weak viewController] in
            UIAccessibility.post(notification: .screenChanged, argument: viewController?.view)
        }
    }

    private func removeStandIn() {
        standIn?.removeFromSuperview()
        standIn = nil
    }

    private func embed(_ viewController: UIViewController, in parent: UIViewController) {
        container.isHidden = false
        // Settles the column where it rests before the slide, so the slide starts from there.
        parent.view.layoutIfNeeded()

        parent.addChild(viewController)
        let hostedView: UIView = viewController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostedView)
        if separator.superview == nil {
            container.addSubview(separator)
            NSLayoutConstraint.activate([
                separator.topAnchor.constraint(equalTo: container.topAnchor),
                separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                separator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            ])
        }
        container.bringSubviewToFront(separator)
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: container.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostedView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        // Laid out at full width up front, so only the column's position animates and never its content.
        container.layoutIfNeeded()
        hostedViewController = viewController
        viewController.didMove(toParent: parent)
    }

    private func move(toShown shown: Bool, animated: Bool, coversPage: Bool = true, completion: @escaping () -> Void) {
        guard let parentView = parent?.view else { return }
        // Stopping leaves the column wherever it is, so a reversal carries on from there.
        animator?.stopAnimation(true)
        animator = nil

        let isAnimated = animated && parentView.window != nil
        if isAnimated && coversPage {
            coverPageWithSnapshot()
        } else {
            removePageSnapshot()
        }

        // Deactivated first: the two poses contradict each other.
        NSLayoutConstraint.deactivate([shown ? hiddenConstraint : shownConstraint])
        NSLayoutConstraint.activate([shown ? shownConstraint : hiddenConstraint])

        guard isAnimated else {
            parentView.layoutIfNeeded()
            completion()
            return
        }

        let animator = UIViewPropertyAnimator(duration: Metrics.slideDuration, timingParameters: Self.slideTiming)
        animator.addAnimations {
            parentView.layoutIfNeeded()
        }
        animator.addCompletion { [weak self, weak animator] position in
            guard let self, self.animator === animator else { return }
            self.animator = nil
            if position == .end {
                completion()
            }
        }
        self.animator = animator
        animator.startAnimation()
        dissolvePageSnapshot()
    }

    /// The page re-lays out for its new width at the start of the slide, which would read as a jump. An image of
    /// it as it was, pinned at its old size, covers that and then fades into the new layout as the column moves.
    /// Its backdrop follows the page, so width the page gains shows its background rather than the new layout.
    private func coverPageWithSnapshot() {
        removePageSnapshot()
        guard let pageView, let snapshot = pageView.snapshotView(afterScreenUpdates: false) else { return }
        let cover = UIView(frame: pageView.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = pageBackgroundColor()
        cover.isUserInteractionEnabled = false
        snapshot.frame = cover.bounds
        snapshot.autoresizingMask = []
        cover.addSubview(snapshot)
        pageView.addSubview(cover)
        pageSnapshot = cover
    }

    private func dissolvePageSnapshot() {
        guard let snapshot = pageSnapshot else { return }
        let dissolve = UIViewPropertyAnimator(duration: Metrics.pageDissolveDuration, curve: .easeInOut) {
            snapshot.alpha = 0
        }
        dissolve.addCompletion { [weak self, weak snapshot] _ in
            snapshot?.removeFromSuperview()
            if let self, self.pageSnapshot === snapshot {
                self.pageSnapshot = nil
                self.pageDissolveAnimator = nil
            }
        }
        pageDissolveAnimator = dissolve
        dissolve.startAnimation(afterDelay: Metrics.pageDissolveDelay)
    }

    private func removePageSnapshot() {
        pageDissolveAnimator?.stopAnimation(true)
        pageDissolveAnimator = nil
        pageSnapshot?.removeFromSuperview()
        pageSnapshot = nil
    }

    /// Takes the column off screen for good and runs every completion waiting on it.
    private func finishDismissal() {
        animator?.stopAnimation(true)
        animator = nil
        removePageSnapshot()
        isPresenting = false
        NSLayoutConstraint.deactivate([shownConstraint])
        NSLayoutConstraint.activate([hiddenConstraint])
        parent?.view.layoutIfNeeded()
        container.isHidden = true
        removeStandIn()
        removeHostedViewController()
    }

    private func removeHostedViewController() {
        if let viewController = hostedViewController {
            hostedViewController = nil
            viewController.willMove(toParent: nil)
            viewController.view.removeFromSuperview()
            viewController.removeFromParent()
            // The same view controller can be presented as a sheet next, which positions its view by frame.
            viewController.view.translatesAutoresizingMaskIntoConstraints = true
            viewController.view.isUserInteractionEnabled = true
        }
        let completions = dismissalCompletions
        dismissalCompletions.removeAll()
        completions.forEach { $0() }
    }
}
