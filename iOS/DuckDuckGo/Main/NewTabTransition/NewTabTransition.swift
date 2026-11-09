//
//  NewTabTransition.swift
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

/// Container transform for opening a new tab: the old screen (a snapshot) scales back and dims
/// while the live new page grows from a smaller card to full screen.
/// Chrome shared by every tab (headers, toolbars) grows in with the new page, so anything still animating
/// for the old tab shows on the new one. Such chrome can cover itself and restore via `NewTabOpeningObserving.afterNewTabOpens`;
/// see `AIChatTabChatHeaderView.coverRightPairWithStandIn` for a menu button closing into a new tab.
@MainActor
final class NewTabTransition: NewTabTransitioning {

    typealias Tuning = NewTabTransitionTuning

    private let window: UIWindow
    private let configuration: NewTabTransitionConfiguration
    private let entryPoint: Tuning.EntryPoint
    private let origin: Tuning.Origin
    private let motion: Tuning.Motion
    private let duration: TimeInterval
    private let tapLocation: CGPoint?

    /// Focus the new tab asks for waits here, so its keyboard lands with the tab.
    let keyboardGate = NewTabKeyboardGate()

    private let backdrop = UIView()
    private let oldPage = UIView()
    private let dimming = UIView()
    private let shadow = UIView()
    private weak var newPage: UIView?
    private weak var pageContent: UIView?
    private var viewsHiddenAboveNewPage: [UIView] = []
    private var completions: [() -> Void] = []
    private var keyboardMoment: Task<Void, Never>?
    private var animators: [UIViewPropertyAnimator] = []
    private var isFinished = false
    private var newPageClippedToBounds = false
    private var newPageCornerRadius: CGFloat = 0

    /// Freezes the screen under a snapshot of `oldScreen` so the caller can build the new tab out of sight.
    /// `oldScreen` is the view the new tab replaces, so menus and sheets above it stay out of the snapshot.
    /// `startDimming` is how dark the screen already looks, such as under a sheet's backdrop.
    /// `pageContent` is the new page's own content, whose animations are its own and keep running.
    static func begin(over oldScreen: UIView,
                      pageContent: UIView?,
                      dimmedBy startDimming: CGFloat = 0,
                      newPageRaisesKeyboard: Bool,
                      from entryPoint: Tuning.EntryPoint,
                      tapLocation: CGPoint?,
                      configuration: NewTabTransitionConfiguration) -> NewTabTransition? {
        guard configuration.isEnabled,
              UIDevice.current.userInterfaceIdiom == .phone,
              let window = (oldScreen as? UIWindow) ?? oldScreen.window,
              let screenSnapshot = oldScreen.snapshotView(afterScreenUpdates: false) else { return nil }
        let transition = NewTabTransition(window: window, entryPoint: entryPoint, tapLocation: tapLocation, configuration: configuration)
        transition.pageContent = pageContent
        transition.coverScreen(with: screenSnapshot, dimmedBy: startDimming)
        // Taps wait for the new tab, as they do during a system transition.
        window.isUserInteractionEnabled = false
        handleOldKeyboard(in: window, as: configuration.oldKeyboard.forNewPage(raisingKeyboard: newPageRaisesKeyboard))
        transition.acknowledgeTap()
        return transition
    }

    /// A new tab raises its own keyboard, so the old one leaves unless it should stay up for it.
    private static func handleOldKeyboard(in window: UIWindow, as oldKeyboard: Tuning.OldKeyboard) {
        switch oldKeyboard {
        case .leavesInstantly: UIView.performWithoutAnimation { _ = window.endEditing(true) }
        case .slidesDown: window.endEditing(true)
        case .staysUp: break
        }
    }

    private init(window: UIWindow, entryPoint: Tuning.EntryPoint, tapLocation: CGPoint?, configuration: NewTabTransitionConfiguration) {
        self.window = window
        self.configuration = configuration
        self.entryPoint = entryPoint
        self.tapLocation = tapLocation
        origin = configuration.origin(for: entryPoint)
        motion = configuration.motion(for: origin)
        duration = configuration.duration(of: motion)
    }

    /// Builds the new tab with `build`, then grows `page` from a card to full screen over the frozen old screen.
    /// Built without animation, so the new tab is already settled on the first frame.
    /// A keyboard the new tab asks for rises on the next turn, together with the grow.
    func revealNewPage(_ page: UIView, builtBy build: () -> Void) {
        UIView.performWithoutAnimation(build)
        page.layoutIfNeeded()
        moveOldPage(below: page)
        hideViews(above: page)
        finishLeftoverAnimations(in: page)
        rememberNewPage(page)
        // Reduce Motion asks for no scaling or sliding, so the new page only fades in.
        if UIAccessibility.isReduceMotionEnabled {
            crossfadeToNewPage(page)
        } else {
            growNewPage(page)
        }
    }

    private func growNewPage(_ page: UIView) {
        prepareNewPageToGrow(page)
        animateOldPageBack()
        animateNewPageIn(page)
        scheduleKeyboardMoment()
    }

    /// Part-way into the grow, so the keyboard's slide ends with the card's instead of after it.
    private func scheduleKeyboardMoment() {
        let delay = duration * Tuning.keyboardStartPortion
        keyboardMoment = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.keyboardGate.reachMoment()
        }
    }

    private func crossfadeToNewPage(_ page: UIView) {
        page.alpha = 0
        keyboardGate.reachMoment()
        let fade = UIViewPropertyAnimator(duration: Tuning.reduceMotionCrossfadeDuration, curve: .easeInOut) {
            page.alpha = 1
        }
        fade.addCompletion { _ in self.finish() }
        run(fade)
    }

    // MARK: - Layers

    private var screenBounds: CGRect { window.bounds }

    private var cornerRadius: CGFloat { configuration.roundsCorners ? configuration.cornerRadius : 0 }

    private var keepsOldScreenStill: Bool { entryPoint == .tabManager && configuration.tabManagerStaysStill }

    private func coverScreen(with screenSnapshot: UIView, dimmedBy startDimming: CGFloat) {
        backdrop.frame = screenBounds
        backdrop.backgroundColor = .black

        oldPage.frame = screenBounds
        oldPage.layer.cornerCurve = .continuous
        oldPage.layer.masksToBounds = true
        screenSnapshot.frame = oldPage.bounds
        oldPage.addSubview(screenSnapshot)
        dimming.frame = oldPage.bounds
        dimming.backgroundColor = .black
        dimming.alpha = startDimming
        oldPage.addSubview(dimming)

        window.addSubview(backdrop)
        window.addSubview(oldPage)
    }

    /// Starts a light dim and commits it now, so it plays while the main thread builds the new tab.
    /// A screen that already looks darker keeps its dim.
    private func acknowledgeTap() {
        let feedbackDimming = max(Tuning.tapFeedbackDimming, dimming.alpha)
        let dim = UIViewPropertyAnimator(duration: duration * Tuning.dimmingPortion, curve: .easeOut) { [dimming] in
            dimming.alpha = feedbackDimming
        }
        run(dim)
        CATransaction.flush()
    }

    private func moveOldPage(below page: UIView) {
        guard let container = page.superview else { return }
        oldPage.layer.cornerRadius = keepsOldScreenStill ? 0 : cornerRadius
        container.insertSubview(backdrop, belowSubview: page)
        container.insertSubview(oldPage, belowSubview: page)
        configureShadow(for: page)
        container.insertSubview(shadow, belowSubview: page)
    }

    private func rememberNewPage(_ page: UIView) {
        newPage = page
        newPageClippedToBounds = page.layer.masksToBounds
        newPageCornerRadius = page.layer.cornerRadius
    }

    private func prepareNewPageToGrow(_ page: UIView) {
        page.layer.cornerCurve = .continuous
        page.layer.masksToBounds = true
        page.layer.cornerRadius = cornerRadius / motion.startScale
        page.transform = newPageStartTransform
        page.alpha = configuration.fadesInNewPage ? 0 : 1
        shadow.transform = newPageStartTransform
    }

    private func configureShadow(for page: UIView) {
        shadow.frame = page.frame
        shadow.layer.shadowColor = UIColor.black.cgColor
        shadow.layer.shadowOpacity = Tuning.shadowOpacity
        shadow.layer.shadowRadius = Tuning.shadowRadius
        shadow.layer.shadowOffset = Tuning.shadowOffset
        shadow.layer.shadowPath = UIBezierPath(roundedRect: shadow.bounds, cornerRadius: cornerRadius).cgPath
        shadow.alpha = 0
    }

    /// Menus and screens still on their way out sit above the new page and would show over it.
    /// A screen presented over the browser shares its container, so every level up to the window is checked.
    /// At window level only the new page's screen stays: UIKit draws glass menu morphs below it, onto its buttons.
    private func hideViews(above page: UIView) {
        let transitionViews = [backdrop, oldPage, shadow]
        var view = page
        while let parent = view.superview, let index = parent.subviews.firstIndex(of: view) {
            let covering = parent === window ? parent.subviews.filter { $0 !== view } : Array(parent.subviews[(index + 1)...])
            viewsHiddenAboveNewPage += covering.filter { !$0.isHidden && !transitionViews.contains($0) }
            if parent === window { break }
            view = parent
        }
        viewsHiddenAboveNewPage.forEach { $0.isHidden = true }
    }

    /// Shared chrome can still be animating for the old page, like a glass button closing its menu.
    private func finishLeftoverAnimations(in page: UIView) {
        page.subviews.filter { $0 !== pageContent }.forEach(Self.removeAnimations(inTreeOf:))
    }

    private static func removeAnimations(inTreeOf view: UIView) {
        view.layer.removeAllAnimations()
        view.subviews.forEach(removeAnimations(inTreeOf:))
    }

    func addCompletion(_ completion: @escaping () -> Void) {
        completions.append(completion)
    }

    /// Ends the transition now, wherever it is, leaving the screen as it is after a finished one.
    func cancel() {
        guard !isFinished else { return }
        animators.filter { $0.state == .active }.forEach { $0.stopAnimation(true) }
        finish()
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        window.isUserInteractionEnabled = true
        [backdrop, oldPage, shadow].forEach { $0.removeFromSuperview() }
        viewsHiddenAboveNewPage.forEach { $0.isHidden = false }
        restoreNewPage()
        keyboardMoment?.cancel()
        keyboardGate.open()
        completions.forEach { $0() }
        releaseFinishedWork()
    }

    /// Animators and completions hold the transition, so letting go of them ends the cycle along with the snapshot.
    private func releaseFinishedWork() {
        animators.removeAll()
        completions.removeAll()
        viewsHiddenAboveNewPage.removeAll()
    }

    private func restoreNewPage() {
        guard let page = newPage else { return }
        page.transform = .identity
        page.alpha = 1
        page.layer.cornerRadius = newPageCornerRadius
        page.layer.masksToBounds = newPageClippedToBounds
    }

    // MARK: - Motion

    /// Kept so `cancel` can stop it wherever it is.
    private func run(_ animator: UIViewPropertyAnimator) {
        animators.append(animator)
        animator.startAnimation()
    }

    private func makeAnimator() -> UIViewPropertyAnimator {
        UIViewPropertyAnimator(duration: duration, timingParameters: timingParameters)
    }

    private var timingParameters: UITimingCurveProvider {
        guard configuration.usesSpring else {
            return UICubicTimingParameters(controlPoint1: Tuning.curveControlPoint1, controlPoint2: Tuning.curveControlPoint2)
        }
        if #available(iOS 17.0, *) {
            return UISpringTimingParameters(duration: duration, bounce: 0)
        }
        return UISpringTimingParameters(dampingRatio: 1)
    }

    private func animateOldPageBack() {
        pushOldPageBack()
        dimOldPage()
    }

    private func pushOldPageBack() {
        guard !keepsOldScreenStill else { return }
        let pushedBack = oldPageEndTransform
        let move = makeAnimator()
        move.addAnimations { [oldPage] in
            oldPage.transform = pushedBack
        }
        run(move)
    }

    private func dimOldPage() {
        let dim = UIViewPropertyAnimator(duration: duration, curve: .easeOut)
        dim.addAnimations { [dimming, motion] in
            UIView.animateKeyframes(withDuration: 0, delay: 0) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: Tuning.dimmingPortion) {
                    dimming.alpha = motion.dimming
                }
            }
        }
        run(dim)
    }

    private func animateNewPageIn(_ page: UIView) {
        let grow = makeAnimator()
        grow.addAnimations { [shadow, cornerRadius] in
            page.transform = .identity
            shadow.transform = .identity
            page.layer.cornerRadius = cornerRadius
            UIView.animateKeyframes(withDuration: 0, delay: 0) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: Tuning.fadeInPortion) {
                    page.alpha = 1
                    shadow.alpha = Tuning.shadowPeakAlpha
                }
                UIView.addKeyframe(withRelativeStartTime: Tuning.fadeInPortion, relativeDuration: 1 - Tuning.fadeInPortion) {
                    shadow.alpha = 0
                }
            }
        }
        // Strong on purpose: nothing else keeps the transition alive until it finishes.
        grow.addCompletion { _ in self.finish() }
        run(grow)
    }

    private var oldPageEndTransform: CGAffineTransform {
        let drift = origin == .belowCenter ? 0 : -motion.oldPageDrift * screenBounds.width
        return CGAffineTransform(translationX: drift, y: 0)
            .scaledBy(x: motion.oldPageScale, y: motion.oldPageScale)
    }

    private var newPageStartTransform: CGAffineTransform {
        let offset = newPageStartOffset
        return CGAffineTransform(translationX: offset.x, y: offset.y)
            .scaledBy(x: motion.startScale, y: motion.startScale)
    }

    private var newPageStartOffset: CGPoint {
        switch origin {
        case .rightOfCenter:
            return CGPoint(x: motion.offset * screenBounds.width, y: 0)
        case .belowCenter:
            return CGPoint(x: 0, y: motion.offset * screenBounds.height)
        case .tapLocation:
            guard let tapLocation else { return CGPoint(x: motion.offset * screenBounds.width, y: 0) }
            return offsetCenteringCard(on: tapLocation)
        }
    }

    /// Moves the card's center toward the tap, but keeps the card inside the screen.
    private func offsetCenteringCard(on point: CGPoint) -> CGPoint {
        let maxX = screenBounds.width * (1 - motion.startScale) / 2
        let maxY = screenBounds.height * (1 - motion.startScale) / 2
        let dx = point.x - screenBounds.midX
        let dy = point.y - screenBounds.midY
        return CGPoint(x: min(max(dx, -maxX), maxX), y: min(max(dy, -maxY), maxY))
    }
}
