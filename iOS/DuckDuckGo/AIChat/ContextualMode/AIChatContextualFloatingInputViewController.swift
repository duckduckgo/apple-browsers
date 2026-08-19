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
import WebKit
import os.log

protocol AIChatContextualFloatingInputViewControllerDelegate: AnyObject {
    func aiChatContextualFloatingInputViewControllerDidRequestDismiss(_ viewController: AIChatContextualFloatingInputViewController)
}

/// The slice of the input host this surface drives: where to mount the bar, the card edges to align content
/// to, and the two levers the exit pulls — resigning the input, and pinning it clear of the keyboard.
@MainActor
protocol AIChatContextualFloatingInputHosting: AnyObject {
    var inputCardTopAnchor: NSLayoutYAxisAnchor { get }
    var inputCardLeadingAnchor: NSLayoutXAxisAnchor { get }
    var inputCardTrailingAnchor: NSLayoutXAxisAnchor { get }

    func mount(in parent: UIViewController) -> UIView
    func unmount(from parent: UIViewController)
    var isInputFirstResponder: Bool { get }

    func deactivateInput()
    func freezeInputPosition()
    func applyDictatedQuery(_ query: String)
}

extension AIChatContextualFloatingInputViewController: ContextualDictationPresenting {

    func applyDictatedQuery(_ query: String) {
        utiHost.applyDictatedQuery(query)
    }
}

/// Chip suggestions and the unified toggle input floating over the page, with no sheet chrome.
/// Dismissed by tapping the dimmed page, swiping the input down, or a VoiceOver escape.
@MainActor
final class AIChatContextualFloatingInputViewController: UIViewController {

    private enum Constants {
        /// Matches the design's system overlay scrim, `rgba(0, 0, 0, 0.2)`.
        static let dimmingAlpha: CGFloat = 0.2
        /// Drag distance that maps to a fully faded dim, and the point past which release dismisses.
        static let dragFadeDistance: CGFloat = 200
        static let dragDismissDistance: CGFloat = 80
        static let dismissVelocityThreshold: CGFloat = 600
        static let springBackDuration: TimeInterval = 0.3
        /// Only used until the keyboard has reported an animation of its own.
        static let assumedKeyboardSlideDuration: TimeInterval = 0.25
        /// Longer than this and the finger was resting or scrolling, not tapping.
        static let maximumTapDuration: CFTimeInterval = 0.4
        static let chipsFadeDuration: TimeInterval = 0.2
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

    /// Gates the keyboard-hide dismissal: a handover's own hide, or a hardware keyboard, is not this
    /// surface losing the keyboard it was sitting above.
    private var hasKeyboardAppeared = false

    /// Stays true for the rest of this surface's life — it is presented once and dismissed once.
    private var isDismissing = false
    private var hasResignedInput = false
    private var hasShownChips = false

    /// Where the keyboard goes while this surface leaves. The slide is the same either way; this only decides
    /// when the input resigns.
    private enum KeyboardHandling {
        /// Nothing else is claiming focus, so resigning now sends the keyboard down alongside the slide.
        case leavesWithSurface
        /// The dismissing tap is handing focus to the page, so the page's own focus decides the keyboard — an
        /// editable element keeps it exactly where it is. Resigning first is what makes it dip and return.
        case staysWithPage
    }

    private var keyboardHandling: KeyboardHandling = .leavesWithSurface

    /// The view the page-tap recognizer is installed on, so it can be detached even if this controller
    /// has already lost its parent.
    private weak var presenterView: UIView?

    /// The host's input view while mounted here. Owned by the host and reused across mounts, so any
    /// slide offset applied to it has to be cleared on the way out.
    private weak var mountedInputView: UIView?

    weak var delegate: AIChatContextualFloatingInputViewControllerDelegate?

    private let utiHost: AIChatContextualFloatingInputHosting
    private var isTransitioningSize = false
    let chipsViewController: AIChatContextualInputViewController

    /// Lets touches outside the input reach the page underneath, so it stays scrollable while the
    /// contextual chat is up. Only the chips, the bar and the close button claim anything.
    private final class PassthroughRootView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            return hit === self ? nil : hit
        }
    }

    /// Purely visual — the page underneath stays scrollable and tappable. Set to strength outright, since
    /// the entrance and exit fade the whole surface; only the drag thins the dim on its own.
    private lazy var dimView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = Constants.dimmingAlpha
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Fails on a held finger. Pausing mid-scroll is not a tap, and reading a page with a finger resting on
    /// it must not dismiss the surface — `allowableMovement` already covers the moving case, not this one.
    private final class BriefTapGestureRecognizer: UITapGestureRecognizer {
        private var touchStart: CFTimeInterval = 0

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            touchStart = CACurrentMediaTime()
            super.touchesBegan(touches, with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard CACurrentMediaTime() - touchStart <= Constants.maximumTapDuration else {
                state = .failed
                return
            }
            super.touchesEnded(touches, with: event)
        }
    }

    /// Installed on the presenter so any tap outside the surface dismisses it. A tap on the page is
    /// consumed with it — the user is leaving, not following a link — while chrome taps still act.
    private lazy var dismissOnPageTapRecognizer: UITapGestureRecognizer = {
        let recognizer = BriefTapGestureRecognizer(target: self, action: #selector(handlePageTap))
        recognizer.delegate = self
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

    init(utiHost: AIChatContextualFloatingInputHosting, chipsViewController: AIChatContextualInputViewController) {
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

    /// A rotation takes the keyboard down and puts it back up. That is the device turning, not the user
    /// leaving, so the surface sits through it — and it is this surface that pins the app to portrait,
    /// so leaving mid-rotation releases the pin and the rotation reverses.
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        isTransitioningSize = true
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.isTransitioningSize = false
        }
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
        // Settles at the pre-keyboard resting position, which the entrance then animates away from.
        // Without it the first layout pass lands inside that animation, and the bar rides in from nowhere.
        view.layoutIfNeeded()
        Logger.contextualUTI.info("Floating contextual input installed")
    }

    /// Fades in as it rides the keyboard guide up — an offset of its own would drift off that edge.
    /// Fades this view, not the bar: the bar is the host's, and activation flushes animations set on it.
    func playEntrance() {
        view.alpha = 0
        UIView.animate(withDuration: keyboardAnimation.duration,
                       delay: 0,
                       options: [keyboardAnimation.options, .beginFromCurrentState],
                       animations: {
            self.view.alpha = 1
            self.view.layoutIfNeeded()
        })
    }

    /// Chips arrive asynchronously with the page context, so this waits for the first batch with content
    /// rather than showing at install time. They sit above the input card, which is pinned to the keyboard
    /// guide, so they ride up with it rather than landing once it has stopped.
    func showChipsIfNeeded() {
        guard chipsViewController.startActionCount > 0 else { return }
        // Already entered once, so this is content returning after `clearChipsFadingOut` — fade it back
        // rather than re-running the one-shot entrance.
        guard !hasShownChips else {
            fadeChipsContainer(to: 1)
            return
        }
        hasShownChips = true
        chipsContainerView.alpha = 1
        chipsViewController.showStartActions()
    }

    /// Clears the chips only once they are invisible: removing them collapses the stack, and that
    /// collapse rides whatever layout animation the input is already running — which reads as the row
    /// sliding down behind the bar rather than leaving.
    func clearChipsFadingOut() {
        fadeChipsContainer(to: 0) { [weak self] in
            self?.chipsViewController.updateStartActions(suggestions: [], quickActions: [])
        }
    }

    private func fadeChipsContainer(to alpha: CGFloat, completion: (() -> Void)? = nil) {
        guard chipsContainerView.alpha != alpha else {
            completion?()
            return
        }
        UIView.animate(withDuration: Constants.chipsFadeDuration,
                       animations: { self.chipsContainerView.alpha = alpha },
                       // An interrupted fade has been overtaken by the next one, whose content is already
                       // in place — clearing it here would empty a row that is on its way back in.
                       completion: { finished in
            guard finished else { return }
            completion?()
        })
    }

    /// The entrance in reverse: settles back down to where it rose from, fading out as it goes. One alpha for
    /// the whole surface, dim included, so it never has to travel far enough to clear the screen.
    func dismiss(completion: @escaping () -> Void) {
        guard !isDismissing else { return }
        isDismissing = true

        // Measured before resigning, which collapses the keyboard guide it reads from. Never upwards: a long
        // drag can already have carried the surface past where this lands.
        let target = max(entranceTravel, contentTranslation)
        // Pinned first, so the slide is the only thing that moves the surface and nothing the keyboard does —
        // leaving, staying, or the page's field raising a taller one — can disturb it.
        utiHost.freezeInputPosition()

        if keyboardHandling == .leavesWithSurface {
            resignInput()
        }

        // Resigning above is what reports the dismissal's own duration and curve, so this reads them after it.
        UIView.animate(withDuration: keyboardAnimation.duration,
                       delay: 0,
                       options: [keyboardAnimation.options, .beginFromCurrentState],
                       animations: {
            self.translateContent(by: target)
            self.view.alpha = 0
        }, completion: { _ in
            // Already done when the keyboard left with the surface. Otherwise the page was offered the
            // keyboard and, if it declined, it is still ours to put away now the surface has gone.
            self.resignInput()
            completion()
        })
    }

    func remove() {
        // A removed surface has no business reacting to the keyboard it no longer sits above.
        NotificationCenter.default.removeObserver(self)
        // Lives on the presenter, so it outlives this controller unless detached explicitly. Detached
        // from the remembered view rather than `parent`, which is already nil if we were detached first.
        presenterView?.removeGestureRecognizer(dismissOnPageTapRecognizer)
        presenterView = nil
        // Scoped to this surface: a dismissal finishing after the next surface has mounted the shared input
        // must leave it alone. Clearing the slide's transform is the host's own business on the way out.
        utiHost.unmount(from: self)
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

    var hasShownChipsForTesting: Bool {
        hasShownChips
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
        // Hidden until dealt: the suggestions are configured as soon as they load, which is before the surface
        // has settled, and without this they simply appear at full strength wherever they land.
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


    @objc func handlePageTap() {
        keyboardHandling = .staysWithPage
        requestDismiss()
    }

    /// Resigning is what sends the keyboard down, and it happens once per dismissal — either as the slide
    /// starts or as it ends, never both.
    func resignInput() {
        guard !hasResignedInput else { return }
        hasResignedInput = true
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

    /// How far the surface rose from the bottom on the way in, and so how far it settles back down on the way
    /// out: the keyboard guide's travel, from where its top rests with the keyboard down to where it is now.
    var entranceTravel: CGFloat {
        max(0, view.safeAreaLayoutGuide.layoutFrame.maxY - view.keyboardLayoutGuide.layoutFrame.minY)
    }

    func observeKeyboardAnimation() {
        let names: [Notification.Name] = [UIResponder.keyboardWillShowNotification,
                                          UIResponder.keyboardWillChangeFrameNotification,
                                          UIResponder.keyboardWillHideNotification]
        for name in names {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleKeyboardNotification),
                                                   name: name,
                                                   object: nil)
        }
    }

    @objc func handleKeyboardNotification(_ notification: Notification) {
        if let animation = KeyboardAnimation(notification: notification) {
            keyboardAnimation = animation
        }

        if notification.name == UIResponder.keyboardWillShowNotification {
            hasKeyboardAppeared = true
        }

        // Something else took the keyboard this surface was sitting above — a long-press text selection,
        // or the page blurring its own field — so the surface goes too.
        guard notification.name == UIResponder.keyboardWillHideNotification,
              hasKeyboardAppeared,
              !isTransitioningSize,
              !isDismissing else { return }
        // Backgrounding and system interruptions take the keyboard too, and neither is the user leaving: the
        // surface and whatever has been typed into it should still be here on the way back.
        guard UIApplication.shared.applicationState == .active else { return }
        // This surface is the attachment picker's presenter, so its own picker takes the keyboard on the
        // way up — leaving now would tear down the input the picked attachment is meant to land in.
        guard presentedViewController == nil else { return }
        // Something else claiming the keyboard resigns our input with it. Still holding focus means the
        // keyboard is only churning — a rotation settling, or a hardware keyboard — so the surface stays.
        guard !utiHost.isInputFirstResponder else { return }
        requestDismiss()
    }

    /// Upward drags are ignored, so the surface only ever travels toward its dismissal.
    func applyDragProgress(_ translation: CGFloat) {
        let distance = max(0, translation)
        let progress = min(1, distance / Constants.dragFadeDistance)
        translateContent(by: distance)
        dimView.alpha = Constants.dimmingAlpha * (1 - progress)
    }

    func springBackFromDrag() {
        UIView.animate(withDuration: Constants.springBackDuration,
                       delay: 0,
                       usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            self.translateContent(by: 0)
            self.dimView.alpha = Constants.dimmingAlpha
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

    /// Taps on our own controls are the surface being used, not the user leaving it. Deferring to our
    /// hit test keeps one definition of which points this surface owns.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === dismissOnPageTapRecognizer else { return true }
        // Only the page is swallowed. Chrome acts on its own taps, and the address bar dismisses this
        // surface by taking focus, which never happens if the tap that focuses it is cancelled.
        gestureRecognizer.cancelsTouchesInView = isWithinWebContent(touch.view)
        return view.hitTest(touch.location(in: view), with: nil) == nil
    }

    /// The page's own tap waits for ours and loses, or the link it hit opens behind the dismissal. Taps
    /// only: a held finger never fails this recognizer, so a waiting long press would do nothing at all.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissOnPageTapRecognizer,
              !(otherGestureRecognizer is UIPanGestureRecognizer),
              !(otherGestureRecognizer is UILongPressGestureRecognizer) else { return false }
        return isWithinWebContent(otherGestureRecognizer.view)
    }

    private func isWithinWebContent(_ view: UIView?) -> Bool {
        var candidate = view
        while let current = candidate {
            if current is WKWebView { return true }
            candidate = current.superview
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
