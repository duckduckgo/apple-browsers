//
//  AIChatContextualFloatingInputViewController.swift
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
import os.log

protocol AIChatContextualFloatingInputViewControllerDelegate: AnyObject {
    func aiChatContextualFloatingInputViewControllerDidRequestDismiss(_ viewController: AIChatContextualFloatingInputViewController)
}

/// Chip suggestions and the unified toggle input floating over the page, with no sheet chrome.
///
/// Dismissed by tapping the dimmed page, by swiping the input down, or by a VoiceOver escape.
@MainActor
final class AIChatContextualFloatingInputViewController: UIViewController {

    /// Matches the design's system overlay scrim, `rgba(0, 0, 0, 0.2)`.
    static let dimmingAlpha: CGFloat = 0.2

    private enum Constants {
        /// Drag distance that maps to a fully faded dim, and the point past which release dismisses.
        static let dragFadeDistance: CGFloat = 200
        static let dragDismissDistance: CGFloat = 80
        static let dismissVelocityThreshold: CGFloat = 600
        static let springBackDuration: TimeInterval = 0.3
        static let entranceDuration: TimeInterval = 0.25
        static let chipsRevealDuration: TimeInterval = 0.2
        /// The chips controller already carries the design's 12pt gap above the card via its own
        /// bottom padding, so this adds nothing on top of it.
        static let chipsBottomSpacing: CGFloat = 0
        /// Deliberately longer than the keyboard's own ~0.25s slide, so the content keeps dissolving
        /// after it reaches the bottom rather than snapping away the moment the keyboard lands.
        static let dismissAnimationDuration: TimeInterval = 0.45
    }

    private var isDismissing = false
    private var hasPlayedChipsEntrance = false

    /// The host's input view while mounted here. Owned by the host and reused across mounts, so any
    /// alpha applied during dismissal has to be restored on the way out.
    private weak var mountedInputView: UIView?

    weak var delegate: AIChatContextualFloatingInputViewControllerDelegate?

    private let utiHost: AIChatContextualUTIHost
    let chipsViewController: AIChatContextualInputViewController

    private lazy var dimView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityViewIsModal = true
        view.isAccessibilityElement = true
        view.accessibilityLabel = UserText.aiChatContextualFloatingInputDismissAccessibility
        view.accessibilityTraits = .button
        return view
    }()

    /// Spans the full width, so it must not swallow taps in the gaps around the chips — those belong
    /// to the dim behind it.
    private final class ChipHitTestingView: UIView {
        var containsChip: ((CGPoint) -> Bool)?

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            containsChip?(point) ?? false
        }
    }

    private lazy var chipsContainerView: ChipHitTestingView = {
        let view = ChipHitTestingView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        view.containsChip = { [weak self] point in
            guard let self else { return false }
            return self.chipsViewController.containsStartAction(at: point, from: self.chipsContainerView)
        }
        return view
    }()

    private lazy var dimTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDimTap))

    /// On the whole surface, so the drag works from the chips, the bar or the dimmed page alike.
    private lazy var dragToDismissRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleDragToDismiss))
        recognizer.delegate = self
        return recognizer
    }()

    init(utiHost: AIChatContextualUTIHost, chipsViewController: AIChatContextualInputViewController) {
        self.utiHost = utiHost
        self.chipsViewController = chipsViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addGestureRecognizer(dragToDismissRecognizer)
        addDimView()
        addChipsContainer()
    }

    /// Adds the floating input over `parent`'s content and mounts the shared input above the keyboard.
    func install(in parent: UIViewController) {
        guard self.parent !== parent else { return }

        parent.addChild(self)
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: parent.view.topAnchor),
            view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
        ])
        didMove(toParent: parent)

        let inputView = utiHost.mount(in: self)
        mountedInputView = inputView
        embedChips(above: utiHost.inputCardTopAnchor)
        revealDim()
        revealChips()
        Logger.contextualUTI.info("Floating contextual input installed")
    }

    /// Called once the input has finished activating: activation re-applies the bar's render state and
    /// would otherwise cut this fade short.
    /// Fades this controller's own view rather than the mounted input's.
    ///
    /// The input belongs to the host and is reused across presentations; activating it re-applies its
    /// render state, which flushed an animation set directly on it on every open after the first.
    /// Nothing outside this controller touches our own view's alpha.
    func playEntrance() {
        view.alpha = 0
        UIView.animate(withDuration: Constants.entranceDuration,
                       delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            self.view.alpha = 1
        }
    }

    /// Chips arrive asynchronously with the page context, so the entrance plays on the first batch
    /// that actually has content rather than at install time.
    func playChipsEntranceIfNeeded() {
        guard !hasPlayedChipsEntrance, chipsViewController.startActionCount > 0 else { return }
        hasPlayedChipsEntrance = true
        // Resting frames first: each chip's start offset is measured from where it lands.
        view.layoutIfNeeded()
        chipsContainerView.alpha = 1
        chipsViewController.animateStartActionsIn()
    }

    /// Rides the keyboard down instead of vanishing: resigning the input drives the keyboard guide,
    /// and laying out inside the animation block carries the bar with it.
    func dismissRidingKeyboard(completion: @escaping () -> Void) {
        guard !isDismissing else { return }
        isDismissing = true

        utiHost.deactivateInput()
        UIView.animate(withDuration: Constants.dismissAnimationDuration,
                       delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState],
                       animations: {
            self.dimView.alpha = 0
            self.chipsContainerView.alpha = 0
            self.mountedInputView?.alpha = 0
            self.view.layoutIfNeeded()
        }, completion: { _ in
            completion()
        })
    }

    func remove() {
        utiHost.unmount()
        // The host reuses this view, so anything applied while dragging has to be undone.
        mountedInputView?.alpha = 1
        mountedInputView?.transform = .identity
        mountedInputView = nil
        removeChips()
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
        Logger.contextualUTI.info("Floating contextual input removed")
    }

    override func accessibilityPerformEscape() -> Bool {
        requestDismiss()
        return true
    }

#if DEBUG
    /// Test-only: exercises the dim tap without synthesising a touch.
    func simulateDimTapForTesting() {
        handleDimTap()
    }

    var hasPlayedChipsEntranceForTesting: Bool {
        hasPlayedChipsEntrance
    }
#endif
}

private extension AIChatContextualFloatingInputViewController {

    func addDimView() {
        view.addSubview(dimView)
        dimView.addGestureRecognizer(dimTapRecognizer)
        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Horizontal alignment waits for `embedChips`, since the card's anchors only share an ancestor
    /// with us once the input is mounted.
    func addChipsContainer() {
        // Faded in by `revealChips` so the loader arrives smoothly rather than snapping on.
        chipsContainerView.alpha = 0
        view.addSubview(chipsContainerView)
        chipsContainerView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
    }

    /// Aligned to the input card rather than the bar's outer view, which carries its own padding.
    func embedChips(above inputCardTop: NSLayoutYAxisAnchor) {
        addChild(chipsViewController)
        chipsViewController.view.translatesAutoresizingMaskIntoConstraints = false
        // After the view loads: the inset constraints don't exist until `viewDidLoad` builds them.
        chipsViewController.clearStartActionsHorizontalInset()
        chipsContainerView.addSubview(chipsViewController.view)
        NSLayoutConstraint.activate([
            chipsContainerView.leadingAnchor.constraint(equalTo: utiHost.inputCardLeadingAnchor),
            chipsContainerView.trailingAnchor.constraint(equalTo: utiHost.inputCardTrailingAnchor),
            chipsContainerView.bottomAnchor.constraint(equalTo: inputCardTop, constant: -Constants.chipsBottomSpacing),
            chipsViewController.view.topAnchor.constraint(equalTo: chipsContainerView.topAnchor),
            chipsViewController.view.leadingAnchor.constraint(equalTo: chipsContainerView.leadingAnchor),
            chipsViewController.view.trailingAnchor.constraint(equalTo: chipsContainerView.trailingAnchor),
            chipsViewController.view.bottomAnchor.constraint(equalTo: chipsContainerView.bottomAnchor),
        ])
        chipsViewController.didMove(toParent: self)
    }

    func removeChips() {
        guard chipsViewController.parent != nil else { return }
        chipsViewController.willMove(toParent: nil)
        chipsViewController.view.removeFromSuperview()
        chipsViewController.removeFromParent()
    }

    /// Set outright rather than faded in: the chips' glass samples whatever sits behind it, so a dim
    /// still animating underneath gets captured mid-fade and the pills keep that stale backdrop.
    func revealDim() {
        dimView.alpha = Self.dimmingAlpha
    }

    func revealChips() {
        UIView.animate(withDuration: Constants.chipsRevealDuration,
                       delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            self.chipsContainerView.alpha = 1
        }
    }


    @objc func handleDimTap() {
        requestDismiss()
    }

    @objc func handleDragToDismiss(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .changed:
            applyDragProgress(recognizer.translation(in: view).y)
        case .ended:
            let translation = recognizer.translation(in: view).y
            let velocity = recognizer.velocity(in: view).y
            if translation > Constants.dragDismissDistance || velocity > Constants.dismissVelocityThreshold {
                requestDismiss()
            } else {
                springBackFromDrag()
            }
        case .cancelled, .failed:
            springBackFromDrag()
        default:
            break
        }
    }

    /// Upward drags are ignored, so the surface only ever travels toward its dismissal.
    func applyDragProgress(_ translation: CGFloat) {
        let distance = max(0, translation)
        let progress = min(1, distance / Constants.dragFadeDistance)
        let offset = CGAffineTransform(translationX: 0, y: distance)
        chipsContainerView.transform = offset
        mountedInputView?.transform = offset
        dimView.alpha = Self.dimmingAlpha * (1 - progress)
    }

    func springBackFromDrag() {
        UIView.animate(withDuration: Constants.springBackDuration,
                       delay: 0,
                       usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            self.chipsContainerView.transform = .identity
            self.mountedInputView?.transform = .identity
            self.dimView.alpha = Self.dimmingAlpha
        }
    }

    func requestDismiss() {
        delegate?.aiChatContextualFloatingInputViewControllerDidRequestDismiss(self)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AIChatContextualFloatingInputViewController: UIGestureRecognizerDelegate {

    /// Only downward, predominantly vertical drags start a dismissal, so horizontal scrolling inside
    /// the bar and text interactions are left alone.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dragToDismissRecognizer else { return true }
        let velocity = dragToDismissRecognizer.velocity(in: view)
        return velocity.y > 0 && velocity.y > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
