//
//  TabSwitcherSwipeUpTransition.swift
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
import Core
import WebKit

final class TabSwitcherSwipeUpGestureRecognizer: UIPanGestureRecognizer {

    /// Where the finger first touched, in window coordinates. The pan's own translation only starts once
    /// the finger has moved past the recognition threshold, which would make the card lag the finger.
    private(set) var touchDownLocation: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touchDownLocation == nil || state == .possible {
            touchDownLocation = touches.first?.location(in: nil)
        }
        super.touchesBegan(touches, with: event)
    }

    override func reset() {
        super.reset()
        touchDownLocation = nil
    }

    /// How far the finger has travelled up the screen since it touched down.
    var upwardTravel: CGFloat {
        guard let touchDownLocation else { return -translation(in: view).y }
        return touchDownLocation.y - location(in: nil).y
    }
}

/// Reports each touch-down without taking part in gesture recognition.
private final class TouchDownObserver: UIGestureRecognizer {

    private let onTouchDown: () -> Void

    init(onTouchDown: @escaping () -> Void) {
        self.onTouchDown = onTouchDown
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouchDown()
        state = .failed
    }
}

/// Presents the tab switcher by turning the page into a card that shrinks into its cell, either
/// following a vertical swipe on the bottom address bar or straight away from the tab switcher button.
///
/// Building the tab switcher is asynchronous and lays out a lot of views, so the card never waits for it:
/// it lives in an overlay on the window, heads for where the cell was last seen, and the tab switcher is
/// installed underneath it once the card is already moving.
final class TabSwitcherSwipeUpTransition: NSObject {

    weak var mainViewController: MainViewController?

    private(set) var isActive = false

    private let host = UIView()
    private let backdrop = UIView()
    private var cardView: TabSwitcherCardView?
    private var returnToolbarSnapshot: (tab: Tab, view: UIView)?
    private var chromeSnapshots: [UIView] = []

    private var screenBounds: CGRect = .zero
    private var isCommitted = false
    private var commitSpring = TabSwitcherTransition.Spring.swipeCommit
    private var cardTarget: CGRect?

    private var transitionContext: UIViewControllerContextTransitioning?
    private var isTabSwitcherInstalled = false
    private var commitAnimators: [UIViewPropertyAnimator] = []
    private weak var hiddenCell: UICollectionViewCell?
    private var isLanding = false
    private weak var landingTouchObserver: UIGestureRecognizer?
    private weak var landingTabSwitcherView: UIView?

    // MARK: - Entry points

    @objc func handlePan(_ gesture: TabSwitcherSwipeUpGestureRecognizer) {
        switch gesture.state {
        case .began:
            _ = begin()
        case .changed:
            guard isActive, !isCommitted else { return }
            cardView?.applyScreenPose(cardFrame: TabSwitcherSwipeUpGeometry.cardFrame(forTravel: gesture.upwardTravel, in: screenBounds))
        case .ended, .cancelled, .failed:
            guard isActive, !isCommitted else { return }
            let velocity = gesture.velocity(in: gesture.view).y
            if gesture.state == .ended, TabSwitcherSwipeUpGeometry.shouldCommit(travel: gesture.upwardTravel, velocity: velocity) {
                commit(with: .swipeCommit)
                requestTabSwitcherAfterFirstFrame()
            } else {
                cancel(velocity: velocity)
            }
        default:
            break
        }
    }

    /// Starts shrinking the page into the tab switcher immediately. The caller then requests the tab
    /// switcher as usual; this object animates its presentation unless it declined to begin, in which
    /// case the regular transition runs.
    func beginFromButton() {
        guard begin() else { return }
        commit(with: .present)
    }

    /// Whether the current page can shrink into the tab switcher as a card. AI tabs are drawn differently in
    /// their cell, and a web tab that hasn't loaded its web view has nothing to capture.
    var canBegin: Bool {
        guard !isActive,
              let mainViewController,
              TabSwitcherTransition.usesCardTransition(for: mainViewController),
              mainViewController.tabSwitcherController == nil,
              mainViewController.presentedViewController == nil,
              let tab = mainViewController.tabManager.currentTabsModel.currentTab else { return false }
        return !tab.isAITab && (tab.link == nil || mainViewController.currentTab?.webView != nil)
    }

    // MARK: - Card

    private func begin() -> Bool {
        finishLanding()
        guard canBegin,
              let mainViewController,
              let window = mainViewController.view.window,
              let coordinator = mainViewController.viewCoordinator else { return false }

        let isNewTabPage = mainViewController.currentTab?.tabModel.link == nil
        let contentView: UIView = isNewTabPage
            ? coordinator.contentContainer
            : mainViewController.currentTab?.webView ?? coordinator.contentContainer
        guard let content = contentView.snapshotView(afterScreenUpdates: false) else { return false }

        isActive = true
        screenBounds = window.bounds

        let theme = ThemeManager.shared.currentTheme
        host.frame = window.bounds
        host.isUserInteractionEnabled = false
        window.addSubview(host)

        backdrop.frame = host.bounds
        backdrop.backgroundColor = theme.backgroundColor
        backdrop.alpha = 1
        host.addSubview(backdrop)

        let cardView = TabSwitcherCardView(content: content,
                                           contentFrameInScreen: contentView.convert(contentView.bounds, to: window),
                                           contentCropTop: (contentView as? WKWebView)?.scrollView.contentInset.top ?? 0,
                                           screenBounds: screenBounds,
                                           screenCornerRadius: TabSwitcherTransition.screenCornerRadius(for: mainViewController.view),
                                           screenBackgroundColor: coordinator.statusBackground.backgroundColor ?? theme.backgroundColor)
        if isNewTabPage,
           let tab = mainViewController.tabManager.currentTabsModel.currentTab,
           let pageLogo = mainViewController.newTabPageViewController?.transitionLogo {
            cardView.installDax(circleInScreen: window.convert(pageLogo.circle, from: nil),
                                pageDax: contentView.resizableSnapshotView(from: contentView.convert(pageLogo.circle, from: nil),
                                                                           afterScreenUpdates: false,
                                                                           withCapInsets: .zero),
                                pageBackground: pageLogo.background,
                                cellImage: TabViewCell.logoImage(for: tab))
        }
        cardView.applyScreenPose(cardFrame: screenBounds)
        host.addSubview(cardView)
        self.cardView = cardView

        installChromeSnapshots(of: mainViewController, in: window)
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.chromeSnapshots.forEach {
                $0.alpha = 0
                $0.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            }
        }
        return true
    }

    /// Get the card moving before the tab switcher is built, so the release doesn't hitch.
    private func requestTabSwitcherAfterFirstFrame() {
        CATransaction.flush()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, self.isCommitted, self.transitionContext == nil else { return }
            self.mainViewController?.requestTabSwitcher()
        }
    }

    func takeReturnToolbarSnapshot() -> (tab: Tab, view: UIView)? {
        defer { returnToolbarSnapshot = nil }
        return returnToolbarSnapshot
    }

    /// The live toolbar is hidden under the tab switcher and can't be snapshotted reliably while it is (its glass
    /// samples the wrong backdrop), so keep a copy for the way back to the same tab. Taken as late as possible:
    /// at the start of the transition, the tab switcher button would still be drawn pressed.
    private func keepToolbarSnapshotForReturn(of mainViewController: MainViewController, in window: UIView) {
        returnToolbarSnapshot = nil
        guard let tab = mainViewController.tabManager.currentTabsModel.currentTab,
              let snapshot = toolbarSnapshot(of: mainViewController, in: window) else { return }
        returnToolbarSnapshot = (tab, snapshot)
    }

    private func toolbarSnapshot(of mainViewController: MainViewController, in window: UIView) -> UIView? {
        let toolbar: BrowserToolbarView = mainViewController.viewCoordinator.toolbar
        guard !toolbar.isHidden, toolbar.alpha > 0.01 else { return nil }
        let rect = toolbar.visibleCapsuleRect
        let snapshot = toolbar.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero)
        snapshot?.frame = toolbar.convert(rect, to: window)
        return snapshot
    }

    private func installChromeSnapshots(of mainViewController: MainViewController, in window: UIView) {
        guard let coordinator = mainViewController.viewCoordinator else { return }
        var snapshots = [toolbarSnapshot(of: mainViewController, in: window)].compactMap { $0 }

        let otherChrome: [UIView?] = [coordinator.navigationBarContainer, coordinator.unifiedToggleInputContainer]
        for view in otherChrome.compactMap({ $0 }) where !view.isHidden && view.alpha > 0.01 && view.window != nil {
            let frame = view.convert(view.bounds, to: window)
            guard frame.midY > window.bounds.midY,
                  let snapshot = view.snapshotView(afterScreenUpdates: false) else { continue }
            snapshot.frame = frame
            snapshots.append(snapshot)
        }

        snapshots.forEach(host.addSubview)
        chromeSnapshots = snapshots
    }

    // MARK: - Commit

    private func commit(with spring: TabSwitcherTransition.Spring) {
        guard let mainViewController,
              let tab = mainViewController.tabManager.currentTabsModel.currentTab,
              let row = mainViewController.tabManager.currentTabsModel.indexOf(tab: tab) else {
            cancel(velocity: 0)
            return
        }

        isCommitted = true
        commitSpring = spring
        let key = TabSwitcherCellFrameCache.Key(row: row,
                                                tabCount: mainViewController.tabManager.currentTabsModel.count,
                                                screenWidth: screenBounds.width)
        springCard(to: TabSwitcherCellFrameCache.frame(for: key, screenHeight: screenBounds.height))
        CATransaction.flush()

        // The presentation can be refused (another one is in flight, say); don't strand the card on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak cardView] in
            guard let self, let cardView, self.cardView === cardView, self.transitionContext == nil else { return }
            self.commitAnimators.forEach { $0.stopAnimation(true) }
            self.commitAnimators = []
            self.tearDownOverlay()
            self.reset()
        }
    }

    /// Calling this again while a spring is running retargets the card: UIKit adds the new spring on top.
    private func springCard(to cellFrame: CGRect) {
        guard let cardView else { return }
        cardTarget = cellFrame
        // Safari doesn't carry the finger's momentum into the release; the card eases off from rest.
        let animator = commitSpring.animator()
        animator.addAnimations {
            cardView.applyCellPose(cellFrame: cellFrame)
        }
        commitAnimators.append(animator)
        animator.addCompletion { _ in
            self.commitAnimators.removeAll { $0 === animator }
            self.finishLandingIfSettled()
        }
        animator.startAnimation()
    }

    private func installTabSwitcher() {
        guard isActive, !isTabSwitcherInstalled,
              let context = transitionContext,
              let tabSwitcher = context.viewController(forKey: .to) as? TabSwitcherViewController else { return }

        tabSwitcher.view.frame = context.finalFrame(for: tabSwitcher)
        tabSwitcher.view.alpha = 0
        context.containerView.insertSubview(tabSwitcher.view, aboveSubview: backdrop)
        tabSwitcher.prepareForPresentation()
        isTabSwitcherInstalled = true
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            tabSwitcher.view.alpha = 1
        }

        let collectionView = tabSwitcher.collectionView
        guard let tab = mainViewController?.tabManager.currentTabsModel.currentTab,
              let row = tabSwitcher.tabsModel.indexOf(tab: tab) else {
            completeCommit()
            return
        }
        let indexPath = IndexPath(row: row, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            completeCommit()
            return
        }

        let cellFrame = collectionView.convert(attributes.frame, to: host)
        TabSwitcherCellFrameCache.store(cellFrame, row: row, in: tabSwitcher)
        if cellFrame != cardTarget {
            springCard(to: cellFrame)
        }

        if let cell = collectionView.cellForItem(at: indexPath) as? TabViewCell {
            cardView?.installChrome(from: cell, isVisible: false)
            // Hiding the cell itself would stop it being hit-tested, so a tap during the landing would miss it.
            cell.contentView.alpha = 0
            hiddenCell = cell
            let response = commitSpring.response
            UIView.animate(withDuration: 0.2, delay: response * 0.35, options: [.curveEaseOut]) {
                self.cardView?.setChrome(visible: true)
            }
            UIView.animate(withDuration: response * 0.35, delay: response * 0.4, options: [.curveEaseInOut]) {
                self.cardView?.setFace(visible: true)
            }
        }
        completeCommit()
    }

    /// The presentation completes as soon as the tab switcher is in place so it takes taps straight away;
    /// the card finishes landing on top of it without intercepting touches.
    private func completeCommit() {
        if let mainViewController {
            mainViewController.viewCoordinator.toolbar.alpha = 0
            mainViewController.endTabSwitcherToolbarOwnership()
        }
        let context = transitionContext
        reset()
        isLanding = true
        landingTabSwitcherView = context?.viewController(forKey: .to)?.view
        observeTouchesWhileLanding(on: landingTabSwitcherView)
        context?.finishInteractiveTransition()
        context?.completeTransition(true)
        finishLandingIfSettled()
    }

    private func finishLandingIfSettled() {
        guard isLanding, commitAnimators.isEmpty else { return }
        finishLanding()
    }

    /// Removes the landing card, jumping straight to the real cell if it is still moving.
    func finishLanding() {
        guard isLanding else { return }
        isLanding = false
        let animators = commitAnimators
        commitAnimators = []
        animators.forEach { $0.stopAnimation(true) }
        if let landingTouchObserver {
            landingTouchObserver.view?.removeGestureRecognizer(landingTouchObserver)
        }
        // The backdrop is about to go, so the page would show through a tab switcher that is still fading in.
        landingTabSwitcherView?.layer.removeAllAnimations()
        landingTabSwitcherView?.alpha = 1
        tearDownOverlay()
        hiddenCell?.contentView.alpha = 1
        hiddenCell = nil
    }

    /// Touching the tab switcher (to scroll or pick a tab) shouldn't happen behind a card that is still moving.
    private func observeTouchesWhileLanding(on view: UIView?) {
        guard let view else { return }
        let observer = TouchDownObserver { [weak self] in
            self?.finishLanding()
        }
        view.addGestureRecognizer(observer)
        landingTouchObserver = observer
    }

    // MARK: - Cancel

    private func cancel(velocity: CGFloat) {
        guard let cardView else { return }
        let spring = TabSwitcherTransition.Spring.swipeCancel
        let distance = screenBounds.maxY - cardView.cardFrame.maxY
        let relativeVelocity = abs(distance) > 1 ? max(-5, min(20, velocity / distance)) : 0
        let animator = spring.animator(initialVelocity: CGVector(dx: relativeVelocity, dy: relativeVelocity))
        animator.addAnimations {
            cardView.applyScreenPose(cardFrame: self.screenBounds)
        }
        UIView.animate(withDuration: 0.2, delay: spring.response * 0.25, options: [.curveEaseOut]) {
            self.chromeSnapshots.forEach {
                $0.alpha = 1
                $0.transform = .identity
            }
        }
        animator.addCompletion { _ in
            self.tearDownOverlay()
            self.reset()
        }
        animator.startAnimation()
    }

    // MARK: - Teardown

    private func tearDownOverlay() {
        chromeSnapshots.forEach { $0.removeFromSuperview() }
        chromeSnapshots = []
        cardView?.removeFromSuperview()
        cardView = nil
        backdrop.removeFromSuperview()
        host.removeFromSuperview()
    }

    private func reset() {
        isActive = false
        isCommitted = false
        transitionContext = nil
        cardTarget = nil
        isTabSwitcherInstalled = false
    }
}

// MARK: - Presentation

extension TabSwitcherSwipeUpTransition: UIViewControllerAnimatedTransitioning, UIViewControllerInteractiveTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        commitSpring.settleDuration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        startInteractiveTransition(transitionContext)
    }

    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        guard isActive, isCommitted, transitionContext.viewController(forKey: .to) is TabSwitcherViewController else {
            transitionContext.cancelInteractiveTransition()
            transitionContext.completeTransition(false)
            return
        }

        self.transitionContext = transitionContext

        // The page must stay hidden behind the backdrop, but the tab switcher has to fade in above it,
        // so the backdrop moves under the (not yet installed) tab switcher while the card stays on top.
        let containerView = transitionContext.containerView
        backdrop.frame = containerView.convert(host.bounds, from: host)
        containerView.insertSubview(backdrop, at: 0)
        host.superview?.bringSubviewToFront(host)

        if let mainViewController {
            if let window = mainViewController.view.window {
                keepToolbarSnapshotForReturn(of: mainViewController, in: window)
            }
            mainViewController.beginTabSwitcherToolbarOwnership()
            mainViewController.viewCoordinator.toolbar.alpha = 0
        }
        DispatchQueue.main.async { self.installTabSwitcher() }
    }
}
