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

    /// `UIView.animateKeyframes` only ever sees the *final* value set inside a keyframe block, so a
    /// bare `layer.cornerRadius = ...` there doesn't get the from/to pair it needs to interpolate --
    /// it just snaps at that keyframe's start. That made the growing/shrinking screenshot flash sharp
    /// corners the instant the transition began, jarring against the rounded card it was supposed to
    /// be continuous with. An explicit `CABasicAnimation` (independent of the keyframe machinery)
    /// animates it properly over the same span; the model-value assignment after `add(_:forKey:)`
    /// keeps the rest state correct once the animation is removed.
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

        // Floating UI's toolbar capsule sits outside `contentContainer`/the webview screenshot, so it
        // was never part of this transition -- it just sat there at full size until the tab switcher's
        // view opaquely covered it, reading as a sudden pop. Mirrors `ToWebViewTransition`'s reveal:
        // a snapshot, brought to the very front, shrinks + fades in one continuous animation over the
        // whole duration, rather than the real view (which sits *behind* `tabSwitcherViewController
        // .view` for this whole presentation) waiting for the switcher's own bars to arrive first --
        // see that transition's setup comment for why that produced a visible appear/disappear/
        // reappear gap. `isTabSwitcherTransitionOwningToolbar` still protects the real (now-hidden)
        // toolbar's alpha from every other code path that could otherwise write it mid-transition.
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
            // Legacy bottom chrome resizes `contentContainer` to sit above the omnibar, but at the
            // moment this frame is read it still measures the taller, pre-resize value, so this
            // compensates. Floating UI's `contentContainer` anchors behind the status bar instead (the
            // toolbar floats on top via obscured content insets, not a frame resize). Cropping the
            // top inset above matches the live page; applying this height compensation there shrank
            // the screenshot a few points shorter than the live webview. `ToWebViewTransition`'s
            // mirror image never applied this adjustment either.
            imageContainer.frame = adjustFrame(imageContainer.frame,
                                               forAddressBarPosition: mainViewController.appSettings.currentAddressBarPosition,
                                               byHeight: -mainViewController.omniBar.barView.expectedHeight)
        }
        // `imageView`'s aspect-fit frame doesn't necessarily cover 100% of `imageContainer`'s bounds
        // at every point along the shrink (its target sizing math differs at the tab-cell end versus
        // the full-webview end), so a plain background here shows through any sliver that's left over
        // instead of whatever dark content happened to be behind the container.
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
                // One continuous shrink + fade, the whole 0-100%, always on top -- see the setup
                // comment above for why this replaced a "wait for the real view" approach.
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
                // Toolbar stays hidden for the whole tab-switcher presentation (`ToWebViewTransition`
                // is what reveals it again); hand ownership back now that the snapshot is gone.
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

        // The tab coming into focus scales + fades the floating platter in. The real toolbar sits
        // *behind* `tabSwitcherViewController.view` for this whole presentation (`.overCurrentContext`
        // never removes `mainViewController.view` from the hierarchy, it just gets covered), so
        // revealing the real view directly meant it could only become visible once the switcher's own
        // bars had fully faded out of the way first -- a real gap between "old bar gone" and "new bar
        // visible" that read as the bar appearing, disappearing, then reappearing. A snapshot has no
        // such constraint: it's added straight to the transition's container and brought to the very
        // front, so it can animate once, continuously, the whole 0-100%, sitting on top of the
        // switcher's own chrome (and the growing page) the entire time instead of waiting for it.
        // `chromeManager.reset` first restores the toolbar's full resting shape (it can still be
        // scroll-collapsed from wherever the backgrounded tab was left), and `afterScreenUpdates: true`
        // makes sure the snapshot actually reflects that reset rather than whatever was last rendered
        // -- without both of those the snapshot could desync from the real toolbar's resting shape and
        // read as a doubled toolbar/tab-count/address-pill, which is why this was dropped once before;
        // both are still in place here.
        let toolbar: BrowserToolbarView = mainViewController.viewCoordinator.toolbar
        let isFloating = mainViewController.isFloatingUIEnabled
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        var toolbarSnapshot: UIView?
        if isFloating {
            mainViewController.chromeManager.reset(animated: false)
            mainViewController.isTabSwitcherTransitionOwningToolbar = true
            // Snapshot while the real toolbar is still fully visible (alpha 1) -- hiding it first
            // would capture a blank view, so the "animation" would just be an invisible view fading
            // into another invisible view, and the real toolbar would appear to pop to visible all
            // at once in the completion block below instead of animating in.
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
        // See `FromWebViewTransition`'s equivalent setup for why this matters: `imageView`'s
        // aspect-fit frame won't necessarily cover 100% of `imageContainer` at every point along the
        // grow, so a plain background here shows through any sliver instead of whatever dark content
        // happened to be behind the container (the tab switcher's own backdrop, in this direction).
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

            // Front-loaded: the whole card-grow/switcher-fade keeps its existing feel over 0-70%.
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.7) {
                self.tabSwitcherViewController.view.alpha = 0
            }

            if let toolbarSnapshot {
                // Still one continuous reveal, always on top (see the setup comment above), but
                // eased out rather than linear: the switcher's icons (dots/+/chat) and the real
                // toolbar's (back/forward/tab-count/menu) sit at different x-positions, so a linear
                // fade spends its whole first half as an illegible overlap of both, then resolves
                // into a clean bar right at the end -- which reads as a sudden pop even though the
                // alpha change itself is continuous. Front-loading the reveal (85% of the way there
                // by 60% of the duration) means it's already legible well before the end, so there's
                // nothing left to "pop" once the switcher's icons finish fading away underneath.
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
