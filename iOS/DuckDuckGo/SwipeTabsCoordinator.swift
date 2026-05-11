//
//  SwipeTabsCoordinator.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import os.log

class SwipeTabsCoordinator: NSObject {
    
    static let tabGap: CGFloat = 10
    
    // Set by refresh function
    weak var tabsModel: TabsModelManaging!
    
    weak var coordinator: MainViewCoordinator!
    weak var tabPreviewsSource: TabPreviewsSource!
    weak var appSettings: AppSettings!
    private let omnibarDependencies: OmnibarDependencyProvider

    let selectTab: (Tab) -> Void
    let newTab: () -> Void
    let onSwipeStarted: () -> Void
    
    let feedbackGenerator: UISelectionFeedbackGenerator = {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        return generator
    }()
    
    var isEnabled = false {
        didSet {
            if !isEnabled {
                state = .idle
            }
            updateLayout()
            collectionView.reloadData()
        }
    }
    
    var collectionView: MainViewFactory.NavigationBarCollectionView {
        coordinator.navigationBarCollectionView
    }

    init(coordinator: MainViewCoordinator,
         tabPreviewsSource: TabPreviewsSource,
         appSettings: AppSettings,
         omnibarDependencies: OmnibarDependencyProvider,
         selectTab: @escaping (Tab) -> Void,
         newTab: @escaping () -> Void,
         onSwipeStarted: @escaping () -> Void) {
        
        self.coordinator = coordinator
        self.tabPreviewsSource = tabPreviewsSource
        self.appSettings = appSettings
        self.omnibarDependencies = omnibarDependencies
        self.selectTab = selectTab
        self.newTab = newTab
        self.onSwipeStarted = onSwipeStarted
                
        super.init()
        
        collectionView.register(OmniBarCell.self, forCellWithReuseIdentifier: Constant.omniBarReuseIdentifier)
        collectionView.register(OmniBarCell.self, forCellWithReuseIdentifier: Constant.templateReuseIdentifier)
        collectionView.isPagingEnabled = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.decelerationRate = .fast
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false

        updateLayout()
    }
    
    enum State {
        
        case idle
        case starting(CGPoint)
        case swiping(CGPoint, FloatingPointSign)
        
        var isIdle: Bool {
            if case .idle = self {
                return true
            }

            return false
        }

    }
    
    var state: State = .idle {
        didSet {
            Logger.swipeTabs.debug("state: \(String(describing: oldValue)) → \(String(describing: self.state))")
        }
    }

    /// Tracks the contentOffset when an external pan (driven by a gesture on a view that overlays
    /// the collection view, e.g. the Unified Toggle Input bar) begins, so `.changed` translations
    /// resolve to an absolute offset.
    private var externalPanStartOffset: CGPoint = .zero

    /// Chrome views (e.g. UTI bar overlay, AI tab header) that should slide horizontally in
    /// lockstep with `currentView` during an external pan. At swipe start we snapshot each
    /// visible view via `snapshotView(afterScreenUpdates:)` (captures glass effects, shadows,
    /// and child layouts as a single flat image), hide the originals, and slide the snapshots.
    /// Sliding the *live* views was visually broken — `UIVisualEffectView` blur can't
    /// recompute mid-translation, so the iOS 26 glass pills rendered as flat dark rectangles,
    /// and the nested cardView / shadow views read as "stacked screens." Cell-based legacy
    /// swipes don't need this: the omnibar is inside the collection view's scroll, so it
    /// tracks naturally.
    var auxiliarySwipeViews: [UIView] = [] {
        didSet {
            Logger.swipeTabs.debug("auxiliarySwipeViews set: count=\(self.auxiliarySwipeViews.count) \(self.auxiliarySwipeViews.map { "\(type(of: $0))(hidden=\($0.isHidden))" }.joined(separator: ", "))")
        }
    }

    /// Active snapshot views of `auxiliarySwipeViews` during a swipe, parked in the superview
    /// so they ignore the source view's clipping / hierarchy. Reset by `cleanUpViews`.
    private var auxiliarySwipeViewSnapshots: [UIView] = []

    /// Tracks which auxiliary views we hid (alpha=0) at swipe start so we can restore them on
    /// cleanup — we can't blanket-restore everyone in the array because some originals were
    /// already hidden (e.g. AI header on a regular tab) and shouldn't reappear.
    private var hiddenAuxiliaryOriginals: [UIView] = []

    weak var preview: UIView?
    weak var currentView: UIView?

    /// Off-screen snapshot of the destination tab's chrome (omnibar / AI header) that slides in
    /// from the lead edge alongside the webview preview. Built only when crossing the
    /// AI↔regular boundary, where the destination's chrome lives at a different position than
    /// the outgoing one — without this the destination chrome would pop into place after the
    /// swipe settles. For regular↔regular swipes the legacy cell-based omnibar already slides
    /// naturally, so we skip the facade.
    weak var chromePreview: UIView?

    /// Pixel-perfect cached snapshots of the real AI chrome views (header + UTI bar), captured
    /// via `drawHierarchy` while they're actually rendered to the window. We can't rebuild
    /// these from scratch with `layer.render` because the pill containers use
    /// `UIVisualEffectView` (iOS 26 glass) and the pills carry shadows — both of which
    /// `layer.render(in:)` ignores. Captured by the host when a Duck.ai tab refreshes.
    var cachedAIHeaderSnapshot: UIImage?
    var cachedAIUTIBarSnapshot: UIImage?

    private var omniBarHeight: CGFloat {
        DefaultOmniBarView.expectedHeight
    }

    func invalidateLayout() {
        updateLayout()
        scrollToCurrent()

        collectionView.reloadData()
        collectionView.layoutIfNeeded()
    }

    private func updateLayout() {
        let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
        layout?.itemSize = CGSize(width: coordinator.superview.frame.size.width, height: omniBarHeight)
        layout?.minimumLineSpacing = 0
        layout?.minimumInteritemSpacing = 0
        layout?.scrollDirection = .horizontal
        layout?.invalidateLayout()
    }

    private func scrollToCurrent() {
        guard isEnabled, let index = tabsModel.currentIndex else { return }
        let targetOffset = collectionView.frame.width * CGFloat(index)

        guard targetOffset != collectionView.contentOffset.x else {
            return
        }
        
        let indexPath = IndexPath(row: index, section: 0)
        guard indexPath.row < collectionView.numberOfItems(inSection: 0) else {
            assertionFailure("target row is equal to or greater than the number of items in the collection view")
            return
        }
        self.collectionView.scrollToItem(at: indexPath,
                                         at: .centeredHorizontally,
                                         animated: false)
    }

    private struct Constant {
        static let omniBarReuseIdentifier = "omniBar"
        static let templateReuseIdentifier = "template"
    }
}

// MARK: UICollectionViewDelegate
extension SwipeTabsCoordinator: UICollectionViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {

        switch state {
        case .idle: break

        case .starting(let startPosition):
            let offset = startPosition.x - scrollView.contentOffset.x
            Logger.swipeTabs.debug("scrollViewDidScroll[.starting]: startX=\(startPosition.x) currentX=\(scrollView.contentOffset.x) offset=\(offset)")
            prepareCurrentView()
            preparePreview(offset)
            prepareAuxiliarySwipeSnapshots()
            state = .swiping(startPosition, offset.sign)
            onSwipeStarted()

        case .swiping(let startPosition, let sign):
            let offset = startPosition.x - scrollView.contentOffset.x
            if offset.sign == sign {
                let modifier = sign == .plus ? -1.0 : 1.0
                swipePreviewProportionally(offset: offset, modifier: modifier)
                swipeChromePreviewProportionally(offset: offset, modifier: modifier)
                swipeCurrentViewProportionally(offset: offset)
                currentView?.transform.tx = offset
                for snapshot in auxiliarySwipeViewSnapshots {
                    snapshot.transform.tx = offset
                }
            } else {
                Logger.swipeTabs.debug("scrollViewDidScroll[.swiping]: sign flipped (\(String(describing: sign)) → \(String(describing: offset.sign))), restarting")
                cleanUpViews()
                state = .starting(startPosition)
            }
        }
    }

    /// Snapshots each visible auxiliary chrome view into a flat image view, parks the snapshot
    /// in the superview at the original's screen position, and hides the original (alpha=0)
    /// so the snapshot is the only thing the user sees. This sidesteps the live-translation
    /// issues with `UIVisualEffectView` glass + drop shadows + nested cardViews.
    private func prepareAuxiliarySwipeSnapshots() {
        // Defensive: should already be empty (cleanUpViews resets), but if a prior swipe was
        // interrupted mid-flight, restore + clear before starting fresh.
        teardownAuxiliarySwipeSnapshots()

        for view in auxiliarySwipeViews {
            guard !view.isHidden, view.bounds.width > 0, view.bounds.height > 0 else {
                Logger.swipeTabs.debug("prepareAuxiliarySwipeSnapshots: skip \(type(of: view)) — hidden or zero-sized")
                continue
            }
            guard let snapshot = view.snapshotView(afterScreenUpdates: false) else {
                Logger.swipeTabs.error("prepareAuxiliarySwipeSnapshots: snapshotView returned nil for \(type(of: view))")
                continue
            }

            // Convert the original's frame into the superview's coordinate space — auxiliary
            // views live as descendants (e.g. unifiedToggleInputContainer is inside
            // navigationBarContainer), so their `.frame` is in their parent's coords, not the
            // root's.
            let frameInSuperview = view.convert(view.bounds, to: coordinator.superview)
            snapshot.frame = frameInSuperview
            coordinator.superview.addSubview(snapshot)
            auxiliarySwipeViewSnapshots.append(snapshot)

            view.alpha = 0
            hiddenAuxiliaryOriginals.append(view)
        }
        Logger.swipeTabs.debug("prepareAuxiliarySwipeSnapshots: created \(self.auxiliarySwipeViewSnapshots.count) snapshots")
    }

    private func teardownAuxiliarySwipeSnapshots() {
        for snapshot in auxiliarySwipeViewSnapshots {
            snapshot.removeFromSuperview()
        }
        auxiliarySwipeViewSnapshots = []
        for original in hiddenAuxiliaryOriginals {
            original.alpha = 1
        }
        hiddenAuxiliaryOriginals = []
    }
    
    private func swipeCurrentViewProportionally(offset: CGFloat) {
        currentView?.transform.tx = offset
    }
    
    private func swipePreviewProportionally(offset: CGFloat, modifier: CGFloat) {
        let width = coordinator.contentContainer.frame.width
        let percent = offset / width
        let swipeWidth = width + Self.tabGap
        let x = (swipeWidth * percent) + (Self.tabGap * modifier)
        preview?.transform.tx = x
    }
    
    private func prepareCurrentView() {

        if !coordinator.logoContainer.isHidden {
            currentView = coordinator.logoContainer
            Logger.swipeTabs.debug("prepareCurrentView: logoContainer (NTP)")
        } else {
            currentView = coordinator.contentContainer.subviews.last
            Logger.swipeTabs.debug("prepareCurrentView: contentContainer.last=\(String(describing: self.currentView.map { type(of: $0) }))")
        }
    }

    private func preparePreview(_ offset: CGFloat) {
        guard let index = tabsModel.currentIndex else {
            Logger.swipeTabs.debug("preparePreview: bailing — no currentIndex")
            return
        }
        let modifier = (offset > 0 ? -1 : 1)
        let nextIndex = index + modifier

        guard tabsModel.tabs.indices.contains(nextIndex) || tabsModel.tabs.last?.link != nil else {
            Logger.swipeTabs.debug("preparePreview: bailing — nextIndex=\(nextIndex) out of range and no \"new tab\" slot")
            return
        }

        let targetSize = coordinator.contentContainer.frame.size
        var height = targetSize.height

        let tab = tabsModel.get(tabAt: nextIndex)
        let isAITab = tab?.isAITab == true
        let hasLink = tab?.link != nil
        Logger.swipeTabs.debug("preparePreview: currentIndex=\(index) nextIndex=\(nextIndex) modifier=\(modifier) isAITab=\(isAITab) hasLink=\(hasLink) contentContainer=\(String(describing: targetSize))")

        if let tab, let image = tabPreviewsSource.preview(for: tab) {
            Logger.swipeTabs.debug("preparePreview: using cached preview image \(String(describing: image.size))")
            createPreviewFromImage(image)
            if appSettings.currentAddressBarPosition.isBottom,
               tab.link != nil,
               let collectionView = coordinator.navigationBarContainer.subviews.first as? UICollectionView {
                // Adjust the preview height to account for the omnibar at the bottom
                // When the omnibar is at the bottom, the webview content extends underneath it
                // We need to subtract the omnibar height from the total height to get the visible content area
                // Note: We use the collectionView's height directly instead of navigationBarContainer.height
                // because the container height can change when the keyboard appears
                height = targetSize.height - collectionView.frame.size.height
                Logger.swipeTabs.debug("preparePreview: bottom-bar height correction applied, navBarCollection.h=\(collectionView.frame.size.height) finalPreviewH=\(height)")
            }
            preview?.frame = CGRect(x: 0, y: 0, width: targetSize.width, height: height)
        } else if tab?.link == nil {
            Logger.swipeTabs.debug("preparePreview: no image and no link — snapshotting logo container")
            let targetFrame = CGRect(origin: .zero, size: coordinator.contentContainer.frame.size)
            createPreviewFromLogoContainerWithSize(targetFrame.size)
            preview?.frame = targetFrame
        } else {
            Logger.swipeTabs.debug("preparePreview: tab=\(String(describing: tab?.uid)) has link but no cached preview image; no preview shown")
        }

        preview?.frame.origin.x = coordinator.contentContainer.frame.width * CGFloat(modifier)
        Logger.swipeTabs.debug("preparePreview: final preview frame=\(self.preview.map { String(describing: $0.frame) } ?? "nil")")

        prepareChromePreview(modifier: modifier, destinationTab: tab)
    }

    /// Builds an off-screen full-screen facade of the destination tab's chrome so it slides in
    /// alongside the webview preview when the AI↔regular boundary is crossed. The cell-based
    /// legacy path already animates the omnibar for regular↔regular swipes, so we only act on
    /// boundary crossings.
    ///
    /// The facade is a full-screen `UIView` that hosts the destination's chrome elements at
    /// their absolute screen positions (regular omnibar at top OR bottom; AI tab = header at
    /// top + UTI bar at bottom). The container is parked one full screen off the lead edge and
    /// translated via `transform.tx` proportional to the swipe progress — same math as the
    /// webview preview, applied to the screen width.
    private func prepareChromePreview(modifier: Int, destinationTab: Tab?) {
        chromePreview?.removeFromSuperview()
        chromePreview = nil

        guard let destinationTab else {
            Logger.swipeTabs.debug("prepareChromePreview: skip — no destination tab")
            return
        }

        let currentTab = tabsModel.currentIndex.flatMap { tabsModel.get(tabAt: $0) }
        let currentIsAI = currentTab?.isAITab == true
        let destinationIsAI = destinationTab.isAITab

        guard currentIsAI != destinationIsAI else {
            Logger.swipeTabs.debug("prepareChromePreview: skip — both \(destinationIsAI ? "AI" : "regular"), no boundary crossing")
            return
        }

        let superview = coordinator.superview
        let container = UIView(frame: CGRect(
            x: CGFloat(modifier) * superview.bounds.width,
            y: 0,
            width: superview.bounds.width,
            height: superview.bounds.height
        ))
        container.isUserInteractionEnabled = false
        container.backgroundColor = .clear

        if destinationIsAI {
            // AI destination: header at top + UTI bar at bottom. Snapshot the existing chrome
            // containers — they're already configured (from a previous AI-tab visit, or initial
            // setup) and `layer.render` captures their layer contents even when hidden.
            if let aiHeader = makeAIHeaderSnapshotForAITabDestination() {
                container.addSubview(aiHeader)
            }
            if let utiBar = makeUTIBarSnapshotForAITabDestination() {
                container.addSubview(utiBar)
            }
            Logger.swipeTabs.debug("prepareChromePreview: AI destination facade subviews=\(container.subviews.count) frame=\(String(describing: container.frame))")
        } else {
            // Regular destination: template omnibar at the user's preferred address-bar
            // position. Rendered fresh because the destination's omnibar isn't currently
            // mounted (we're on an AI tab whose collection-view cells are alpha=0).
            if let omnibar = makeRegularOmnibarSnapshot(for: destinationTab) {
                omnibar.frame = CGRect(
                    x: 0,
                    y: regularChromePreviewYPosition(),
                    width: superview.bounds.width,
                    height: DefaultOmniBarView.expectedHeight
                )
                container.addSubview(omnibar)
            }
            Logger.swipeTabs.debug("prepareChromePreview: regular destination facade subviews=\(container.subviews.count) frame=\(String(describing: container.frame)) for destinationTab uid=\(destinationTab.uid)")
        }

        superview.addSubview(container)
        chromePreview = container
    }

    /// Y-coordinate (in `superview`'s coordinate space) where the destination regular tab's
    /// omnibar will live after the swipe settles — tracks the user's address-bar position
    /// preference, factoring in safe area and toolbar.
    private func regularChromePreviewYPosition() -> CGFloat {
        let superview = coordinator.superview
        let insets = superview.safeAreaInsets
        if appSettings.currentAddressBarPosition.isBottom {
            let toolbarHeight = coordinator.toolbar.isHidden ? 0 : coordinator.toolbar.bounds.height
            return superview.bounds.height - insets.bottom - toolbarHeight - DefaultOmniBarView.expectedHeight
        } else {
            return insets.top
        }
    }

    /// Renders a configured template omnibar for the given tab into an image, returned as an
    /// `UIImageView` sized to the omnibar. Mirrors the cell-template configuration in
    /// `collectionView(_:cellForItemAt:)` so the facade visual matches the real omnibar that
    /// will appear post-settle.
    private func makeRegularOmnibarSnapshot(for tab: Tab) -> UIView? {
        let controller = OmniBarFactory.createOmniBarViewController(with: omnibarDependencies)
        controller.showSeparator()
        controller.adjust(for: appSettings.currentAddressBarPosition)
        controller.configureForSwipeTemplate(
            isExpandedPhone: coordinator.omniBar.isExpandedPhone,
            tabCount: tabsModel.count
        )

        let url = tab.link?.url
        if tab.isAITab {
            controller.enterAIChatMode()
        } else if let url {
            controller.startBrowsing()
            controller.resetPrivacyIcon(for: url)
        } else {
            controller.stopBrowsing()
        }
        controller.refreshText(forUrl: url, forceFullURL: appSettings.showFullSiteAddress)
        controller.refreshFireMode(fireMode: tab.fireTab)

        let barView = controller.barView
        let width = coordinator.superview.bounds.width
        let height = DefaultOmniBarView.expectedHeight

        // Force the view through a layout pass at the target size — without this `layer.render`
        // captures the view at its intrinsic / zero size.
        barView.translatesAutoresizingMaskIntoConstraints = true
        barView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        barView.setNeedsLayout()
        barView.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: barView.bounds.size)
        let image = renderer.image { context in
            barView.layer.render(in: context.cgContext)
        }
        return UIImageView(image: image)
    }

    /// Returns the cached AI tab header snapshot — captured live by `drawHierarchy` while the
    /// header was rendered to the window, so it includes the iOS 26 glass-pill effects and
    /// shadows that `CALayer.render` can't reproduce. Built fresh views lose those entirely
    /// (the pills go flat), so we trade a frame of staleness for visual fidelity.
    private func makeAIHeaderSnapshotForAITabDestination() -> UIView? {
        guard let image = cachedAIHeaderSnapshot else {
            Logger.swipeTabs.debug("makeAIHeaderSnapshotForAITabDestination: no cached snapshot (user has not been on Duck.ai yet this session)")
            return nil
        }
        let imageView = UIImageView(image: image)
        imageView.frame = CGRect(
            x: 0,
            y: coordinator.superview.safeAreaInsets.top,
            width: image.size.width,
            height: image.size.height
        )
        return imageView
    }

    /// Returns the cached UTI bar snapshot — same trade-off as the header: `drawHierarchy`
    /// catches the live shadows / blur, `layer.render` doesn't.
    private func makeUTIBarSnapshotForAITabDestination() -> UIView? {
        guard let image = cachedAIUTIBarSnapshot else {
            Logger.swipeTabs.debug("makeUTIBarSnapshotForAITabDestination: no cached snapshot")
            return nil
        }
        let imageView = UIImageView(image: image)
        let yPosition = coordinator.superview.bounds.height - coordinator.superview.safeAreaInsets.bottom - image.size.height
        imageView.frame = CGRect(x: 0, y: yPosition, width: image.size.width, height: image.size.height)
        return imageView
    }

    /// Mirrors `swipePreviewProportionally`'s math so the chrome facade slides in lockstep with
    /// the webview preview — same tab-gap treatment, just applied to the screen width since the
    /// chrome lives outside `contentContainer`.
    private func swipeChromePreviewProportionally(offset: CGFloat, modifier: CGFloat) {
        guard let chromePreview else { return }
        let width = coordinator.superview.bounds.width
        let percent = offset / width
        let swipeWidth = width + Self.tabGap
        let x = (swipeWidth * percent) + (Self.tabGap * modifier)
        chromePreview.transform.tx = x
    }

    private func createPreviewFromImage(_ image: UIImage) {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        coordinator.contentContainer.addSubview(imageView)
        preview = imageView
        Logger.swipeTabs.debug("createPreviewFromImage: added UIImageView to contentContainer")
    }

    private func createPreviewFromLogoContainerWithSize(_ size: CGSize) {
        let origin = coordinator.contentContainer.convert(CGPoint.zero, to: coordinator.logoContainer)
        let snapshotFrame = CGRect(origin: origin, size: size)
        let isHidden = coordinator.logoContainer.isHidden
        coordinator.logoContainer.isHidden = false
        if let snapshotView = coordinator.logoContainer.resizableSnapshotView(from: snapshotFrame,
                                                                              afterScreenUpdates: true,
                                                                              withCapInsets: .zero) {
            coordinator.contentContainer.addSubview(snapshotView)
            preview = snapshotView
            Logger.swipeTabs.debug("createPreviewFromLogoContainerWithSize: added snapshot view")
        } else {
            Logger.swipeTabs.error("createPreviewFromLogoContainerWithSize: snapshot returned nil")
        }
        coordinator.logoContainer.isHidden = isHidden
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        Logger.swipeTabs.debug("scrollViewWillBeginDragging: state=\(String(describing: self.state)) contentOffset=\(String(describing: scrollView.contentOffset))")
        switch state {
        case .idle:
            state = .starting(scrollView.contentOffset)

        default: break
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        Logger.swipeTabs.debug("scrollViewDidEndDecelerating: state=\(String(describing: self.state)) contentOffset=\(String(describing: scrollView.contentOffset))")
        guard !state.isIdle else {
            Logger.swipeTabs.debug("scrollViewDidEndDecelerating: bailing — state idle")
            return
        }

        defer {
            cleanUpViews()
            state = .idle
        }

        let point = CGPoint(x: coordinator.navigationBarCollectionView.bounds.midX,
                            y: coordinator.navigationBarCollectionView.bounds.midY)

        guard let index = coordinator.navigationBarCollectionView.indexPathForItem(at: point)?.row else {
            Logger.swipeTabs.error("scrollViewDidEndDecelerating: no index at midpoint \(String(describing: point)) — collection numItems=\(self.coordinator.navigationBarCollectionView.numberOfItems(inSection: 0))")
            assertionFailure("invalid index")
            return
        }
        feedbackGenerator.selectionChanged()
        if index >= tabsModel.count {
            Logger.swipeTabs.debug("scrollViewDidEndDecelerating: target index=\(index) is past last tab — newTab()")
            newTab()
        } else {
            if let tab = tabsModel.get(tabAt: index) {
                Logger.swipeTabs.debug("scrollViewDidEndDecelerating: selectTab index=\(index) isAITab=\(tab.isAITab) hasLink=\(tab.link != nil)")
                selectTab(tab)
            } else {
                Logger.swipeTabs.error("scrollViewDidEndDecelerating: tabsModel.get(\(index)) returned nil")
            }
        }
    }

    private func cleanUpViews() {
        Logger.swipeTabs.debug("cleanUpViews: currentView=\(String(describing: self.currentView.map { type(of: $0) })) preview=\(self.preview != nil) chromePreview=\(self.chromePreview != nil) auxSnapshots=\(self.auxiliarySwipeViewSnapshots.count)")
        currentView?.transform = .identity
        currentView = nil
        preview?.removeFromSuperview()
        chromePreview?.removeFromSuperview()
        chromePreview = nil
        teardownAuxiliarySwipeSnapshots()
    }

}

// MARK: Public Interface
extension SwipeTabsCoordinator {

    func refresh(tabsModel: TabsModelManaging, scrollToSelected: Bool = false) {
        self.tabsModel = tabsModel
        coordinator.navigationBarCollectionView.reloadData()
        
        updateLayout()
        
        if scrollToSelected {
            scrollToCurrent()
        }
    }
    
    /// Captures pixel-perfect images of the AI chrome (header + UTI bar) using `drawHierarchy`
    /// while they're rendered to a window. Called by the host whenever the AI chrome refreshes
    /// so the cache stays current with subscription state, model, etc. Skips views that are
    /// currently hidden or unsized — the cache then represents the most recent valid render.
    func captureAIChromeSnapshotsIfPossible() {
        if let header = coordinator.aiChatTabChatHeaderContainer,
           !header.isHidden,
           header.bounds.width > 0, header.bounds.height > 0 {
            let renderer = UIGraphicsImageRenderer(size: header.bounds.size)
            cachedAIHeaderSnapshot = renderer.image { _ in
                header.drawHierarchy(in: header.bounds, afterScreenUpdates: false)
            }
            Logger.swipeTabs.debug("captureAIChromeSnapshotsIfPossible: header captured size=\(String(describing: header.bounds.size))")
        } else {
            Logger.swipeTabs.debug("captureAIChromeSnapshotsIfPossible: header skipped — hidden or zero-sized")
        }

        if let uti = coordinator.unifiedToggleInputContainer,
           !uti.isHidden,
           uti.bounds.width > 0, uti.bounds.height > 0 {
            let renderer = UIGraphicsImageRenderer(size: uti.bounds.size)
            cachedAIUTIBarSnapshot = renderer.image { _ in
                uti.drawHierarchy(in: uti.bounds, afterScreenUpdates: false)
            }
            Logger.swipeTabs.debug("captureAIChromeSnapshotsIfPossible: uti bar captured size=\(String(describing: uti.bounds.size))")
        } else {
            Logger.swipeTabs.debug("captureAIChromeSnapshotsIfPossible: uti bar skipped — hidden or zero-sized")
        }
    }

    func addressBarPositionChanged(isTop: Bool) {
        if isTop {
            collectionView.horizontalScrollIndicatorInsets.bottom = -1.5
            collectionView.hitTestInsets.top = -12
            collectionView.hitTestInsets.bottom = 0
        } else {
            collectionView.horizontalScrollIndicatorInsets.bottom = collectionView.frame.height - 7.5
            collectionView.hitTestInsets.top = 0
            collectionView.hitTestInsets.bottom = -12
        }
    }

    /// Drives the swipe-tabs state machine from a pan gesture attached to a view that overlays
    /// the navigation-bar collection view (e.g. the Unified Toggle Input bar or the AI tab
    /// header), where touches don't reach the collection view's own pan recognizer. Scrubs
    /// `contentOffset` so the existing `scrollViewDidScroll` path animates the preview and
    /// current view; snaps to the closest page on release and routes through
    /// `scrollViewDidEndDecelerating` to select the destination tab.
    func handleExternalPan(_ gesture: UIPanGestureRecognizer) {
        guard isEnabled, let panView = gesture.view else {
            Logger.swipeTabs.debug("handleExternalPan: bailing — isEnabled=\(self.isEnabled) panView=\(gesture.view != nil)")
            return
        }

        switch gesture.state {
        case .began:
            // A prior external pan's settling animation can still be in flight, or another
            // attached recognizer (UTI bar / AI header) may have left non-idle state behind.
            // Reset before starting so `scrollViewWillBeginDragging` (which only transitions
            // from `.idle`) actually arms the state machine for this gesture.
            Logger.swipeTabs.debug("handleExternalPan[.began]: source=\(type(of: panView)) contentOffset=\(String(describing: self.collectionView.contentOffset))")
            collectionView.layer.removeAllAnimations()
            cleanUpViews()
            state = .idle
            externalPanStartOffset = collectionView.contentOffset
            scrollViewWillBeginDragging(collectionView)

        case .changed:
            let translation = gesture.translation(in: panView).x
            let pageWidth = collectionView.frame.width
            let proposedX = externalPanStartOffset.x - translation
            let maxX = max(collectionView.contentSize.width - pageWidth, 0)
            collectionView.contentOffset = CGPoint(x: max(0, min(proposedX, maxX)), y: 0)

        case .ended, .cancelled, .failed:
            let pageWidth = collectionView.frame.width
            guard pageWidth > 0 else {
                Logger.swipeTabs.error("handleExternalPan[.ended]: pageWidth=0 — selecting current")
                scrollViewDidEndDecelerating(collectionView)
                return
            }

            let translation = gesture.translation(in: panView).x
            let velocity = gesture.velocity(in: panView).x
            let totalPages = collectionView.numberOfItems(inSection: 0)
            let currentPage = Int((externalPanStartOffset.x / pageWidth).rounded())

            // Velocity wins over distance: a flick past the threshold commits to next/prev even
            // if the user barely moved. Otherwise fall back to a half-page distance rule, so a
            // slow drag still snaps back unless it crossed the midpoint.
            let velocityThreshold: CGFloat = 300
            let distanceThreshold = pageWidth / 2
            var targetPage = currentPage
            if abs(velocity) > velocityThreshold {
                targetPage += velocity < 0 ? 1 : -1
            } else if abs(translation) > distanceThreshold {
                targetPage += translation < 0 ? 1 : -1
            }
            targetPage = max(0, min(targetPage, max(totalPages - 1, 0)))

            let targetOffset = CGPoint(x: CGFloat(targetPage) * pageWidth, y: 0)
            Logger.swipeTabs.debug("handleExternalPan[.\(String(describing: gesture.state))]: translation=\(translation) velocity=\(velocity) currentPage=\(currentPage) → targetPage=\(targetPage) (of \(totalPages)) targetOffset=\(String(describing: targetOffset))")
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
                self.collectionView.contentOffset = targetOffset
            }, completion: { _ in
                Logger.swipeTabs.debug("handleExternalPan: settle animation complete, dispatching to scrollViewDidEndDecelerating")
                self.scrollViewDidEndDecelerating(self.collectionView)
            })

        default:
            break
        }
    }

}

// MARK: UICollectionViewDataSource
extension SwipeTabsCoordinator: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard isEnabled, let tabsModel else { return 1 }
        let extras = tabsModel.tabs.last?.link != nil ? 1 : 0 // last tab is not a home page, so let's add one
        let count = tabsModel.count + extras
        return count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // `tabsModel` is a weak IUO; an early layout pass during startup (or after a model
        // teardown) can ask for cells before `refresh(tabsModel:)` has wired it up. Fall
        // back to the current-omnibar cell rather than crashing.
        let isCurrentTab = !isEnabled || tabsModel?.currentIndex == indexPath.row || tabsModel == nil
        let reuseIdentifier = isCurrentTab ? Constant.omniBarReuseIdentifier : Constant.templateReuseIdentifier

        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as? OmniBarCell else {
            fatalError("Not \(OmniBarCell.self)")
        }

        if isCurrentTab {
            cell.omniBar = coordinator.omniBar
        } else {
            // Strong reference while we use the omnibar
            let tab = tabsModel?.get(tabAt: indexPath.row)
            let url = tab?.link?.url

            let controller = cell.controller ?? OmniBarFactory.createOmniBarViewController(with: omnibarDependencies)

            coordinator.parentController?.addChild(controller)

            cell.omniBar = controller

            cell.omniBar?.showSeparator()
            cell.omniBar?.adjust(for: appSettings.currentAddressBarPosition)

            cell.omniBar?.configureForSwipeTemplate(
                isExpandedPhone: coordinator.omniBar.isExpandedPhone,
                tabCount: tabsModel.count
            )
            
            if tab?.isAITab == true {
                cell.omniBar?.enterAIChatMode()
            } else if let url {
                cell.omniBar?.startBrowsing()
                cell.omniBar?.resetPrivacyIcon(for: url)
            } else {
                cell.omniBar?.stopBrowsing()
            }

            cell.omniBar?.refreshText(forUrl: url, forceFullURL: appSettings.showFullSiteAddress)
            cell.omniBar?.refreshFireMode(fireMode: tab?.fireTab ?? false)

            controller.didMove(toParent: coordinator.parentController)
            cell.controller = controller
        }

        cell.setNeedsUpdateConstraints()

        return cell
    }

}

class OmniBarCell: UICollectionViewCell {

    weak var coordinator: MainViewCoordinator?
    var controller: OmniBarViewController?

    override var safeAreaInsets: UIEdgeInsets {
        guard let collectionView = superview as? UICollectionView else {
            return super.safeAreaInsets
        }
        return collectionView.safeAreaInsets
    }

    weak var omniBar: OmniBar? {
        willSet {
            (omniBar?.barView as? DefaultOmniBarView)?.safeAreaManagedByContainer = false
            omniBar?.barView.removeFromSuperview()
        }
        didSet {
            guard let omniBarView = omniBar?.barView else { return }

            omniBarView.translatesAutoresizingMaskIntoConstraints = false
            (omniBarView as? DefaultOmniBarView)?.safeAreaManagedByContainer = true
            addSubview(omniBarView)

            NSLayoutConstraint.activate([
                omniBarView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
                omniBarView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
                omniBarView.topAnchor.constraint(equalTo: topAnchor),
                omniBarView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    /// Forwards an overflow point to the omnibar view for hit testing.
    /// Supports the iPad expanded search area which extends below the cell's bounds.
    private func omniBarOverflowHitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard point.y >= bounds.maxY, let omniBarView = omniBar?.barView else { return nil }
        let localPoint = omniBarView.convert(point, from: self)
        return omniBarView.hitTest(localPoint, with: event)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || omniBarOverflowHitTest(point, with: event) != nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        super.hitTest(point, with: event) ?? omniBarOverflowHitTest(point, with: event)
    }

    deinit {
        controller?.removeFromParent()
        controller = nil
    }
}
