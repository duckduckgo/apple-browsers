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
import WebKit
import FeatureFlags_iOS

class WebViewTransition: TabSwitcherTransition {

    fileprivate let tabSwitcherSettings: TabSwitcherSettings = DefaultTabSwitcherSettings()

    fileprivate func tabSwitcherCellFrame(for attributes: UICollectionViewLayoutAttributes) -> CGRect {
        return self.tabSwitcherViewController.collectionView.convert(attributes.frame,
                                                                     to: self.tabSwitcherViewController.view)
    }

    /// In floating UI the page runs edge to edge, so the card is the whole screen (status band included)
    /// with the display's corner radius, like Safari, and the page sits in it at `webViewFrame`.
    fileprivate func screenCardGeometry(webViewFrame: CGRect,
                                        in containerView: UIView) -> (frame: CGRect, contentFrame: CGRect, cornerRadius: CGFloat) {
        let screenFrame = containerView.bounds
        let contentFrame = CGRect(x: webViewFrame.minX - screenFrame.minX,
                                  y: webViewFrame.minY - screenFrame.minY,
                                  width: webViewFrame.width,
                                  height: screenFrame.maxY - webViewFrame.minY)
        return (screenFrame, contentFrame, TabSwitcherTransition.screenCornerRadius(for: containerView))
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
}

class FromWebViewTransition: WebViewTransition {
    
    private let mainViewController: MainViewController
    
    init(mainViewController: MainViewController,
         tabSwitcherViewController: TabSwitcherViewController) {
        self.mainViewController = mainViewController

        super.init(tabSwitcherViewController: tabSwitcherViewController)
    }
    
    /// Duck.ai tabs land on a rich card, not a screenshot. Crossfade a snapshot of the
    /// destination cell over the webview preview so the shrink ends on matching content
    /// instead of popping from screenshot to card. Gated on the rich-card flag: with it off
    /// the AI cell is a screenshot, so there's nothing to crossfade to.
    private func installAITabCellSnapshot(for tab: Tab, at indexPath: IndexPath) -> UIView? {
        guard tab.isAITab,
              mainViewController.featureFlagger.isFeatureOn(.aiChatTabSwitcherRichCard) else { return nil }

        tabSwitcherViewController.collectionView.layoutIfNeeded()
        guard let cell = tabSwitcherViewController.collectionView
            .cellForItem(at: indexPath) as? TabViewGridCell else { return nil }

        // Force the .image thumbnail in synchronously — its async load won't finish
        // before snapshotView captures the cell.
        cell.prepareForSnapshot()
        let currentBorderHidden = cell.border.isHidden
        cell.border.isHidden = true
        defer { cell.border.isHidden = currentBorderHidden }

        guard let snapshot = cell.snapshotView(afterScreenUpdates: true) else { return nil }
        snapshot.frame = imageContainer.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshot.alpha = 0
        imageContainer.addSubview(snapshot)
        return snapshot
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

        TabSwitcherCellFrameCache.store(tabSwitcherCellFrame(for: layoutAttr), row: rowIndex, in: tabSwitcherViewController)

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

        let cellSnapshot = installAITabCellSnapshot(for: tab, at: indexPath)
        prepareOutgoingTabChrome(at: indexPath, cellSnapshot: cellSnapshot)

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
            }

            if self.tabSwitcherSettings.isGridViewEnabled {
                UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.55) {
                    self.applyGridChromePose(isVisible: true)
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

    private func prepareOutgoingTabChrome(at indexPath: IndexPath, cellSnapshot: UIView?) {
        if tabSwitcherSettings.isGridViewEnabled,
           cellSnapshot == nil,
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

    private func preparePreview(_ preview: UIImage?, rowIndex: Int) {
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

        if !tabSwitcherSettings.isGridViewEnabled {
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

        let theme = ThemeManager.shared.currentTheme
        mainViewController.view.alpha = 1

        let isFloating = mainViewController.isFloatingUIEnabled
        if isFloating {
            mainViewController.chromeManager.reset(animated: false)
            concealLiveFloatingToolbar(of: mainViewController)
        }

        if tabSwitcherViewController.transitionStyle == .modern,
           TabSwitcherTransition.usesCardTransition(for: mainViewController),
           let preview = tabSwitcherViewController.previewsSource.preview(for: tab) {
            animateCardDismiss(using: transitionContext,
                               mainViewController: mainViewController,
                               webView: webView,
                               preview: preview,
                               rowIndex: rowIndex,
                               layoutAttr: layoutAttr)
            return
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
        preparePreview(preview, rowIndex: rowIndex)
        
        scrollIfOutsideViewport(collectionView: tabSwitcherViewController.collectionView, rowIndex: rowIndex, attributes: layoutAttr)

        if tabSwitcherViewController.transitionStyle == .legacy {
            animateLegacyDismiss(using: transitionContext,
                                 mainViewController: mainViewController,
                                 webView: webView,
                                 preview: preview,
                                 isFloating: isFloating,
                                 usesFloatingTopBackdrop: usesFloatingTopBackdrop)
            return
        }

        let isGrid = tabSwitcherSettings.isGridViewEnabled
        let destination = destinationCardGeometry(for: mainViewController,
                                                  webView: webView,
                                                  containerView: transitionContext.containerView)
        let spring = TabSwitcherTransition.Spring.dismiss
        let animator = spring.animator()
        animator.addAnimations {
            self.setCardFrame(destination.frame, cornerRadius: destination.cornerRadius, shadowOpacity: 0)
            self.imageView.frame = WebViewTransitionGeometry.destinationImageFrame(for: destination.contentFrame.size,
                                                                                   previewSize: preview?.size,
                                                                                   alignsWithContainerBottom: isFloating)
                .offsetBy(dx: destination.contentFrame.minX, dy: destination.contentFrame.minY)
            self.imageView.alpha = 1
            self.solidBackground.alpha = 1
            if isFloating {
                self.imageContainer.backgroundColor = mainViewController.viewCoordinator.statusBackground.backgroundColor
            }
            if !isGrid {
                self.applyListChromePose(isVisible: false)
            }
        }

        UIView.animate(withDuration: spring.response * 0.55, delay: 0, options: [.curveEaseOut]) {
            self.tabSwitcherViewController.view.alpha = 0
        }

        if isGrid {
            UIView.animate(withDuration: spring.response * 0.45, delay: 0, options: [.curveEaseOut]) {
                self.applyGridChromePose(isVisible: false)
            }
        }

        var isWebViewRendered = false
        var isAnimationFinished = false
        let finish = {
            guard isWebViewRendered, isAnimationFinished else { return }
            self.removeTransitionViews()
            if usesFloatingTopBackdrop {
                mainViewController.viewCoordinator.navigationBarContainer.backgroundColor = .clear
            }
            mainViewController.revealFloatingToolbarAfterTabSwitcherTransition()
            transitionContext.completeTransition(true)
        }
        TabSwitcherTransition.whenRendered(webView) {
            isWebViewRendered = true
            finish()
        }
        animator.addCompletion { _ in
            isAnimationFinished = true
            finish()
        }
        animator.startAnimation()
    }

    private func animateLegacyDismiss(using transitionContext: UIViewControllerContextTransitioning,
                                      mainViewController: MainViewController,
                                      webView: WKWebView,
                                      preview: UIImage?,
                                      isFloating: Bool,
                                      usesFloatingTopBackdrop: Bool) {
        UIView.animateKeyframes(withDuration: TabSwitcherTransition.duration(isFloatingUIEnabled: isFloating), delay: 0, options: .calculationModeLinear, animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                var destinationFrame = mainViewController.viewCoordinator.contentContainer.frame
                if isFloating {
                    destinationFrame = webView.convert(webView.bounds, to: transitionContext.containerView)
                }
                self.setCardFrame(destinationFrame, cornerRadius: 0, shadowOpacity: 0)
                self.imageView.frame = WebViewTransitionGeometry.destinationImageFrame(for: destinationFrame.size,
                                                                                       previewSize: preview?.size,
                                                                                       alignsWithContainerBottom: isFloating)
                self.imageView.alpha = 1
                self.solidBackground.alpha = 1
                if !self.tabSwitcherSettings.isGridViewEnabled {
                    self.applyListChromePose(isVisible: false)
                }
            }

            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.7) {
                self.tabSwitcherViewController.view.alpha = 0
            }

            if self.tabSwitcherSettings.isGridViewEnabled {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.55) {
                    self.applyGridChromePose(isVisible: false)
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

    /// The cell's preview grows back into the page.
    private func animateCardDismiss(using transitionContext: UIViewControllerContextTransitioning,
                                    mainViewController: MainViewController,
                                    webView: WKWebView,
                                    preview: UIImage,
                                    rowIndex: Int,
                                    layoutAttr: UICollectionViewLayoutAttributes) {
        let containerView = transitionContext.containerView
        let backgroundColor = mainViewController.floatingTabSwitcherTransitionBackgroundColor
        // A web view just attached for a different tab hasn't been laid out yet; its frame and insets
        // would place the preview off from where the page will actually draw.
        mainViewController.view.layoutIfNeeded()
        let statusAreaColor = mainViewController.appSettings.currentAddressBarPosition.isBottom
            ? Self.statusAreaColor(of: webView, preview: preview) ?? backgroundColor
            : mainViewController.viewCoordinator.statusBackground.backgroundColor ?? backgroundColor

        let webViewFrame = webView.convert(webView.bounds, to: containerView)
        let cropTop = webView.scrollView.contentInset.top
        let previewFrameInScreen = CGRect(x: webViewFrame.minX,
                                          y: webViewFrame.minY + cropTop,
                                          width: webViewFrame.width,
                                          height: webViewFrame.height - cropTop)
        let cardView = TabSwitcherCardView(content: UIImageView(image: preview),
                                           contentFrameInScreen: previewFrameInScreen,
                                           contentCropTop: 0,
                                           screenBounds: containerView.bounds,
                                           screenCornerRadius: TabSwitcherTransition.screenCornerRadius(for: containerView),
                                           screenBackgroundColor: statusAreaColor)
        runCardDismiss(cardView,
                       rowIndex: rowIndex,
                       layoutAttributes: layoutAttr,
                       pageColor: statusAreaColor,
                       using: transitionContext,
                       mainViewController: mainViewController,
                       whenPageReady: { TabSwitcherTransition.whenRendered(webView, $0) })
    }

    /// With the address bar at the bottom the page runs under the status bar, which the stored preview leaves out.
    /// At the top of the page that strip shows the page's overscroll colour; further down it shows content, whose
    /// best guess is the preview's top edge.
    private static func statusAreaColor(of webView: WKWebView, preview: UIImage) -> UIColor? {
        let scrollView = webView.scrollView
        if scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1 {
            return webView.underPageBackgroundColor
        }
        return topEdgeColor(of: preview)
    }

    private static func topEdgeColor(of image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage, cgImage.width > 0, cgImage.height > 0,
              let strip = cgImage.cropping(to: CGRect(x: 0, y: 0, width: cgImage.width, height: min(4, cgImage.height))) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn, pixel[3] > 0 else { return nil }
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }

    private func destinationCardGeometry(for mainViewController: MainViewController,
                                         webView: UIView,
                                         containerView: UIView) -> (frame: CGRect, contentFrame: CGRect, cornerRadius: CGFloat) {
        guard mainViewController.isFloatingUIEnabled else {
            let frame = mainViewController.viewCoordinator.contentContainer.frame
            return (frame, CGRect(origin: .zero, size: frame.size), 0)
        }
        return screenCardGeometry(webViewFrame: webView.convert(webView.bounds, to: containerView), in: containerView)
    }

}
