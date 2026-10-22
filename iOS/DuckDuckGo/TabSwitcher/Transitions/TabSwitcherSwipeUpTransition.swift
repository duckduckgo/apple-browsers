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

    var horizontalTravel: CGFloat {
        guard let touchDownLocation else { return translation(in: view).x }
        return location(in: nil).x - touchDownLocation.x
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
/// following a swipe on the bottom address bar or straight away from the tab switcher button.
///
/// Building the tab switcher is asynchronous and lays out a lot of views, so the card never waits for it:
/// it lives in an overlay on the window, heads for where the cell was last seen, and the tab switcher is
/// installed underneath it once the card is already moving.
final class TabSwitcherSwipeUpTransition: NSObject {

    weak var mainViewController: MainViewController?

    private(set) var isActive = false

    /// Whether the next presentation of the tab switcher belongs to this transition. A swipe that is
    /// springing back isn't one, so the tab switcher button still works meanwhile.
    var presentsTabSwitcher: Bool { isActive && isCommitted }

    private let host = UIView()
    private let backdrop = UIView()
    private let previewContainer = UIView()
    private let previewBlur = UIVisualEffectView()
    private let previewCover = UIView()
    private var blurAnimator: UIViewPropertyAnimator?
    private var previewTask: Task<TabSwitcherViewController?, Never>?
    private var previewedTabSwitcher: TabSwitcherViewController?
    private var revealProgress: CGFloat = 0
    private var cardView: TabSwitcherCardView?
    private var chromeSnapshots: [UIView] = []
    @MainActor private struct NeighboringTab {
        let tab: Tab
        let offset: Int
        let card: TabSwitcherCardView
        let preview: UIImageView
    }
    private var neighboringTabs: [NeighboringTab] = []
    private var isReturning = false

    private var screenBounds: CGRect = .zero
    private var isCommitted = false
    private var commitSpring = TabSwitcherTransition.Spring.swipeCommit
    private var cardTarget: CGRect?

    private var transitionContext: UIViewControllerContextTransitioning?
    private var commitAnimators: [UIViewPropertyAnimator] = []
    private weak var hiddenCell: UICollectionViewCell?
    private var isLanding = false
    private weak var landingTouchObserver: UIGestureRecognizer?
    private weak var landingTabSwitcherView: UIView?

    // MARK: - Entry points

    @objc func handlePan(_ gesture: TabSwitcherSwipeUpGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard begin() else { return }
            if let window = mainViewController?.view.window {
                installNeighboringTabs(in: window)
            }
            updateDrag(gesture)
            prepareTabSwitcherPreview()
        case .changed:
            guard isActive, !isCommitted, !isReturning else { return }
            updateDrag(gesture)
        case .ended, .cancelled, .failed:
            guard isActive, !isCommitted, !isReturning else { return }
            let velocity = gesture.velocity(in: gesture.view).y
            let offset = TabSwitcherSwipeUpGeometry.selectedTabOffset(horizontalTravel: gesture.horizontalTravel,
                                                                     screenWidth: screenBounds.width)
            if gesture.state == .ended, offset != 0 {
                cancel(velocity: velocity, returningTo: neighboringTab(atOffset: offset))
            } else if gesture.state == .ended, TabSwitcherSwipeUpGeometry.shouldCommit(travel: gesture.upwardTravel, velocity: velocity) {
                commit(with: .swipeCommit)
                requestTabSwitcherAfterFirstFrame()
            } else {
                cancel(velocity: velocity)
            }
        default:
            break
        }
    }

    private func updateDrag(_ gesture: TabSwitcherSwipeUpGestureRecognizer) {
        let frame = TabSwitcherSwipeUpGeometry.cardFrame(forTravel: gesture.upwardTravel,
                                                         horizontalTravel: gesture.horizontalTravel,
                                                         in: screenBounds)
        cardView?.applyScreenPose(cardFrame: frame)
        for neighbor in neighboringTabs {
            let frame = TabSwitcherSwipeUpGeometry.neighborCardFrame(forTravel: gesture.upwardTravel,
                                                                    horizontalTravel: gesture.horizontalTravel,
                                                                    offset: neighbor.offset,
                                                                    in: screenBounds)
            let tilt = UIAccessibility.isReduceMotionEnabled ? 0 : TabSwitcherSwipeUpGeometry.neighborTilt(forTravel: gesture.upwardTravel,
                                                                                                          screenHeight: screenBounds.height,
                                                                                                          offset: neighbor.offset)
            neighbor.card.applyScreenPose(cardFrame: frame, tilt: tilt)
        }
        setChromeVisibility(TabSwitcherSwipeUpGeometry.chromeVisibility(forTravel: gesture.upwardTravel, screenHeight: screenBounds.height))
        setRevealProgress(TabSwitcherSwipeUpGeometry.revealProgress(forTravel: gesture.upwardTravel, screenHeight: screenBounds.height))
    }

    private func neighboringTab(atOffset offset: Int) -> NeighboringTab? {
        return neighboringTabs.first {
            $0.offset == offset && mainViewController?.tabManager.currentTabsModel.indexOf(tab: $0.tab) != nil
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

        previewContainer.frame = host.bounds
        previewContainer.accessibilityElementsHidden = true
        host.addSubview(previewContainer)
        previewBlur.frame = host.bounds
        host.addSubview(previewBlur)
        previewCover.frame = host.bounds
        previewCover.backgroundColor = theme.backgroundColor
        host.addSubview(previewCover)
        setRevealProgress(0)

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
        return true
    }

    private func installNeighboringTabs(in window: UIWindow) {
        guard let mainViewController, let cardView, mainViewController.swipeTabsCoordinator != nil,
              let index = mainViewController.tabManager.currentTabsModel.currentIndex else { return }
        let model = mainViewController.tabManager.currentTabsModel
        let theme = ThemeManager.shared.currentTheme
        for offset in [-1, 1] {
            guard model.tabs.indices.contains(index + offset), let tab = model.get(tabAt: index + offset) else { continue }
            let preview = mainViewController.previewsSource.preview(for: tab)
            // shortcut: uncaptured tabs show their logo; use live previews if these placeholders become distracting.
            let imageView = UIImageView(image: preview ?? TabViewCell.logoImage(for: tab))
            imageView.contentMode = preview == nil ? .center : .scaleAspectFill
            imageView.clipsToBounds = true
            var contentFrame = screenBounds
            if tab.link != nil, !tab.isAITab, let webView = mainViewController.currentTab?.webView {
                contentFrame = webView.convert(webView.bounds, to: window)
                let cropTop = webView.scrollView.contentInset.top
                contentFrame.origin.y += cropTop
                contentFrame.size.height = max(0, contentFrame.height - cropTop)
            }
            let card = TabSwitcherCardView(content: imageView,
                                           contentFrameInScreen: contentFrame,
                                           contentCropTop: 0,
                                           screenBounds: screenBounds,
                                           screenCornerRadius: TabSwitcherTransition.screenCornerRadius(for: mainViewController.view),
                                           screenBackgroundColor: theme.backgroundColor)
            card.applyScreenPose(cardFrame: TabSwitcherSwipeUpGeometry.neighborCardFrame(forTravel: 0,
                                                                                       horizontalTravel: 0,
                                                                                       offset: offset,
                                                                                       in: screenBounds))
            host.insertSubview(card, belowSubview: cardView)
            let neighbor = NeighboringTab(tab: tab, offset: offset, card: card, preview: imageView)
            neighboringTabs.append(neighbor)
            if let webView = mainViewController.tabManager.controller(for: tab)?.webView {
                refreshNeighborPreview(neighbor, from: webView)
            }
        }
    }

    private func refreshNeighborPreview(_ neighbor: NeighboringTab, from webView: WKWebView, completion: (() -> Void)? = nil) {
        guard let rect = WebViewPreviewSnapshotGeometry.visibleRect(webViewBounds: webView.bounds,
                                                                   contentInset: webView.scrollView.contentInset,
                                                                   capturesFullBounds: true) else {
            if let completion {
                TabSwitcherTransition.whenRendered(webView, completion)
            }
            return
        }
        let isReturning = self.isReturning
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        // Grid previews are capped at a column's width; the returning card needs native screen detail.
        configuration.snapshotWidth = NSNumber(value: WebViewPreviewSnapshotGeometry.snapshotWidth(for: rect,
                                                                                                   windowSize: screenBounds.size,
                                                                                                   isFullScreen: true))
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            if let self, self.isReturning == isReturning,
               self.neighboringTabs.contains(where: { $0.card === neighbor.card }), let image {
                neighbor.preview.image = image
                neighbor.preview.contentMode = .scaleAspectFill
            }
            completion?()
        }
    }

    private func setChromeVisibility(_ visibility: CGFloat) {
        let scale = 0.94 + 0.06 * visibility
        chromeSnapshots.forEach {
            $0.alpha = visibility
            $0.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    // MARK: - Destination preview

    private func prepareTabSwitcherPreview() {
        guard let mainViewController, let cardView else { return }
        previewTask = Task { @MainActor [weak self, weak mainViewController, weak cardView] in
            guard let controller = await mainViewController?.makeTabSwitcher(),
                  !Task.isCancelled,
                  let self, let cardView, self.cardView === cardView, self.isActive else { return nil }

            controller.view.frame = self.previewContainer.bounds
            self.previewContainer.addSubview(controller.view)
            controller.prepareForPresentation()
            self.positionCurrentCell(in: controller)
            self.previewedTabSwitcher = controller

            if !UIAccessibility.isReduceTransparencyEnabled, !self.isCommitted {
                let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
                    self.previewBlur.effect = UIBlurEffect(style: .systemMaterial)
                }
                animator.pausesOnCompletion = true
                animator.startAnimation()
                animator.pauseAnimation()
                self.blurAnimator = animator
            }
            self.setRevealProgress(self.revealProgress)
            return controller
        }
    }

    /// Reuse the destination being revealed by the swipe when its presentation is requested.
    var tabSwitcherPreparation: Task<TabSwitcherViewController?, Never>? {
        presentsTabSwitcher ? previewTask : nil
    }

    private func setRevealProgress(_ progress: CGFloat) {
        revealProgress = progress
        previewCover.alpha = 1 - progress
        blurAnimator?.fractionComplete = TabSwitcherSwipeUpGeometry.blurProgress(forRevealProgress: progress, isCommitted: isCommitted)
    }

    /// Use the same scroll position for the preview and the final destination.
    @discardableResult
    private func positionCurrentCell(in tabSwitcher: TabSwitcherViewController) -> CGRect? {
        let collectionView = tabSwitcher.collectionView
        guard let tab = mainViewController?.tabManager.currentTabsModel.currentTab,
              let row = tabSwitcher.tabsModel.indexOf(tab: tab) else { return nil }
        let indexPath = IndexPath(row: row, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }

        let cellFrame = collectionView.convert(attributes.frame, to: host)
        TabSwitcherCellFrameCache.store(cellFrame, row: row, in: tabSwitcher)
        if let cell = collectionView.cellForItem(at: indexPath) {
            hiddenCell?.contentView.alpha = 1
            // Hiding the cell itself would stop taps from reaching it while the card lands.
            cell.contentView.alpha = 0
            hiddenCell = cell
        }
        return cellFrame
    }

    /// Get the card moving before the tab switcher is built, so the release doesn't hitch.
    private func requestTabSwitcherAfterFirstFrame() {
        CATransaction.flush()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, self.isCommitted, self.transitionContext == nil else { return }
            self.mainViewController?.requestTabSwitcher()
        }
    }

    private func installChromeSnapshots(of mainViewController: MainViewController, in window: UIView) {
        let snapshots = mainViewController.tabSwitcherChromeSnapshots(in: window)
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
        // A quick flick can release while the covered overview still has its strongest blur.
        blurAnimator?.fractionComplete = TabSwitcherSwipeUpGeometry.blurProgress(forRevealProgress: revealProgress, isCommitted: true)
        revealProgress = 1
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.setChromeVisibility(0)
            self.neighboringTabs.forEach { $0.card.alpha = 0 }
        }
        springCard(to: TabSwitcherCellFrameCache.frame(forRow: row, in: screenBounds, isGrid: cardView?.cellStyle != .list))
        if cardView?.cellStyle == .list {
            UIView.animate(withDuration: spring.response * 0.45, delay: spring.response * 0.1, options: [.curveEaseIn]) {
                self.cardView?.setPage(visible: false)
            }
        }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            self.previewCover.alpha = 0
        }
        blurAnimator?.isReversed = true
        blurAnimator?.continueAnimation(withTimingParameters: nil, durationFactor: 0.15)
        CATransaction.flush()

        // The presentation can be refused (another one is in flight, say); don't strand the card on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak cardView] in
            guard let self, let cardView, self.cardView === cardView, self.isActive, self.transitionContext == nil else { return }
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
        guard isActive,
              let context = transitionContext,
              let tabSwitcher = context.viewController(forKey: .to) as? TabSwitcherViewController else { return }

        tabSwitcher.view.frame = context.finalFrame(for: tabSwitcher)
        tabSwitcher.view.alpha = tabSwitcher === previewedTabSwitcher ? 1 : 0
        context.containerView.insertSubview(tabSwitcher.view, aboveSubview: backdrop)
        tabSwitcher.prepareForPresentation()
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
        guard let cellFrame = positionCurrentCell(in: tabSwitcher) else {
            completeCommit()
            return
        }

        if cellFrame != cardTarget {
            springCard(to: cellFrame)
        }

        if let cell = collectionView.cellForItem(at: indexPath) as? TabViewCell {
            cardView?.installChrome(from: cell, isVisible: false)
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

    private func cancel(velocity: CGFloat, returningTo neighbor: NeighboringTab? = nil) {
        isReturning = true
        previewTask?.cancel()
        previewTask = nil
        guard let cardView else { return }
        let spring = TabSwitcherTransition.Spring.swipeCancel
        let distance = screenBounds.maxY - cardView.cardFrame.maxY
        let relativeVelocity = abs(distance) > 1 ? max(-5, min(20, velocity / distance)) : 0
        let animator = spring.animator(initialVelocity: CGVector(dx: relativeVelocity, dy: relativeVelocity))
        let offset = neighbor?.offset ?? 0
        animator.addAnimations {
            cardView.applyScreenPose(cardFrame: self.screenBounds.offsetBy(dx: -CGFloat(offset) * (self.screenBounds.width + 20), dy: 0))
            for entry in self.neighboringTabs {
                let frame = entry.offset == offset ? self.screenBounds : TabSwitcherSwipeUpGeometry.neighborCardFrame(
                    forTravel: 0,
                    horizontalTravel: -CGFloat(offset) * (self.screenBounds.width + 20),
                    offset: entry.offset,
                    in: self.screenBounds)
                entry.card.applyScreenPose(cardFrame: frame)
            }
            self.previewCover.alpha = 1
        }
        var hasSettled = false
        var isPageReady = neighbor == nil
        let returningCard = neighbor?.card ?? cardView
        let finish = {
            guard hasSettled, isPageReady else { return }
            [self.backdrop, self.previewContainer, self.previewBlur, self.previewCover].forEach { $0.removeFromSuperview() }
            UIView.animate(withDuration: 0.1, animations: {
                returningCard.alpha = 0
            }, completion: { _ in
                self.tearDownOverlay()
                self.reset()
                self.mainViewController?.revealFloatingToolbarAfterTabSwitcherTransition(isAlreadyShowing: true)
            })
        }
        animator.addCompletion { _ in
            hasSettled = true
            finish()
        }
        animator.startAnimation()
        if let mainViewController {
            mainViewController.beginTabSwitcherToolbarOwnership()
            if let neighbor, let swipeTabs = mainViewController.swipeTabsCoordinator {
                swipeTabs.onSwipeStarted()
                swipeTabs.selectTab(neighbor.tab)
            }
            mainViewController.view.layoutIfNeeded()
            revealLiveReturnChrome(of: mainViewController, response: spring.response)
            if let neighbor, let webView = mainViewController.currentTab?.webView, neighbor.tab.link != nil {
                let pageReady = {
                    guard !isPageReady else { return }
                    isPageReady = true
                    finish()
                }
                refreshNeighborPreview(neighbor, from: webView) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: pageReady)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: pageReady)
            } else {
                if let neighbor {
                    let content: UIView = mainViewController.viewCoordinator.contentContainer
                    if !content.bounds.isEmpty {
                        var didDraw = false
                        let image = UIGraphicsImageRenderer(bounds: content.bounds).image { _ in
                            didDraw = content.drawHierarchy(in: content.bounds, afterScreenUpdates: true)
                        }
                        if didDraw {
                            neighbor.preview.image = image
                            neighbor.preview.contentMode = .scaleAspectFill
                        }
                    }
                }
                isPageReady = true
            }
        } else {
            isPageReady = true
        }
    }

    /// Keep glass live: a copied toolbar can retain the departing page's blurred content.
    private func revealLiveReturnChrome(of mainViewController: MainViewController, response: TimeInterval) {
        let coordinator: MainViewCoordinator = mainViewController.viewCoordinator
        let stage = coordinator.superview
        let toolbar: BrowserToolbarView = coordinator.toolbar
        let bars: [UIView] = [toolbar, coordinator.navigationBarContainer, coordinator.aiChatTabChatHeaderContainer].filter {
            $0.superview === stage && !$0.isHidden && ($0 === toolbar || $0.alpha > 0.01)
        }
        let visibility = chromeSnapshots.first?.alpha ?? 0
        let transform = chromeSnapshots.first?.transform ?? CGAffineTransform(scaleX: 0.94, y: 0.94)
        chromeSnapshots.forEach { $0.removeFromSuperview() }
        chromeSnapshots = []
        guard let lowestBar = bars.min(by: { (stage.subviews.firstIndex(of: $0) ?? 0) < (stage.subviews.firstIndex(of: $1) ?? 0) }) else { return }
        host.frame = stage.convert(host.bounds, from: host)
        stage.insertSubview(host, belowSubview: lowestBar)
        for bar in bars {
            bar.alpha = visibility
            bar.transform = transform
        }
        UIView.animate(withDuration: 0.2, delay: response * 0.25, options: [.curveEaseOut]) {
            for bar in bars {
                bar.alpha = 1
                bar.transform = .identity
            }
        }
    }

    // MARK: - Teardown

    private func tearDownOverlay() {
        previewTask?.cancel()
        previewTask = nil
        if blurAnimator?.state == .active {
            blurAnimator?.stopAnimation(true)
        }
        blurAnimator = nil
        previewBlur.effect = nil
        previewCover.layer.removeAllAnimations()
        previewContainer.subviews.forEach { $0.removeFromSuperview() }
        previewedTabSwitcher = nil
        hiddenCell?.contentView.alpha = 1
        hiddenCell = nil
        previewContainer.removeFromSuperview()
        previewBlur.removeFromSuperview()
        previewCover.removeFromSuperview()
        neighboringTabs.forEach { $0.card.removeFromSuperview() }
        neighboringTabs = []
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
        isReturning = false
        transitionContext = nil
        cardTarget = nil
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
            mainViewController.beginTabSwitcherToolbarOwnership()
            mainViewController.viewCoordinator.toolbar.alpha = 0
        }
        DispatchQueue.main.async { self.installTabSwitcher() }
    }
}
