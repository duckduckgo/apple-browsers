//
//  TabSwitcherTransition.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit

class TabSwitcherTransition: NSObject, UIViewControllerAnimatedTransitioning {
    
    struct Constants {
        static let duration = 0.20
        static let floatingDuration = 0.28
        static let collapsedToolbarScale: CGFloat = 0.7
        /// Appear animation for the live floating toolbar, once the destination page is on screen.
        static let floatingToolbarRevealDuration: TimeInterval = 0.22
        static let floatingToolbarRevealScale: CGFloat = 0.94
        static let displayCornerRadius: CGFloat = 55
    }

    /// The toolbar as it looked when the tab switcher opened, for the way back to that tab.
    var returningToolbarSnapshot: (tab: Tab, view: UIView)?

    /// Spring curves measured frame-by-frame from Safari's tab overview on iOS 26.
    struct Spring {
        let response: TimeInterval
        let dampingRatio: CGFloat

        static let present = Spring(response: 0.38, dampingRatio: 0.9)
        static let dismiss = Spring(response: 0.42, dampingRatio: 0.9)
        static let swipeCommit = Spring(response: 0.51, dampingRatio: 0.825)
        static let swipeCancel = Spring(response: 0.42, dampingRatio: 0.86)

        /// Time for the spring to visually settle, used where UIKit needs a fixed duration.
        var settleDuration: TimeInterval { response * 1.25 }

        func animator(initialVelocity: CGVector = .zero) -> UIViewPropertyAnimator {
            let angularFrequency = 2 * .pi / response
            let timing = UISpringTimingParameters(mass: 1,
                                                  stiffness: angularFrequency * angularFrequency,
                                                  damping: 2 * dampingRatio * angularFrequency,
                                                  initialVelocity: initialVelocity)
            return UIViewPropertyAnimator(duration: settleDuration, timingParameters: timing)
        }

        /// Runs keyframe animations with this spring as their overall timing.
        func animateKeyframes(animations: @escaping () -> Void, completion: @escaping (UIViewAnimatingPosition) -> Void) {
            let animator = animator()
            animator.addAnimations {
                UIView.animateKeyframes(withDuration: 0, delay: 0, options: .calculationModeLinear, animations: animations)
            }
            animator.addCompletion(completion)
            animator.startAnimation()
        }
    }

    /// Whether the page travels between the screen and its cell as a card, like Safari's tab overview.
    static func usesCardTransition(for mainViewController: MainViewController) -> Bool {
        mainViewController.isFloatingUIEnabled
            && mainViewController.appSettings.currentAddressBarPosition.isBottom
            && DefaultTabSwitcherSettings().isGridViewEnabled
    }

    /// Approximates the physical display corner so a full-screen card is indistinguishable from the screen.
    static func screenCornerRadius(for view: UIView) -> CGFloat {
        let bottomInset = view.window?.safeAreaInsets.bottom ?? 0
        return bottomInset > 0 ? Constants.displayCornerRadius : 0
    }

    static func duration(isFloatingUIEnabled: Bool) -> TimeInterval {
        isFloatingUIEnabled ? Constants.floatingDuration : Constants.duration
    }

    static func toolbarTransform(scale: CGFloat, for view: UIView) -> CGAffineTransform {
        let heightLost = view.bounds.height * (1 - scale) / 2
        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: 0, y: heightLost))
    }

    static func collapsedToolbarTransform(for view: UIView) -> CGAffineTransform {
        toolbarTransform(scale: Constants.collapsedToolbarScale, for: view)
    }
    
    // Used to hide contents of the 'from' VC when animating.
    let solidBackground = UIView()
    // Draws outside the clipped transition card so depth can participate in the morph.
    let cardShadow = UIView()
    let cardBorder = UIView()
    // Container for the image, will clip subviews like tab switcher cell does.
    let imageContainer = UIView()
    // Image to display as a preview.
    let imageView = UIImageView()
    private(set) var gridChromeSnapshot: UIView?
    private weak var listCellBorder: UIView?
    private var listCellBorderWasHidden = false
    
    let tabSwitcherViewController: TabSwitcherViewController
    
    init(tabSwitcherViewController: TabSwitcherViewController) {
        self.tabSwitcherViewController = tabSwitcherViewController
    }
    
    func prepareSubviews(using transitionContext: UIViewControllerContextTransitioning) {
        
        transitionContext.containerView.addSubview(solidBackground)

        cardShadow.backgroundColor = UIColor(designSystemColor: .surfaceTertiary)
        cardShadow.layer.cornerCurve = .continuous
        cardShadow.layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        cardShadow.layer.shadowRadius = TabViewCell.Constants.shadowRadius
        cardShadow.layer.shadowOffset = TabViewCell.Constants.shadowOffset
        transitionContext.containerView.addSubview(cardShadow)

        imageContainer.clipsToBounds = true
        imageContainer.layer.cornerCurve = .continuous
        imageContainer.addSubview(imageView)
        transitionContext.containerView.addSubview(imageContainer)
    }

    func setCardFrame(_ frame: CGRect, cornerRadius: CGFloat, shadowOpacity: Float) {
        cardShadow.frame = frame
        cardShadow.layer.cornerRadius = cornerRadius
        cardShadow.layer.shadowOpacity = shadowOpacity
        // No shadowPath: UIView animations don't interpolate it, so it would jump to the destination frame.
        cardShadow.layer.shadowPath = nil

        imageContainer.frame = frame
        imageContainer.layer.cornerRadius = cornerRadius

        if cardBorder.superview != nil {
            let borderOutset = TabViewCell.Constants.borderOutset / 2
            cardBorder.frame = frame.insetBy(dx: -borderOutset, dy: -borderOutset)
            cardBorder.layer.cornerRadius = cornerRadius == 0 ? 0 : TabViewCell.Constants.borderRadius
        }
    }

    func prepareGridChromeSnapshot(for cell: TabViewGridCell, initiallyVisible: Bool) {
        cell.layoutIfNeeded()
        let headerFrame = CGRect(x: 0,
                                 y: 0,
                                 width: cell.bounds.width,
                                 height: TabViewGridCell.Constants.headerHeight)
        guard let snapshot = cell.resizableSnapshotView(from: headerFrame,
                                                        afterScreenUpdates: true,
                                                        withCapInsets: .zero) else {
            return
        }

        snapshot.frame = CGRect(x: imageContainer.bounds.minX,
                                y: imageContainer.bounds.minY,
                                width: imageContainer.bounds.width,
                                height: TabViewGridCell.Constants.headerHeight)
        snapshot.autoresizingMask = [.flexibleWidth]
        imageContainer.addSubview(snapshot)
        gridChromeSnapshot = snapshot
        applyGridChromePose(isVisible: initiallyVisible, in: imageContainer.bounds)
    }

    func applyGridChromePose(isVisible: Bool, in _: CGRect) {
        gridChromeSnapshot?.alpha = isVisible ? 1 : 0
    }

    func prepareListChrome(for cell: TabViewListCell, initiallyVisible: Bool) {
        cell.layoutIfNeeded()
        cardBorder.backgroundColor = .clear
        cardBorder.isUserInteractionEnabled = false
        cardBorder.layer.cornerCurve = .continuous
        cardBorder.layer.borderColor = cell.border.layer.borderColor
        cardBorder.layer.borderWidth = cell.border.layer.borderWidth
        imageContainer.superview?.addSubview(cardBorder)

        listCellBorder = cell.border
        listCellBorderWasHidden = cell.border.isHidden
        cell.border.isHidden = true

        let borderOutset = TabViewCell.Constants.borderOutset / 2
        cardBorder.frame = imageContainer.frame.insetBy(dx: -borderOutset, dy: -borderOutset)
        cardBorder.layer.cornerRadius = initiallyVisible ? TabViewCell.Constants.borderRadius : 0
        applyListChromePose(isVisible: initiallyVisible)
    }

    func applyListChromePose(isVisible: Bool) {
        cardBorder.alpha = isVisible ? 1 : 0
    }

    func removeTransitionViews() {
        solidBackground.removeFromSuperview()
        cardShadow.removeFromSuperview()
        cardBorder.removeFromSuperview()
        imageContainer.removeFromSuperview()
        gridChromeSnapshot = nil
        listCellBorder?.isHidden = listCellBorderWasHidden
        listCellBorder = nil
    }
    
    func makeToolbarSnapshot(of toolbar: BrowserToolbarView,
                             in containerView: UIView,
                             afterScreenUpdates: Bool) -> UIView? {
        let captureRect = toolbar.visibleCapsuleRect
        guard let snapshot = toolbar.resizableSnapshotView(from: captureRect,
                                                           afterScreenUpdates: afterScreenUpdates,
                                                           withCapInsets: .zero) else { return nil }
        snapshot.frame = toolbar.convert(captureRect, to: containerView)
        return snapshot
    }

    func concealLiveFloatingToolbar(of mainViewController: MainViewController) {
        guard mainViewController.isFloatingUIEnabled else { return }
        mainViewController.beginTabSwitcherToolbarOwnership()
        mainViewController.viewCoordinator.toolbar.alpha = 0
    }

    func installToolbarSnapshot(for mainViewController: MainViewController,
                                transitionContext: UIViewControllerContextTransitioning,
                                afterScreenUpdates: Bool) -> UIView? {
        guard mainViewController.isFloatingUIEnabled else { return nil }

        concealLiveFloatingToolbar(of: mainViewController)
        let toolbar: BrowserToolbarView = mainViewController.viewCoordinator.toolbar
        defer { toolbar.alpha = 0 }

        guard let snapshot = makeToolbarSnapshot(of: toolbar,
                                                 in: transitionContext.containerView,
                                                 afterScreenUpdates: afterScreenUpdates) else { return nil }

        transitionContext.containerView.addSubview(snapshot)
        return snapshot
    }

    /// The live toolbar sits under the transition, so a copy of it (kept from when the tab switcher opened)
    /// fades in over the growing page like Safari's. Returns nil when there's no copy for this tab.
    func installReturningToolbarSnapshot(for tab: Tab, in containerView: UIView, response: TimeInterval) -> UIView? {
        guard let returningToolbarSnapshot, returningToolbarSnapshot.tab === tab else { return nil }
        let snapshot = returningToolbarSnapshot.view
        snapshot.alpha = 0
        snapshot.transform = CGAffineTransform(scaleX: Constants.floatingToolbarRevealScale, y: Constants.floatingToolbarRevealScale)
        containerView.addSubview(snapshot)
        UIView.animate(withDuration: 0.2, delay: response * 0.3, options: [.curveEaseOut]) {
            snapshot.alpha = 1
            snapshot.transform = .identity
        }
        return snapshot
    }

    /// Grows `cardView` from the cell back to the full screen, mirroring how `TabSwitcherSwipeUpTransition`
    /// shrank it. Near the end the card fades to reveal the live page and toolbar underneath, so the toolbar
    /// arrives with the page instead of after it.
    func runCardDismiss(_ cardView: TabSwitcherCardView,
                        rowIndex: Int,
                        layoutAttributes: UICollectionViewLayoutAttributes,
                        pageColor: UIColor,
                        using transitionContext: UIViewControllerContextTransitioning,
                        mainViewController: MainViewController,
                        tab: Tab,
                        whenPageReady: (@escaping () -> Void) -> Void) {
        let containerView = transitionContext.containerView
        let collectionView = tabSwitcherViewController.collectionView
        cardView.applyCellPose(cellFrame: collectionView.convert(layoutAttributes.frame, to: tabSwitcherViewController.view))
        scrollIfOutsideViewport(collectionView: collectionView, rowIndex: rowIndex, attributes: layoutAttributes)

        // Keeps the tab switcher's backdrop behind the growing card once the other cells have faded, and
        // hides the live page until the card hands over to it.
        let backdrop = UIView(frame: containerView.bounds)
        backdrop.backgroundColor = tabSwitcherViewController.view.backgroundColor
        containerView.insertSubview(backdrop, belowSubview: tabSwitcherViewController.view)
        containerView.addSubview(cardView)

        let cell = collectionView.cellForItem(at: IndexPath(row: rowIndex, section: 0)) as? TabViewCell
        if let cell {
            cardView.installChrome(from: cell, isVisible: true)
            cell.alpha = 0
        }

        let spring = TabSwitcherTransition.Spring.dismiss
        let toolbarSnapshot = installReturningToolbarSnapshot(for: tab, in: containerView, response: spring.response)
        let animator = spring.animator()
        animator.addAnimations {
            cardView.applyScreenPose(cardFrame: containerView.bounds)
        }
        // Switch to the page's colour quickly: blending from the cell's white over the whole spring
        // reads as a pale band above the page.
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut]) {
            cardView.setBackgroundColor(pageColor)
        }
        UIView.animate(withDuration: spring.response * 0.35, delay: 0, options: [.curveEaseOut]) {
            cardView.setChrome(visible: false)
        }
        UIView.animate(withDuration: spring.response * 0.55, delay: 0, options: [.curveEaseOut]) {
            self.tabSwitcherViewController.view.alpha = 0
        }

        var isHandOffDue = false
        var isPageReady = false
        var isHandOffStarted = false
        var isHandOffFinished = false
        var isAnimationFinished = false

        let finish = {
            guard isHandOffFinished, isAnimationFinished else { return }
            cardView.removeFromSuperview()
            backdrop.removeFromSuperview()
            toolbarSnapshot?.removeFromSuperview()
            cell?.alpha = 1
            self.removeTransitionViews()
            transitionContext.completeTransition(true)
        }
        let handOff = {
            guard isHandOffDue, isPageReady, !isHandOffStarted else { return }
            isHandOffStarted = true
            // The card covers the screen by now; drop the backdrop outright so the card fades straight
            // into the live page rather than through the backdrop's colour.
            backdrop.isHidden = true
            self.revealLiveToolbar(of: mainViewController, replacing: toolbarSnapshot)
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseInOut], animations: {
                cardView.alpha = 0
            }, completion: { _ in
                isHandOffFinished = true
                finish()
            })
        }

        whenPageReady {
            isPageReady = true
            handOff()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + spring.response * 0.75) {
            isHandOffDue = true
            handOff()
        }
        animator.addCompletion { _ in
            isAnimationFinished = true
            finish()
        }
        animator.startAnimation()
    }

    /// Hands the toolbar back to the page. When a returning copy is already showing it, the live toolbar
    /// appears in place instead of playing its own entrance.
    func revealLiveToolbar(of mainViewController: MainViewController, replacing toolbarSnapshot: UIView?) {
        mainViewController.revealFloatingToolbarAfterTabSwitcherTransition()
        guard toolbarSnapshot != nil else { return }
        let toolbar: BrowserToolbarView = mainViewController.viewCoordinator.toolbar
        toolbar.layer.removeAllAnimations()
        toolbar.alpha = 1
        toolbar.transform = .identity
    }

    // MARK: UIViewControllerAnimatedTransitioning

    // Override - Abstract function
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        assertionFailure("You must implement this method")
    }
    
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        let mainViewController = (transitionContext?.viewController(forKey: .from) as? MainViewController)
            ?? (transitionContext?.viewController(forKey: .to) as? MainViewController)
        return Self.duration(isFloatingUIEnabled: mainViewController?.isFloatingUIEnabled ?? false)
    }
    
    // MARK: Common logic
    
    func scrollIfOutsideViewport(collectionView: UICollectionView,
                                 rowIndex: Int,
                                 attributes: UICollectionViewLayoutAttributes) {
        // If cell is outside viewport, scroll while animating
        if attributes.frame.origin.y + attributes.frame.size.height < collectionView.contentOffset.y {
            collectionView.scrollToItem(at: IndexPath(row: rowIndex, section: 0),
                                        at: .top,
                                        animated: true)
        } else if attributes.frame.origin.y > collectionView.frame.height + collectionView.contentOffset.y {
            collectionView.scrollToItem(at: IndexPath(row: rowIndex, section: 0),
                                        at: .bottom,
                                        animated: true)
        }
    }
}

class TabSwitcherTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {

    weak var swipeUpTransition: TabSwitcherSwipeUpTransition?

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let mainVC = presenting as? MainViewController,
            let tabSwitcherVC = presented as? TabSwitcherViewController else {
            return nil
        }

        if let swipeUpTransition, swipeUpTransition.isActive {
            return swipeUpTransition
        }
        
        if mainVC.newTabPageViewController != nil {
            return FromHomeScreenTransition(mainViewController: mainVC,
                                            tabSwitcherViewController: tabSwitcherVC)
        }
        
        return FromWebViewTransition(mainViewController: mainVC,
                                     tabSwitcherViewController: tabSwitcherVC)
    }

    func interactionControllerForPresentation(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        animator as? TabSwitcherSwipeUpTransition
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let tabSwitcherVC = dismissed as? TabSwitcherViewController else { return nil }
        swipeUpTransition?.finishLanding()

        let transition: TabSwitcherTransition
        if let tab = tabSwitcherVC.tabsModel.currentTab, tab.link == nil {
            transition = ToHomeScreenTransition(tabSwitcherViewController: tabSwitcherVC)
        } else {
            transition = ToWebViewTransition(tabSwitcherViewController: tabSwitcherVC)
        }
        transition.returningToolbarSnapshot = swipeUpTransition?.takeReturnToolbarSnapshot()
        return transition
    }
}

extension TabSwitcherTransition {

    func adjustFrame(_ frame: CGRect, forAddressBarPosition position: AddressBarPosition, byMinY minY: CGFloat = 0.0, byHeight height: CGFloat = 0.0) -> CGRect {
        guard position.isBottom else { return frame }
        return CGRect(x: frame.minX,
                           y: frame.minY + minY,
                           width: frame.width,
                           height: frame.height + height)
    }

}
