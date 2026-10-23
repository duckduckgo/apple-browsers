//
//  HomeScreenTransition.swift
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

protocol HomeScreenTransitionSource: AnyObject {
    var snapshotView: UIView { get }
    var rootContainerView: UIView { get }
}

class HomeScreenTransition: TabSwitcherTransition {
    
    fileprivate var homeScreenSnapshot: UIView?
    fileprivate var settingsButtonSnapshot: UIView?

    fileprivate var homeScreenSnapshotSourceSize: CGSize?

    fileprivate let tabSwitcherSettings: TabSwitcherSettings = DefaultTabSwitcherSettings()

    fileprivate func prepareSnapshots(with transitionSource: HomeScreenTransitionSource,
                                      transitionContext: UIViewControllerContextTransitioning,
                                      addressBarPosition: AddressBarPosition,
                                      addressBarHeight: CGFloat,
                                      isFloatingUIEnabled: Bool) {

        let viewToSnapshot = transitionSource.snapshotView
        let sourceBounds = isFloatingUIEnabled
            ? transitionSource.rootContainerView.bounds
            : adjustFrame(transitionSource.rootContainerView.bounds, forAddressBarPosition: addressBarPosition, byHeight: -addressBarHeight)
        let frameToSnapshot = transitionSource.rootContainerView.convert(sourceBounds, to: viewToSnapshot)

        if let snapshot = viewToSnapshot.resizableSnapshotView(from: frameToSnapshot,
                                                               afterScreenUpdates: false,
                                                               withCapInsets: .zero) {
            imageContainer.addSubview(snapshot)
            homeScreenSnapshotSourceSize = frameToSnapshot.size
            snapshot.frame = HomeScreenTransitionGeometry.snapshotFrame(for: frameToSnapshot.size,
                                                                        in: imageContainer.bounds,
                                                                        isGridViewEnabled: tabSwitcherSettings.isGridViewEnabled)
            homeScreenSnapshot = snapshot
        }
    }

    fileprivate func homeScreenSnapshotFrame(in containerBounds: CGRect, includesGridChrome: Bool = false) -> CGRect {
        let snapshotBounds: CGRect
        if tabSwitcherSettings.isGridViewEnabled, includesGridChrome {
            snapshotBounds = CGRect(
                x: TabViewGridCell.Constants.previewHorizontalInset / 2,
                y: TabViewGridCell.Constants.headerHeight,
                width: containerBounds.width - TabViewGridCell.Constants.previewHorizontalInset,
                height: containerBounds.height - TabViewGridCell.Constants.headerHeight - TabViewGridCell.Constants.previewBottomPadding)
        } else {
            snapshotBounds = containerBounds
        }
        return HomeScreenTransitionGeometry.snapshotFrame(
            for: homeScreenSnapshotSourceSize ?? .zero,
            in: snapshotBounds,
            isGridViewEnabled: tabSwitcherSettings.isGridViewEnabled)
    }

    fileprivate func tabSwitcherCellFrame(for attributes: UICollectionViewLayoutAttributes) -> CGRect {
        self.tabSwitcherViewController.collectionView.convert(attributes.frame,
                                                              to: self.tabSwitcherViewController.view)
    }
    
    fileprivate func previewFrame(for cellBounds: CGSize) -> CGRect {
        guard tabSwitcherSettings.isGridViewEnabled else {
            return CGRect(origin: .zero, size: cellBounds)
                .offsetBy(dx: 0, dy: -TabViewCell.Constants.previewPadding)
        }

        // Match TabViewGridCell.previewClipView / WebViewTransitionGeometry.previewFrame:
        // logo sits in the preview area below the cell header, not the full cell.
        let horizontalInset = TabViewGridCell.Constants.previewHorizontalInset / 2
        let availableWidth = cellBounds.width - TabViewGridCell.Constants.previewHorizontalInset
        let availableHeight = cellBounds.height
            - TabViewGridCell.Constants.headerHeight
            - TabViewGridCell.Constants.previewBottomPadding
        guard availableWidth > 0, availableHeight > 0 else {
            return CGRect(origin: .zero, size: cellBounds)
        }
        return CGRect(x: horizontalInset,
                      y: TabViewGridCell.Constants.headerHeight,
                      width: availableWidth,
                      height: availableHeight)
    }
    
}

class FromHomeScreenTransition: HomeScreenTransition {
    
    private let mainViewController: MainViewController
    
    init(mainViewController: MainViewController,
         tabSwitcherViewController: TabSwitcherViewController) {
        self.mainViewController = mainViewController

        super.init(tabSwitcherViewController: tabSwitcherViewController)
    }

    override func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        prepareSubviews(using: transitionContext)
        tabSwitcherViewController.view.alpha = 0
        transitionContext.containerView.insertSubview(tabSwitcherViewController.view, belowSubview: imageContainer)
        transitionContext.containerView.insertSubview(cardShadow, belowSubview: imageContainer)
        tabSwitcherViewController.view.frame = transitionContext.finalFrame(for: tabSwitcherViewController)
        tabSwitcherViewController.prepareForPresentation()
        
        guard let homeScreen = mainViewController.newTabPageViewController,
              let tab = mainViewController.tabManager.currentTabsModel.currentTab,
              let rowIndex = tabSwitcherViewController.tabsModel.indexOf(tab: tab),
              let layoutAttr = tabSwitcherViewController.collectionView.layoutAttributesForItem(at: IndexPath(row: rowIndex, section: 0))
        else {
            tabSwitcherViewController.view.alpha = 1
            removeTransitionViews()
            mainViewController.endTabSwitcherToolbarOwnership()
            transitionContext.completeTransition(true)
            return
        }

        let toolbar: BrowserToolbarView = mainViewController.viewCoordinator.toolbar
        let isFloating = mainViewController.isFloatingUIEnabled
        let duration = TabSwitcherTransition.duration(isFloatingUIEnabled: isFloating)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let toolbarSnapshot = installToolbarSnapshot(for: mainViewController,
                                                     transitionContext: transitionContext,
                                                     afterScreenUpdates: false)

        let theme = ThemeManager.shared.currentTheme

        let homeScreenFrame = homeScreen.view.convert(homeScreen.rootContainerView.frame, to: nil)
        solidBackground.frame = isFloating
            ? homeScreenFrame
            : adjustFrame(homeScreenFrame,
                          forAddressBarPosition: mainViewController.appSettings.currentAddressBarPosition,
                          byHeight: -mainViewController.omniBar.barView.expectedHeight)
        solidBackground.backgroundColor = theme.backgroundColor

        setCardFrame(solidBackground.frame, cornerRadius: 0, shadowOpacity: 0)
        imageContainer.backgroundColor = theme.backgroundColor
        
        prepareSnapshots(with: homeScreen,
                         transitionContext: transitionContext,
                         addressBarPosition: mainViewController.appSettings.currentAddressBarPosition,
                         addressBarHeight: mainViewController.omniBar.barView.expectedHeight,
                         isFloatingUIEnabled: isFloating)

        imageView.alpha = 0
        imageView.frame = imageContainer.bounds
        imageView.contentMode = .center
        if tabSwitcherSettings.isGridViewEnabled {
            imageView.image = TabViewCell.logoImage(for: tab)
            if let cell = tabSwitcherViewController.collectionView.cellForItem(at: IndexPath(row: rowIndex, section: 0)) as? TabViewGridCell {
                prepareGridChromeSnapshot(for: cell, initiallyVisible: false)
            }
        } else if let cell = tabSwitcherViewController.collectionView.cellForItem(at: IndexPath(row: rowIndex, section: 0)) as? TabViewListCell {
            prepareListChrome(for: cell, initiallyVisible: false)
        }
        
        UIView.animateKeyframes(withDuration: duration, delay: 0, options: .calculationModeLinear, animations: {
            
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                let containerFrame = self.tabSwitcherCellFrame(for: layoutAttr)
                self.setCardFrame(containerFrame,
                                  cornerRadius: TabViewCell.Constants.cellCornerRadius,
                                  shadowOpacity: 1)
                self.imageContainer.backgroundColor = UIColor(designSystemColor: .surfaceTertiary)
                self.imageView.frame = self.previewFrame(for: self.imageContainer.bounds.size)
                self.homeScreenSnapshot?.frame = self.homeScreenSnapshotFrame(
                    in: CGRect(origin: .zero, size: containerFrame.size),
                    includesGridChrome: true)
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

            // Slowly fade out to create a cross fade effect
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                self.homeScreenSnapshot?.alpha = 0
            }
            
            UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.7) {
                self.tabSwitcherViewController.view.alpha = 1
            }
            
            if self.tabSwitcherSettings.isGridViewEnabled {
                UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.3) {
                    self.imageView.alpha = 1
                    self.settingsButtonSnapshot?.alpha = 0
                }
            } else {
                UIView.addKeyframe(withRelativeStartTime: 0.7, relativeDuration: 0.3) {
                    // Fade card chrome with the snapshot so a blank rounded card
                    // does not linger over the list row.
                    self.imageContainer.alpha = 0
                    self.cardShadow.alpha = 0
                    self.cardBorder.alpha = 0
                    self.settingsButtonSnapshot?.alpha = 0
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
            self.settingsButtonSnapshot?.removeFromSuperview()
            toolbarSnapshot?.removeFromSuperview()
            if isFloating {
                toolbar.alpha = 0
                self.mainViewController.endTabSwitcherToolbarOwnership()
            }
            transitionContext.completeTransition(true)
        })
    }
}

class ToHomeScreenTransition: HomeScreenTransition {

    override func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        prepareSubviews(using: transitionContext)
        
        guard let mainViewController = transitionContext.viewController(forKey: .to) as? MainViewController,
              let homeScreen = mainViewController.newTabPageViewController,
              let tab = mainViewController.tabManager.currentTabsModel.currentTab,
              let rowIndex = tabSwitcherViewController.tabsModel.indexOf(tab: tab),
              let layoutAttr = tabSwitcherViewController.collectionView.layoutAttributesForItem(at: IndexPath(row: rowIndex, section: 0))
        else {
            // Layout attributes can be nil when a new tab was just added but the collection view
            // hasn't laid out its cell yet. Fall back to a simple crossfade to avoid a flash.
            if let mainViewController = transitionContext.viewController(forKey: .to) as? MainViewController {
                mainViewController.view.alpha = 1
                concealLiveFloatingToolbar(of: mainViewController)
            }
            let mainViewController = transitionContext.viewController(forKey: .to) as? MainViewController
            let isFloating = mainViewController?.isFloatingUIEnabled ?? false
            UIView.animate(withDuration: TabSwitcherTransition.duration(isFloatingUIEnabled: isFloating), animations: {
                self.tabSwitcherViewController.view.alpha = 0
            }, completion: { _ in
                self.removeTransitionViews()
                mainViewController?.revealFloatingToolbarAfterTabSwitcherTransition()
                transitionContext.completeTransition(true)
            })
            return
        }

        mainViewController.view.alpha = 1

        let isFloating = mainViewController.isFloatingUIEnabled
        let duration = TabSwitcherTransition.duration(isFloatingUIEnabled: isFloating)
        if isFloating {
            mainViewController.chromeManager.reset(animated: false)
            concealLiveFloatingToolbar(of: mainViewController)
        }

        let theme = ThemeManager.shared.currentTheme
        let initialContainerFrame = tabSwitcherCellFrame(for: layoutAttr)
        setCardFrame(initialContainerFrame,
                     cornerRadius: TabViewCell.Constants.cellCornerRadius,
                     shadowOpacity: 1)

        imageContainer.backgroundColor = theme.tabSwitcherCellBackgroundColor
        
        prepareSnapshots(with: homeScreen,
                         transitionContext: transitionContext,
                         addressBarPosition: mainViewController.appSettings.currentAddressBarPosition,
                         addressBarHeight: mainViewController.omniBar.barView.expectedHeight,
                         isFloatingUIEnabled: isFloating)
        homeScreenSnapshot?.frame = homeScreenSnapshotFrame(in: imageContainer.bounds, includesGridChrome: true)
        homeScreenSnapshot?.alpha = 0
        settingsButtonSnapshot?.alpha = 0
        
        imageView.frame = previewFrame(for: imageContainer.bounds.size)
        imageView.contentMode = .center
        if tabSwitcherSettings.isGridViewEnabled {
            imageView.image = TabViewCell.logoImage(for: tab)
            imageView.alpha = tab.viewed ? 1 : 0
            if let cell = tabSwitcherViewController.collectionView.cellForItem(at: IndexPath(row: rowIndex, section: 0)) as? TabViewGridCell {
                prepareGridChromeSnapshot(for: cell, initiallyVisible: true)
            }
        } else if let cell = tabSwitcherViewController.collectionView.cellForItem(at: IndexPath(row: rowIndex, section: 0)) as? TabViewListCell {
            prepareListChrome(for: cell, initiallyVisible: true)
        }
        imageView.backgroundColor = .clear

        scrollIfOutsideViewport(collectionView: tabSwitcherViewController.collectionView, rowIndex: rowIndex, attributes: layoutAttr)
        
        UIView.animateKeyframes(withDuration: duration, delay: 0, options: .calculationModeLinear, animations: {
            
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                let homeScreenFrame = homeScreen.view.convert(homeScreen.rootContainerView.frame, to: nil)
                let destinationFrame = isFloating
                    ? homeScreenFrame
                    : self.adjustFrame(homeScreenFrame,
                                       forAddressBarPosition: mainViewController.appSettings.currentAddressBarPosition,
                                       byHeight: -mainViewController.omniBar.barView.expectedHeight)
                self.setCardFrame(destinationFrame, cornerRadius: 0, shadowOpacity: 0)
                self.imageContainer.backgroundColor = theme.backgroundColor
                self.imageView.frame = CGRect(origin: .zero,
                                              size: self.imageContainer.bounds.size)
                self.homeScreenSnapshot?.frame = self.homeScreenSnapshotFrame(
                    in: CGRect(origin: .zero, size: destinationFrame.size))
                if !self.tabSwitcherSettings.isGridViewEnabled {
                    self.applyListChromePose(isVisible: false)
                }
            }

            if self.tabSwitcherSettings.isGridViewEnabled {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.55) {
                    let homeScreenFrame = homeScreen.view.convert(homeScreen.rootContainerView.frame, to: nil)
                    let destinationFrame = isFloating
                        ? homeScreenFrame
                        : self.adjustFrame(homeScreenFrame,
                                           forAddressBarPosition: mainViewController.appSettings.currentAddressBarPosition,
                                           byHeight: -mainViewController.omniBar.barView.expectedHeight)
                    self.applyGridChromePose(isVisible: false,
                                             in: CGRect(origin: .zero, size: destinationFrame.size))
                }
            }

            if tab.viewed {
                UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.3) {
                    self.imageView.alpha = 0
                    self.imageContainer.alpha = 1
                }
            }

            // Longer transition to create cross fade effect
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.8) {
                self.homeScreenSnapshot?.alpha = 1
                self.settingsButtonSnapshot?.alpha = 1
            }
            
            UIView.addKeyframe(withRelativeStartTime: 0.7, relativeDuration: 0.3) {
                self.tabSwitcherViewController.view.alpha = 0
            }

        }, completion: { _ in
            self.removeTransitionViews()
            self.settingsButtonSnapshot?.removeFromSuperview()
            mainViewController.revealFloatingToolbarAfterTabSwitcherTransition()
            transitionContext.completeTransition(true)
        })
    }
}
