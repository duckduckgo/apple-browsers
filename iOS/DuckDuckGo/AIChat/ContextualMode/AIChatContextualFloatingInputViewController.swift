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
        static let chipsRevealDuration: TimeInterval = 0.2
        /// Only used until the keyboard has reported an animation of its own.
        static let assumedKeyboardSlideDuration: TimeInterval = 0.25
        /// The share of the keyboard's animation over which it actually travels — its hide curve covers 96%
        /// of the distance in the first 60% and crawls the rest, and following that crawl reads as a stop.
        static let keyboardVisibleFraction: TimeInterval = 0.6
    }

    /// The keyboard's own animation, taken from its notifications: moving with the keyboard means running
    /// on its exact duration and curve, which is not one of the standard ones.
    private struct KeyboardAnimation {
        var duration: TimeInterval = Constants.assumedKeyboardSlideDuration
        var options: UIView.AnimationOptions = .curveEaseInOut

        init() {}

        init?(notification: Notification) {
            guard let info = notification.userInfo,
                  let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
                  let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
                  curve >= 0 else { return nil }
            self.duration = duration
            // The keyboard animates on a curve outside `UIView.AnimationCurve`, which only the raw
            // option bits can carry.
            self.options = UIView.AnimationOptions(rawValue: UInt(curve) << 16)
        }
    }

    private var keyboardAnimation = KeyboardAnimation()

    private var isDismissing = false
    private var hasPlayedChipsEntrance = false

    /// When the input resigns, which is what sends the keyboard down.
    private enum KeyboardRelease {
        /// Before the slide, so the keyboard travels with the surface. Nothing else is claiming focus.
        case beforeSlide
        /// After it, when the dismissing tap is also handing focus to the page: resigning first makes the
        /// keyboard dip out and come straight back, where waiting lets the page's own focus decide — an
        /// editable element keeps the keyboard exactly where it is and this becomes a no-op.
        case afterSlide
    }

    private var keyboardRelease: KeyboardRelease = .beforeSlide

    /// The view the page-tap recognizer is installed on, so it can be detached even if this controller
    /// has already lost its parent.
    private weak var presenterView: UIView?

    /// The host's input view while mounted here. Owned by the host and reused across mounts, so any
    /// slide offset applied to it has to be cleared on the way out.
    private weak var mountedInputView: UIView?

    weak var delegate: AIChatContextualFloatingInputViewControllerDelegate?

    private let utiHost: AIChatContextualUTIHost
    let chipsViewController: AIChatContextualInputViewController

    /// Lets touches outside the input reach the page underneath, so it stays scrollable while the
    /// contextual chat is up. Only the chips, the bar and the close button claim anything.
    private final class PassthroughRootView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            return hit === self ? nil : hit
        }
    }

    /// Purely visual — dimming the page must not stop it being scrolled or tapped.
    private lazy var dimView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Installed on the presenter so it sees taps that land on the page, and deliberately does not
    /// consume them: a tap dismisses this surface *and* still activates whatever it hit, so a link
    /// opens on the same tap. Taps on our own chips and bar are filtered out by the delegate.
    private lazy var dismissOnPageTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handlePageTap))
        recognizer.delegate = self
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        return recognizer
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

    /// Only reaches us where the surface claims touches — the chips, the bar and the close button — so
    /// a drag on the page scrolls the page instead.
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

    override func loadView() {
        view = PassthroughRootView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addGestureRecognizer(dragToDismissRecognizer)
        addDimView()
        addChipsContainer()
        observeKeyboardAnimation()
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
        presenterView = parent.view
        parent.view.addGestureRecognizer(dismissOnPageTapRecognizer)
        revealDim()
        revealChips()
        // Settles at the pre-keyboard resting position, which the entrance then animates away from.
        // Without it the first layout pass lands inside that animation, and the bar rides in from nowhere.
        view.layoutIfNeeded()
        Logger.contextualUTI.info("Floating contextual input installed")
    }

    /// Rides up glued to the keyboard's top edge. The bar's bottom is already pinned to the keyboard guide,
    /// so this only animates the layout on the keyboard's own terms — an offset of its own is what would
    /// let it drift off that edge. Called after activation, which re-applies the bar's render state.
    func playEntrance() {
        UIView.animate(withDuration: keyboardAnimation.duration,
                       delay: 0,
                       options: [keyboardAnimation.options, .beginFromCurrentState]) {
            self.view.layoutIfNeeded()
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

    /// Slides down off the bottom edge at one unchanging pace, taking the dim with it. The layout ride is
    /// deliberately not animated here: the keyboard guide animates itself alongside the keyboard, and a
    /// second animation of our own over the same positions is what breaks the pace.
    func dismiss(completion: @escaping () -> Void) {
        guard !isDismissing else { return }
        isDismissing = true

        // Measured before resigning, which collapses the keyboard guide it reads from. Never upwards: a
        // long drag can already have carried the surface past where this lands.
        let target = max(slideOutDistance, contentTranslation)

        releaseKeyboard(if: .beforeSlide)

        // Read after resigning, which is what reports the dismissal's own duration.
        UIView.animate(withDuration: keyboardAnimation.duration * Constants.keyboardVisibleFraction,
                       delay: 0,
                       options: [.curveLinear, .beginFromCurrentState],
                       animations: {
            self.translateContent(by: target)
            self.dimView.alpha = 0
        }, completion: { _ in
            self.releaseKeyboard(if: .afterSlide)
            completion()
        })
    }

    func remove() {
        // Lives on the presenter, so it outlives this controller unless detached explicitly. Detached
        // from the remembered view rather than `parent`, which is already nil if we were detached first.
        presenterView?.removeGestureRecognizer(dismissOnPageTapRecognizer)
        presenterView = nil
        utiHost.unmount()
        // Handed back clean: the host reuses this view, and a slide leaves a transform on it.
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
    /// Test-only: exercises a page tap without synthesising a touch.
    func simulatePageTapForTesting() {
        handlePageTap()
    }

    var hasPlayedChipsEntranceForTesting: Bool {
        hasPlayedChipsEntrance
    }
#endif
}

private extension AIChatContextualFloatingInputViewController {

    func addDimView() {
        view.addSubview(dimView)
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
            // Flush to the card: the chips controller already carries the design's 12pt gap in its
            // own bottom padding.
            chipsContainerView.bottomAnchor.constraint(equalTo: inputCardTop),
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


    @objc func handlePageTap() {
        keyboardRelease = .afterSlide
        requestDismiss()
    }

    private func releaseKeyboard(if timing: KeyboardRelease) {
        guard keyboardRelease == timing else { return }
        utiHost.deactivateInput()
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

    /// The chips and the bar move as one, so every slide — entrance, dismissal and drag — goes through
    /// here rather than transforming each of them in turn.
    func translateContent(by distance: CGFloat) {
        let offset = CGAffineTransform(translationX: 0, y: distance)
        chipsContainerView.transform = offset
        mountedInputView?.transform = offset
    }

    /// Both content views always carry the same slide offset.
    var contentTranslation: CGFloat {
        chipsContainerView.transform.ty
    }

    /// Where the top of the surface sits at rest — the chips once they are up, the bar otherwise. Read
    /// through any current offset, since a slide sets an absolute translation rather than adding to one.
    var restingContentTop: CGFloat {
        let top = min(chipsContainerView.frame.minY, mountedInputView?.frame.minY ?? .greatestFiniteMagnitude)
        return top - contentTranslation
    }

    /// How far the surface still has to travel to be gone. The keyboard guide carries the bar as far as
    /// the bottom safe area on its own, so this is only what that ride leaves over.
    var slideOutDistance: CGFloat {
        let clearingBottomEdge = view.bounds.maxY - restingContentTop
        let keyboardRide = view.safeAreaLayoutGuide.layoutFrame.maxY - view.keyboardLayoutGuide.layoutFrame.minY
        return max(0, clearingBottomEdge - max(0, keyboardRide))
    }

    func observeKeyboardAnimation() {
        let names: [Notification.Name] = [UIResponder.keyboardWillShowNotification,
                                          UIResponder.keyboardWillChangeFrameNotification,
                                          UIResponder.keyboardWillHideNotification]
        for name in names {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(recordKeyboardAnimation),
                                                   name: name,
                                                   object: nil)
        }
    }

    @objc func recordKeyboardAnimation(_ notification: Notification) {
        guard let animation = KeyboardAnimation(notification: notification) else { return }
        keyboardAnimation = animation
    }

    /// Upward drags are ignored, so the surface only ever travels toward its dismissal.
    func applyDragProgress(_ translation: CGFloat) {
        let distance = max(0, translation)
        let progress = min(1, distance / Constants.dragFadeDistance)
        translateContent(by: distance)
        dimView.alpha = Self.dimmingAlpha * (1 - progress)
    }

    func springBackFromDrag() {
        UIView.animate(withDuration: Constants.springBackDuration,
                       delay: 0,
                       usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            self.translateContent(by: 0)
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

    /// Taps on our own controls are the surface being used, not the user leaving it. Asking our own
    /// hit test keeps one definition of "does this surface own this point" — the passthrough root and
    /// the chips container already decide it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === dismissOnPageTapRecognizer else { return true }
        return view.hitTest(touch.location(in: view), with: nil) == nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
