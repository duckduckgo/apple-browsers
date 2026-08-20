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
            tabSwitcherViewController.view.alpha = 1
            transitionContext.completeTransition(true)
            return
        }

        let indexPath = IndexPath(row: rowIndex, section: 0)
        tabSwitcherViewController.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)

        guard let layoutAttr = tabSwitcherViewController.collectionView.layoutAttributesForItem(at: indexPath),
              let preview = tabSwitcherViewController.previewsSource.preview(for: tab)
        else {
            tabSwitcherViewController.view.alpha = 1
            transitionContext.completeTransition(true)
            return
        }

        let theme = ThemeManager.shared.currentTheme
        let webViewFrame = webView.convert(webView.bounds, to: nil)

        solidBackground.backgroundColor = theme.backgroundColor
        solidBackground.frame = webViewFrame

        // Floating UI's toolbar capsule sits outside `contentContainer`/the webview screenshot, so it
        // was never part of this transition -- it just sat there at full size until the tab switcher's
        // view opaquely covered it, reading as a sudden pop rather than a smooth exit. Animating the
        // *live* toolbar's alpha here would race against `tabSwitcherViewController.view`'s own
        // fade-in keyframe below -- the two compound and the toolbar visually vanishes well before
        // the fade either animation implies alone, before the screenshot even looks like it's
        // shrinking. Snapshotting it and animating the snapshot keeps this fully under this
        // transition's own timing, in step with the screenshot's shrink, matching how Safari shrinks
        // the whole page as one unit. Shrinks toward its own bottom edge (scaling around the default
        // centre anchor and translating back down by half the height lost pins the bottom edge in
        // place) while fading out.
        let toolbar: BrowserToolbarView = mainViewController.viewCoordinator.toolbar
        let isFloating = mainViewController.isFloatingUIEnabled
        var toolbarSnapshot: UIView?
        if isFloating, let snapshot = toolbar.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = toolbar.convert(toolbar.bounds, to: transitionContext.containerView)
            transitionContext.containerView.insertSubview(snapshot, aboveSubview: imageContainer)
            toolbarSnapshot = snapshot
            toolbar.alpha = 0
        }

        imageContainer.frame = mainViewController.viewCoordinator.contentContainer.frame
        imageContainer.frame = adjustFrame(imageContainer.frame,
                                           forAddressBarPosition: mainViewController.appSettings.currentAddressBarPosition,
                                           byHeight: -mainViewController.omniBar.barView.expectedHeight)
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

        UIView.animateKeyframes(withDuration: TabSwitcherTransition.Constants.duration, delay: 0, options: .calculationModeLinear, animations: {

            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                let containerFrame = self.tabSwitcherCellFrame(for: layoutAttr)
                self.imageContainer.frame = containerFrame
                self.imageContainer.layer.cornerRadius = TabViewCell.Constants.cellCornerRadius
                self.imageView.frame = WebViewTransitionGeometry.previewFrame(for: containerFrame.size,
                                                                              previewSize: preview.size,
                                                                              isGridViewEnabled: self.tabSwitcherSettings.isGridViewEnabled)
                if let toolbarSnapshot {
                    let scale: CGFloat = 0.7
                    let heightLost = toolbarSnapshot.bounds.height * (1 - scale) / 2
                    toolbarSnapshot.transform = CGAffineTransform(scaleX: scale, y: scale)
                        .concatenating(CGAffineTransform(translationX: 0, y: heightLost))
                    toolbarSnapshot.alpha = 0
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
            self.solidBackground.removeFromSuperview()
            self.imageContainer.removeFromSuperview()
            toolbarSnapshot?.removeFromSuperview()
            if isFloating {
                toolbar.alpha = 1
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
        let webViewFrame = webView.convert(webView.bounds, to: nil)
        mainViewController.view.alpha = 1

        // Reverse of `FromWebViewTransition`'s shrink, same reasoning: animating the *live* toolbar's
        // alpha here would compound with `tabSwitcherViewController.view`'s own fade-out in the same
        // block below, so a snapshot carries the reveal instead, self-contained regardless of
        // whatever state the toolbar was left in (e.g. a fresh presentation, not just the matching
        // `FromWebViewTransition`). Starts in that same shrunk/faded state, then animates back to
        // identity alongside the webview screenshot growing back to full size.
        let toolbar: BrowserToolbarView = mainViewController.viewCoordinator.toolbar
        let isFloating = mainViewController.isFloatingUIEnabled
        var toolbarSnapshot: UIView?
        if isFloating, let snapshot = toolbar.snapshotView(afterScreenUpdates: false) {
            let scale: CGFloat = 0.7
            let heightLost = toolbar.bounds.height * (1 - scale) / 2
            snapshot.frame = toolbar.convert(toolbar.bounds, to: transitionContext.containerView)
            snapshot.transform = CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: 0, y: heightLost))
            snapshot.alpha = 0
            transitionContext.containerView.insertSubview(snapshot, aboveSubview: imageContainer)
            toolbarSnapshot = snapshot
            toolbar.alpha = 0
        }

        solidBackground.backgroundColor = theme.backgroundColor
        solidBackground.frame = webView.bounds
        // Put overlay above webview to hide its content till the end of the transition
        solidBackground.removeFromSuperview()
        webView.addSubview(solidBackground)
        
        imageContainer.frame = tabSwitcherCellFrame(for: layoutAttr)
        imageContainer.layer.cornerRadius = TabViewCell.Constants.cellCornerRadius
        
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
        
        UIView.animate(withDuration: TabSwitcherTransition.Constants.duration, animations: {
            self.imageContainer.frame = mainViewController.viewCoordinator.contentContainer.frame
            self.imageContainer.layer.cornerRadius = 0

            self.imageView.frame = WebViewTransitionGeometry.destinationImageFrame(for: webViewFrame.size,
                                                                                   previewSize: preview?.size)
            self.imageView.alpha = 1

            self.solidBackground.alpha = 1
            self.tabSwitcherViewController.view.alpha = 0
            if let toolbarSnapshot {
                toolbarSnapshot.transform = .identity
                toolbarSnapshot.alpha = 1
            }
        }, completion: { _ in
            self.solidBackground.removeFromSuperview()
            self.imageContainer.removeFromSuperview()
            toolbarSnapshot?.removeFromSuperview()
            if isFloating {
                toolbar.alpha = 1
            }
            transitionContext.completeTransition(true)
        })
    }

}
