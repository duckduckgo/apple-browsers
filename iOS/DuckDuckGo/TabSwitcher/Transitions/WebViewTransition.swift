//
//  WebViewTransition.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Core
import FeatureFlags_iOS

class WebViewTransition: TabSwitcherTransition {

    fileprivate let tabSwitcherSettings: TabSwitcherSettings = DefaultTabSwitcherSettings()

    fileprivate func tabSwitcherCellFrame(for attributes: UICollectionViewLayoutAttributes) -> CGRect {
        return self.tabSwitcherViewController.collectionView.convert(attributes.frame,
                                                                     to: self.tabSwitcherViewController.view)
    }

    fileprivate func animateCornerRadius(of view: UIView, to radius: CGFloat, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: "cornerRadius")
        animation.fromValue = view.layer.cornerRadius
        animation.toValue = radius
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(animation, forKey: "cornerRadius")
        view.layer.cornerRadius = radius
    }

    /// Duck.ai cells show a rich card, not a screenshot, so the transition crossfades the cell body
    /// against the preview. With the rich-card flag off the cell is a screenshot: nothing to crossfade.
    fileprivate func installAITabCellSnapshot(for tab: Tab, at indexPath: IndexPath, isRichCardEnabled: Bool) -> UIView? {
        guard tab.isAITab, isRichCardEnabled else { return nil }

        tabSwitcherViewController.collectionView.layoutIfNeeded()
        guard let cell = tabSwitcherViewController.collectionView
            .cellForItem(at: indexPath) as? TabViewGridCell else { return nil }

        // Force the .image thumbnail in synchronously — its async load won't finish
        // before snapshotView captures the cell.
        cell.prepareForSnapshot()
        let currentBorderHidden = cell.border.isHidden
        cell.border.isHidden = true
        defer { cell.border.isHidden = currentBorderHidden }

        cell.layoutIfNeeded()
        let headerHeight = TabViewGridCell.Constants.headerHeight
        let bodyFrame = CGRect(x: 0, y: headerHeight,
                               width: cell.bounds.width,
                               height: cell.bounds.height - headerHeight)
        guard bodyFrame.height > 0, cell.bounds.width > 0,
              let snapshot = cell.resizableSnapshotView(from: bodyFrame,
                                                        afterScreenUpdates: true,
                                                        withCapInsets: .zero) else { return nil }
        snapshot.frame = bodyFrame
        imageContainer.addSubview(snapshot)
        return snapshot
    }

    /// Uniform scale: stretching to the card's frame squashes the logo.
    fileprivate func expandAITabCellSnapshot(_ snapshot: UIView?, centeredAt center: CGPoint) {
        guard let snapshot, snapshot.bounds.width > 0 else { return }
        let scale = imageContainer.bounds.width / snapshot.bounds.width
        snapshot.transform = CGAffineTransform(scaleX: scale, y: scale)
        snapshot.center = center
    }

    fileprivate func settleAITabCellSnapshot(_ snapshot: UIView?, inCardOfSize cardSize: CGSize) {
        guard let snapshot else { return }
        snapshot.transform = .identity
        snapshot.center = CGPoint(x: cardSize.width / 2,
                                  y: TabViewGridCell.Constants.headerHeight + snapshot.bounds.height / 2)
    }
}

class FromWebViewTransition: WebViewTransition {
    
    private let mainViewController: MainViewController
    
    init(mainViewController: MainViewController,
         tabSwitcherViewController: TabSwitcherViewController) {
        self.mainViewController = mainViewController

        super.init(tabSwitcherViewController: tabSwitcherViewController)
    }
    
    /// Start point for the cell snapshot, so its logo covers the logo in the preview image.
    /// With the keyboard up, the page centres its logo above the input rather than in the card, and the
    /// preview image doesn't line up with the live page, so the logo's position on the page is mapped onto the image.
    private func aiTabCellSnapshotStartCenter() -> CGPoint {
        let bounds = imageContainer.bounds
        let cardCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        guard mainViewController.keyboardShowing,
              let coordinator = mainViewController.viewCoordinator,
              coordinator.isUnifiedToggleInputVisible,
              let input = coordinator.unifiedToggleInputContainer,
              let webView = mainViewController.currentTab?.webView else { return cardCenter }

        let page = imageContainer.convert(webView.bounds, from: webView)
        let inputTop = imageContainer.convert(input.bounds, from: input).minY
        guard page.height > 0, inputTop > page.minY else { return cardCenter }
        let logoFraction = (min(inputTop, page.maxY) - page.minY) / 2 / page.height
        return CGPoint(x: bounds.midX, y: imageView.frame.minY + logoFraction * imageView.frame.height)
    }

    override func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        prepareSubviews(using: transitionContext)

        tabSwitcherViewController.view.alpha = 0
        transitionContext.containerView.insertSubview(tabSwitcherViewController.view, aboveSubview: solidBackground)
        tabSwitcherViewController.view.frame = transitionContext.finalFrame(for: tabSwitcherViewController)
        tabSwitcherViewController.prepareForPresentation()
        
        guard let webView = mainViewController.currentTab?.webView,
              let tab = mainViewController.tabManager.currentTabsModel.currentTab,
              let rowIndex = tabSwitcherViewController.tabsModel.indexOf(tab: tab)
        else {
            tabSwitcherViewController.view.alpha = 1
            removeTransitionViews()
            mainViewController.endTabSwitcherToolbarOwnership()
            transitionContext.completeTransition(true)
            return
        }

        let indexPath = IndexPath(row: rowIndex, section: 0)
        tabSwitcherViewController.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)

        guard let layoutAttr = tabSwitcherViewController.collectionView.layoutAttributesForItem(at: indexPath),
              let preview = tabSwitcherViewController.previewsSource.preview(for: tab)
        else {
            tabSwitcherViewController.view.alpha = 1
            removeTransitionViews()
            mainViewController.endTabSwitcherToolbarOwnership()
            transitionContext.completeTransition(true)
            return
        }

        let theme = ThemeManager.shared.currentTheme
        let webViewFrame = webView.convert(webView.bounds, to: transitionContext.containerView)

        solidBackground.backgroundColor = theme.backgroundColor
        solidBackground.frame = webViewFrame

        let toolbar: BrowserToolbarView = mainViewController.viewCoordinator.toolbar
        let isFloating = mainViewController.isFloatingUIEnabled
        let duration = TabSwitcherTransition.duration(isFloatingUIEnabled: isFloating)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let toolbarSnapshot = installToolbarSnapshot(for: mainViewController,
                                                     transitionContext: transitionContext,
                                                     afterScreenUpdates: false)

        var initialContainerFrame = mainViewController.viewCoordinator.contentContainer.frame
        if isFloating {
            initialContainerFrame = webViewFrame
        } else {
            initialContainerFrame = adjustFrame(initialContainerFrame,
                                                forAddressBarPosition: mainViewController.appSettings.currentAddressBarPosition,
                                                byHeight: -mainViewController.omniBar.barView.expectedHeight)
        }
        setCardFrame(initialContainerFrame, cornerRadius: 0, shadowOpacity: 0)
        imageContainer.backgroundColor = theme.backgroundColor
        imageView.frame = WebViewTransitionGeometry.destinationImageFrame(
            for: imageContainer.bounds.size,
            previewSize: preview.size,
            alignsWithContainerBottom: isFloating)
        imageView.image = preview

        let cellSnapshot = installAITabCellSnapshot(
            for: tab,
            at: indexPath,
            isRichCardEnabled: mainViewController.featureFlagger.isFeatureOn(.aiChatTabSwitcherRichCard))
        expandAITabCellSnapshot(cellSnapshot, centeredAt: aiTabCellSnapshotStartCenter())
        cellSnapshot?.alpha = 0
        prepareOutgoingTabChrome(at: indexPath)

        UIView.animateKeyframes(withDuration: duration, delay: 0, options: .calculationModeLinear, animations: {

            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                let containerFrame = self.tabSwitcherCellFrame(for: layoutAttr)
                self.setCardFrame(containerFrame,
                                  cornerRadius: TabViewCell.Constants.cellCornerRadius,
                                  shadowOpacity: 1)
                self.imageView.frame = WebViewTransitionGeometry.previewFrame(for: containerFrame.size,
                                                                              previewSize: preview.size,
                                                                              isGridViewEnabled: self.tabSwitcherSettings.isGridViewEnabled)
                if !self.tabSwitcherSettings.isGridViewEnabled {
                    self.applyListChromePose(isVisible: true)
                }
                self.settleAITabCellSnapshot(cellSnapshot, inCardOfSize: containerFrame.size)
            }

            if self.tabSwitcherSettings.isGridViewEnabled {
                UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.55) {
                    self.applyGridChromePose(
                        isVisible: true,
                        in: CGRect(origin: .zero, size: self.tabSwitcherCellFrame(for: layoutAttr).size))
                }
            }

            UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.7) {
                self.tabSwitcherViewController.view.alpha = 1
            }

            if let cellSnapshot {
                // Crossfade webview preview out / cell snapshot in over the first half.
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                    self.imageView.alpha = 0
                    cellSnapshot.alpha = 1
                }
            } else if !self.tabSwitcherSettings.isGridViewEnabled {
                UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.5) {
                    self.imageView.alpha = 0
                }
            }

            if let toolbarSnapshot {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                    if !reduceMotion {
                        toolbarSnapshot.transform = TabSwitcherTransition.collapsedToolbarTransform(for: toolbarSnapshot)
                    }
                    toolbarSnapshot.alpha = 0
                }
            }
        }, completion: { _ in
            self.removeTransitionViews()
            toolbarSnapshot?.removeFromSuperview()
            if isFloating {
                toolbar.alpha = 0
                self.mainViewController.endTabSwitcherToolbarOwnership()
            }
            transitionContext.completeTransition(true)
        })

    }

    private func prepareOutgoingTabChrome(at indexPath: IndexPath) {
        if tabSwitcherSettings.isGridViewEnabled,
           let cell = tabSwitcherViewController.collectionView.cellForItem(at: indexPath) as? TabViewGridCell {
            prepareGridChromeSnapshot(for: cell, initiallyVisible: false)
        } else if !tabSwitcherSettings.isGridViewEnabled,
                  let cell = tabSwitcherViewController.collectionView.cellForItem(at: indexPath) as? TabViewListCell {
            prepareListChrome(for: cell, initiallyVisible: false)
        }
    }
}

class ToWebViewTransition: WebViewTransition {

    /// Crossfade fallback when the destination is no longer a web view; mirrors ToHomeScreenTransition.
    /// Hands the toolbar back to its normal owner so a guard-failed transition can't strand it hidden.
    private func completeWithCrossfadeFallback(using transitionContext: UIViewControllerContextTransitioning) {
        let mainViewController = transitionContext.viewController(forKey: .to) as? MainViewController
        if let mainViewController {
            mainViewController.view.alpha = 1
            concealLiveFloatingToolbar(of: mainViewController)
        }
        let duration = TabSwitcherTransition.duration(isFloatingUIEnabled: mainViewController?.isFloatingUIEnabled ?? false)
        UIView.animate(withDuration: duration, animations: {
            self.tabSwitcherViewController.view.alpha = 0
        }, completion: { _ in
            self.removeTransitionViews()
            mainViewController?.revealFloatingToolbarAfterTabSwitcherTransition()
            transitionContext.completeTransition(true)
        })
    }

    private func preparePreview(_ preview: UIImage?, rowIndex: Int, fadesIn: Bool) {
        if let preview {
            imageView.frame = WebViewTransitionGeometry.previewFrame(for: imageContainer.bounds.size,
                                                                     previewSize: preview.size,
                                                                     isGridViewEnabled: tabSwitcherSettings.isGridViewEnabled)
        } else {
            imageView.frame = CGRect(origin: .zero, size: imageContainer.bounds.size)
        }
        imageView.image = preview

        let indexPath = IndexPath(row: rowIndex, section: 0)
        if tabSwitcherSettings.isGridViewEnabled,
           let cell = tabSwitcherViewController.collectionView.cellForItem(at: indexPath) as? TabViewGridCell {
            prepareGridChromeSnapshot(for: cell, initiallyVisible: true)
        } else if let cell = tabSwitcherViewController.collectionView.cellForItem(at: indexPath) as? TabViewListCell {
            prepareListChrome(for: cell, initiallyVisible: true)
        }

        if fadesIn || !tabSwitcherSettings.isGridViewEnabled {
            imageView.alpha = 0
        }
    }

    override func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        prepareSubviews(using: transitionContext)
        
        guard let mainViewController = transitionContext.viewController(forKey: .to) as? MainViewController,
              let webView = mainViewController.currentTab?.webView,
              let tab = mainViewController.currentTab?.tabModel,
              let rowIndex = tabSwitcherViewController.tabsModel.indexOf(tab: tab),
              let layoutAttr = tabSwitcherViewController.collectionView.layoutAttributesForItem(at: IndexPath(row: rowIndex, section: 0))
        else {
            completeWithCrossfadeFallback(using: transitionContext)
            return
        }

        // Before the card is laid out (afterScreenUpdates would flash it empty) and under the header snapshot.
        let cellSnapshot = installAITabCellSnapshot(
            for: tab,
            at: IndexPath(row: rowIndex, section: 0),
            isRichCardEnabled: mainViewController.featureFlagger.isFeatureOn(.aiChatTabSwitcherRichCard))

        let theme = ThemeManager.shared.currentTheme
        mainViewController.view.alpha = 1

        let isFloating = mainViewController.isFloatingUIEnabled
        let duration = TabSwitcherTransition.duration(isFloatingUIEnabled: isFloating)
        if isFloating {
            mainViewController.chromeManager.reset(animated: false)
            concealLiveFloatingToolbar(of: mainViewController)
        }

        let transitionBackgroundColor = isFloating
            ? mainViewController.floatingTabSwitcherTransitionBackgroundColor
            : theme.backgroundColor
        solidBackground.backgroundColor = transitionBackgroundColor
        solidBackground.frame = webView.bounds
        // Put overlay above webview to hide its content till the end of the transition
        solidBackground.removeFromSuperview()
        webView.addSubview(solidBackground)
        
        let initialContainerFrame = tabSwitcherCellFrame(for: layoutAttr)
        setCardFrame(initialContainerFrame,
                     cornerRadius: TabViewCell.Constants.cellCornerRadius,
                     shadowOpacity: 1)
        imageContainer.backgroundColor = transitionBackgroundColor
        let usesFloatingTopBackdrop = isFloating && mainViewController.appSettings.currentAddressBarPosition == .top
        if usesFloatingTopBackdrop {
            mainViewController.viewCoordinator.navigationBarContainer.backgroundColor = transitionBackgroundColor
        }
        let preview = tabSwitcherViewController.previewsSource.preview(for: tab)
        preparePreview(preview, rowIndex: rowIndex, fadesIn: cellSnapshot != nil)
        
        scrollIfOutsideViewport(collectionView: tabSwitcherViewController.collectionView, rowIndex: rowIndex, attributes: layoutAttr)

        UIView.animateKeyframes(withDuration: duration, delay: 0, options: .calculationModeLinear, animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                var destinationFrame = mainViewController.viewCoordinator.contentContainer.frame
                if isFloating {
                    destinationFrame = webView.convert(webView.bounds, to: transitionContext.containerView)
                }
                self.setCardFrame(destinationFrame, cornerRadius: 0, shadowOpacity: 0)
                self.imageView.frame = WebViewTransitionGeometry.destinationImageFrame(for: destinationFrame.size,
                                                                                       previewSize: preview?.size,
                                                                                       alignsWithContainerBottom: isFloating)
                self.expandAITabCellSnapshot(cellSnapshot,
                                             centeredAt: CGPoint(x: destinationFrame.width / 2, y: destinationFrame.height / 2))
                if cellSnapshot == nil {
                    self.imageView.alpha = 1
                }
                self.solidBackground.alpha = 1
                if !self.tabSwitcherSettings.isGridViewEnabled {
                    self.applyListChromePose(isVisible: false)
                }
            }

            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.7) {
                self.tabSwitcherViewController.view.alpha = 0
            }

            if let cellSnapshot {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.3) {
                    cellSnapshot.alpha = 0
                }
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                    self.imageView.alpha = 1
                }
            }

            if self.tabSwitcherSettings.isGridViewEnabled {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.55) {
                    var destinationFrame = mainViewController.viewCoordinator.contentContainer.frame
                    if isFloating {
                        destinationFrame = webView.convert(webView.bounds, to: transitionContext.containerView)
                    }
                    self.applyGridChromePose(
                        isVisible: false,
                        in: CGRect(origin: .zero, size: destinationFrame.size))
                }
            }
        }, completion: { _ in
            self.removeTransitionViews()
            if usesFloatingTopBackdrop {
                mainViewController.viewCoordinator.navigationBarContainer.backgroundColor = .clear
            }
            mainViewController.revealFloatingToolbarAfterTabSwitcherTransition()
            transitionContext.completeTransition(true)
        })
    }

}
