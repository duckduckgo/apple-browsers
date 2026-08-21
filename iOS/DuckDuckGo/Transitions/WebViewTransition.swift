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
            completeWithoutAnimation(using: transitionContext)
            return
        }

        let indexPath = IndexPath(row: rowIndex, section: 0)
        tabSwitcherViewController.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)

        guard let layoutAttr = tabSwitcherViewController.collectionView.layoutAttributesForItem(at: indexPath),
              let preview = tabSwitcherViewController.previewsSource.preview(for: tab)
        else {
            completeWithoutAnimation(using: transitionContext)
            return
        }

        let theme = ThemeManager.shared.currentTheme
        let webViewFrame = webView.convert(webView.bounds, to: nil)
        
        solidBackground.backgroundColor = theme.backgroundColor
        solidBackground.frame = webViewFrame
        
        var initialContainerFrame = mainViewController.viewCoordinator.contentContainer.frame
        initialContainerFrame = adjustFrame(initialContainerFrame,
                                            forAddressBarPosition: mainViewController.appSettings.currentAddressBarPosition,
                                            byHeight: -mainViewController.omniBar.barView.expectedHeight)
        setCardFrame(initialContainerFrame, cornerRadius: 0, shadowOpacity: 0)
        imageView.frame = imageContainer.bounds
        imageView.image = preview

        let cellSnapshot = makeAITabCellSnapshotIfNeeded(for: tab, at: indexPath)
        prepareOutgoingTabChrome(at: indexPath, cellSnapshot: cellSnapshot)
        animateToTabSwitcher(layoutAttr: layoutAttr,
                             preview: preview,
                             cellSnapshot: cellSnapshot,
                             transitionContext: transitionContext)
    }

    private func completeWithoutAnimation(using transitionContext: UIViewControllerContextTransitioning) {
        tabSwitcherViewController.view.alpha = 1
        removeTransitionViews()
        transitionContext.completeTransition(true)
    }

    /// Duck.ai tabs land on a rich card, not a screenshot. Crossfade a snapshot of the
    /// destination cell over the webview preview so the shrink ends on matching content
    /// instead of popping from screenshot to card. Gated on the rich-card flag: with it off
    /// the AI cell is a screenshot, so there's nothing to crossfade to.
    private func makeAITabCellSnapshotIfNeeded(for tab: Tab, at indexPath: IndexPath) -> UIView? {
        guard tab.isAITab,
              mainViewController.featureFlagger.isFeatureOn(.aiChatTabSwitcherRichCard) else {
            return nil
        }

        tabSwitcherViewController.collectionView.layoutIfNeeded()
        guard let cell = tabSwitcherViewController.collectionView.cellForItem(at: indexPath) as? TabViewGridCell else {
            return nil
        }

        // Force the .image thumbnail in synchronously — its async load won't finish
        // before snapshotView captures the cell.
        cell.prepareForSnapshot()
        let currentBorderHidden = cell.border.isHidden
        cell.border.isHidden = true
        defer { cell.border.isHidden = currentBorderHidden }

        guard let snapshot = cell.snapshotView(afterScreenUpdates: true) else {
            return nil
        }
        snapshot.frame = imageContainer.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshot.alpha = 0
        imageContainer.addSubview(snapshot)
        return snapshot
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

    private func animateToTabSwitcher(layoutAttr: UICollectionViewLayoutAttributes,
                                      preview: UIImage,
                                      cellSnapshot: UIView?,
                                      transitionContext: UIViewControllerContextTransitioning) {
        UIView.animateKeyframes(withDuration: TabSwitcherTransition.Constants.duration, delay: 0, options: .calculationModeLinear, animations: {

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
        }, completion: { _ in
            self.removeTransitionViews()
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
            }
            UIView.animate(withDuration: TabSwitcherTransition.Constants.duration, animations: {
                self.tabSwitcherViewController.view.alpha = 0
            }, completion: { _ in
                self.removeTransitionViews()
                transitionContext.completeTransition(true)
            })
            return
        }
                
        let theme = ThemeManager.shared.currentTheme
        let webViewFrame = webView.convert(webView.bounds, to: nil)
        mainViewController.view.alpha = 1
        
        solidBackground.backgroundColor = theme.backgroundColor
        solidBackground.frame = webView.bounds
        // Put overlay above webview to hide its content till the end of the transition
        solidBackground.removeFromSuperview()
        webView.addSubview(solidBackground)
        
        let initialContainerFrame = tabSwitcherCellFrame(for: layoutAttr)
        setCardFrame(initialContainerFrame,
                     cornerRadius: TabViewCell.Constants.cellCornerRadius,
                     shadowOpacity: 1)
        
        let preview = tabSwitcherViewController.previewsSource.preview(for: tab)
        if let preview = preview {
            imageView.frame = WebViewTransitionGeometry.previewFrame(for: imageContainer.bounds.size,
                                                                     previewSize: preview.size,
                                                                     isGridViewEnabled: tabSwitcherSettings.isGridViewEnabled)
        } else {
            imageView.frame = CGRect(origin: .zero, size: imageContainer.bounds.size)
        }
        imageView.image = preview

        if tabSwitcherSettings.isGridViewEnabled,
           let cell = tabSwitcherViewController.collectionView.cellForItem(at: IndexPath(row: rowIndex, section: 0)) as? TabViewGridCell {
            prepareGridChromeSnapshot(for: cell, initiallyVisible: true)
        } else if !tabSwitcherSettings.isGridViewEnabled,
                  let cell = tabSwitcherViewController.collectionView.cellForItem(at: IndexPath(row: rowIndex, section: 0)) as? TabViewListCell {
            prepareListChrome(for: cell, initiallyVisible: true)
        }
        
        if !tabSwitcherSettings.isGridViewEnabled {
            self.imageView.alpha = 0
        }
        
        scrollIfOutsideViewport(collectionView: tabSwitcherViewController.collectionView, rowIndex: rowIndex, attributes: layoutAttr)
        
        UIView.animateKeyframes(withDuration: TabSwitcherTransition.Constants.duration, delay: 0, options: .calculationModeLinear, animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
                let destinationFrame = mainViewController.viewCoordinator.contentContainer.frame
                self.setCardFrame(destinationFrame, cornerRadius: 0, shadowOpacity: 0)
                self.imageView.frame = WebViewTransitionGeometry.destinationImageFrame(for: webViewFrame.size,
                                                                                       previewSize: preview?.size)
                self.imageView.alpha = 1
                self.solidBackground.alpha = 1
                self.tabSwitcherViewController.view.alpha = 0
                if !self.tabSwitcherSettings.isGridViewEnabled {
                    self.applyListChromePose(isVisible: false)
                }
            }

            if self.tabSwitcherSettings.isGridViewEnabled {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.55) {
                    self.applyGridChromePose(
                        isVisible: false,
                        in: CGRect(origin: .zero, size: mainViewController.viewCoordinator.contentContainer.bounds.size))
                }
            }
        }, completion: { _ in
            self.removeTransitionViews()
            transitionContext.completeTransition(true)
        })
    }

}
