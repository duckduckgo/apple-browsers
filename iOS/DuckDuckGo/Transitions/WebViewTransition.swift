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
}

class FromWebViewTransition: WebViewTransition {
    
    private let mainViewController: MainViewController
    
    init(mainViewController: MainViewController,
         tabSwitcherViewController: TabSwitcherViewController) {
        self.mainViewController = mainViewController

        super.init(tabSwitcherViewController: tabSwitcherViewController)
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
            mainViewController.isTabSwitcherTransitionOwningToolbar = false
            transitionContext.completeTransition(true)
            return
        }

        let indexPath = IndexPath(row: rowIndex, section: 0)
        tabSwitcherViewController.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)

        guard let layoutAttr = tabSwitcherViewController.collectionView.layoutAttributesForItem(at: indexPath),
              let preview = tabSwitcherViewController.previewsSource.preview(for: tab)
        else {
            tabSwitcherViewController.view.alpha = 1
            mainViewController.isTabSwitcherTransitionOwningToolbar = false
            transitionContext.completeTransition(true)
            return
        }

        let theme = ThemeManager.shared.currentTheme
        let webViewFrame = webView.convert(webView.bounds, to: nil)

        solidBackground.backgroundColor = theme.backgroundColor
        solidBackground.frame = webViewFrame

        let toolbar: BrowserToolbarView = mainViewController.viewCoordinator.toolbar
        let isFloating = mainViewController.isFloatingUIEnabled
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        var toolbarSnapshot: UIView?
        if isFloating {
            mainViewController.isTabSwitcherTransitionOwningToolbar = true
            if let snapshot = makeToolbarSnapshot(of: toolbar,
                                                  in: transitionContext.containerView,
                                                  afterScreenUpdates: false) {
                transitionContext.containerView.addSubview(snapshot)
                toolbarSnapshot = snapshot
            }
            toolbar.alpha = 0
        }

        imageContainer.frame = mainViewController.viewCoordinator.contentContainer.frame
        if isFloating {
            imageContainer.frame = WebViewTransitionGeometry.webContentFrame(
                from: imageContainer.frame,
                topObscuredHeight: webView.scrollView.contentInset.top)
        } else {
            imageContainer.frame = adjustFrame(imageContainer.frame,
                                               forAddressBarPosition: mainViewController.appSettings.currentAddressBarPosition,
                                               byHeight: -mainViewController.omniBar.barView.expectedHeight)
        }
        imageContainer.backgroundColor = theme.backgroundColor
        imageView.frame = imageContainer.bounds
        imageView.image = preview

        // Duck.ai tabs land on a rich card, not a screenshot. Crossfade a snapshot of the
        // destination cell over the webview preview so the shrink ends on matching content
        // instead of popping from screenshot to card. Gated on the rich-card flag: with it off
        // the AI cell is a screenshot, so there's nothing to crossfade to
        var cellSnapshot: UIView?
        if tab.isAITab, mainViewController.featureFlagger.isFeatureOn(.aiChatTabSwitcherRichCard) {
            tabSwitcherViewController.collectionView.layoutIfNeeded()
            if let cell = tabSwitcherViewController.collectionView.cellForItem(at: indexPath) as? TabViewGridCell {
                // Force the .image thumbnail in synchronously — its async load won't finish
                // before snapshotView captures the cell.
                cell.prepareForSnapshot()
                let currentBorderHidden = cell.border.isHidden
                cell.border.isHidden = true
                if let snapshot = cell.snapshotView(afterScreenUpdates: true) {
                    snapshot.frame = imageContainer.bounds
                    snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    snapshot.alpha = 0
                    imageContainer.addSubview(snapshot)
                    cellSnapshot = snapshot
                }
                cell.border.isHidden = currentBorderHidden
            }
               
        }

        animateCornerRadius(of: imageContainer, to: TabViewCell.Constants.cellCornerRadius, duration: TabSwitcherTransition.Constants.duration)

        UIView.animateKeyframes(withDuration: TabSwitcherTransition.Constants.duration, delay: 0, options: .calculationModeLinear, animations: {

            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                let containerFrame = self.tabSwitcherCellFrame(for: layoutAttr)
                self.imageContainer.frame = containerFrame
                self.imageView.frame = WebViewTransitionGeometry.previewFrame(for: containerFrame.size,
                                                                              previewSize: preview.size,
                                                                              isGridViewEnabled: self.tabSwitcherSettings.isGridViewEnabled)
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
                        let scale: CGFloat = 0.7
                        let heightLost = toolbarSnapshot.bounds.height * (1 - scale) / 2
                        toolbarSnapshot.transform = CGAffineTransform(scaleX: scale, y: scale)
                            .concatenating(CGAffineTransform(translationX: 0, y: heightLost))
                    }
                    toolbarSnapshot.alpha = 0
                }
            }
        }, completion: { _ in
            self.solidBackground.removeFromSuperview()
            self.imageContainer.removeFromSuperview()
            toolbarSnapshot?.removeFromSuperview()
            if isFloating {
                toolbar.alpha = 0
                self.mainViewController.isTabSwitcherTransitionOwningToolbar = false
            }
            transitionContext.completeTransition(true)
        })

    }
}

class ToWebViewTransition: WebViewTransition {

    override func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        prepareSubviews(using: transitionContext)
        
        guard let mainViewController = transitionContext.viewController(forKey: .to) as? MainViewController,
              let webView = mainViewController.currentTab?.webView,
              let tab = mainViewController.currentTab?.tabModel,
              let rowIndex = tabSwitcherViewController.tabsModel.indexOf(tab: tab),
              let layoutAttr = tabSwitcherViewController.collectionView.layoutAttributesForItem(at: IndexPath(row: rowIndex, section: 0))
        else {
            // Crossfade fallback when destination is no longer a web view; mirrors ToHomeScreenTransition.
            if let mainViewController = transitionContext.viewController(forKey: .to) as? MainViewController {
                mainViewController.view.alpha = 1
                mainViewController.isTabSwitcherTransitionOwningToolbar = false
                if mainViewController.isFloatingUIEnabled {
                    mainViewController.viewCoordinator.toolbar.transform = .identity
                    mainViewController.viewCoordinator.toolbar.alpha = 1
                }
            }
            UIView.animate(withDuration: TabSwitcherTransition.Constants.duration, animations: {
                self.tabSwitcherViewController.view.alpha = 0
            }, completion: { _ in
                self.solidBackground.removeFromSuperview()
                self.imageContainer.removeFromSuperview()
                transitionContext.completeTransition(true)
            })
            return
        }

        let theme = ThemeManager.shared.currentTheme
        mainViewController.view.alpha = 1

        let toolbar: BrowserToolbarView = mainViewController.viewCoordinator.toolbar
        let isFloating = mainViewController.isFloatingUIEnabled
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        var toolbarSnapshot: UIView?
        if isFloating {
            mainViewController.chromeManager.reset(animated: false)
            mainViewController.isTabSwitcherTransitionOwningToolbar = true
            if let snapshot = makeToolbarSnapshot(of: toolbar,
                                                  in: transitionContext.containerView,
                                                  afterScreenUpdates: true) {
                if !reduceMotion {
                    let scale: CGFloat = 0.7
                    let heightLost = snapshot.bounds.height * (1 - scale) / 2
                    snapshot.transform = CGAffineTransform(scaleX: scale, y: scale)
                        .concatenating(CGAffineTransform(translationX: 0, y: heightLost))
                }
                snapshot.alpha = 0
                transitionContext.containerView.addSubview(snapshot)
                toolbarSnapshot = snapshot
            }
            toolbar.alpha = 0
        }

        solidBackground.backgroundColor = theme.backgroundColor
        solidBackground.frame = webView.bounds
        // Put overlay above webview to hide its content till the end of the transition
        solidBackground.removeFromSuperview()
        webView.addSubview(solidBackground)
        
        imageContainer.frame = tabSwitcherCellFrame(for: layoutAttr)
        imageContainer.layer.cornerRadius = TabViewCell.Constants.cellCornerRadius
        imageContainer.backgroundColor = theme.backgroundColor

        let preview = tabSwitcherViewController.previewsSource.preview(for: tab)
        if let preview = preview {
            imageView.frame = WebViewTransitionGeometry.previewFrame(for: imageContainer.bounds.size,
                                                                     previewSize: preview.size,
                                                                     isGridViewEnabled: tabSwitcherSettings.isGridViewEnabled)
        } else {
            imageView.frame = CGRect(origin: .zero, size: imageContainer.bounds.size)
        }
        imageView.image = preview
        
        if !tabSwitcherSettings.isGridViewEnabled {
            self.imageView.alpha = 0
        }
        
        scrollIfOutsideViewport(collectionView: tabSwitcherViewController.collectionView, rowIndex: rowIndex, attributes: layoutAttr)

        animateCornerRadius(of: imageContainer, to: 0, duration: TabSwitcherTransition.Constants.duration)

        UIView.animateKeyframes(withDuration: TabSwitcherTransition.Constants.duration, delay: 0, options: .calculationModeLinear, animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                var destinationFrame = mainViewController.viewCoordinator.contentContainer.frame
                if isFloating {
                    destinationFrame = WebViewTransitionGeometry.webContentFrame(
                        from: destinationFrame,
                        topObscuredHeight: webView.scrollView.contentInset.top)
                }
                self.imageContainer.frame = destinationFrame

                self.imageView.frame = WebViewTransitionGeometry.destinationImageFrame(for: destinationFrame.size,
                                                                                       previewSize: preview?.size)
                self.imageView.alpha = 1
                self.solidBackground.alpha = 1
            }

            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.7) {
                self.tabSwitcherViewController.view.alpha = 0
            }

            if let toolbarSnapshot {
                let easedScale: CGFloat = 0.955 // 0.7 + 0.85 * (1 - 0.7)
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.6) {
                    if !reduceMotion {
                        let heightLost = toolbarSnapshot.bounds.height * (1 - easedScale) / 2
                        toolbarSnapshot.transform = CGAffineTransform(scaleX: easedScale, y: easedScale)
                            .concatenating(CGAffineTransform(translationX: 0, y: heightLost))
                    }
                    toolbarSnapshot.alpha = 0.85
                }
                UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.4) {
                    if !reduceMotion {
                        toolbarSnapshot.transform = .identity
                    }
                    toolbarSnapshot.alpha = 1
                }
            }
        }, completion: { _ in
            self.solidBackground.removeFromSuperview()
            self.imageContainer.removeFromSuperview()
            toolbarSnapshot?.removeFromSuperview()
            if isFloating {
                toolbar.alpha = 1
                mainViewController.isTabSwitcherTransitionOwningToolbar = false
            }
            transitionContext.completeTransition(true)
        })
    }

}
