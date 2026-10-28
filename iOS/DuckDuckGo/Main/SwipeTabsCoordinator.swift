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
import FeatureFlags_iOS
import PixelKit

enum FloatingSwipePreviewGeometry {

    static func destinationFrame(isAITab: Bool,
                                 superviewBounds: CGRect,
                                 contentContainerFrame: CGRect,
                                 safeAreaInsets: UIEdgeInsets,
                                 aiHeaderHeight: CGFloat,
                                 aiInputHeight: CGFloat) -> CGRect {
        let frameInSuperview: CGRect
        if isAITab {
            let top = superviewBounds.minY + safeAreaInsets.top + aiHeaderHeight
            let bottom = superviewBounds.maxY - safeAreaInsets.bottom - aiInputHeight
            frameInSuperview = CGRect(
                x: superviewBounds.minX,
                y: top,
                width: superviewBounds.width,
                height: max(bottom - top, 0)
            )
        } else {
            // The redesigned NTP also fills the viewport; its content manages the safe-area inset.
            frameInSuperview = superviewBounds
        }

        return frameInSuperview.offsetBy(
            dx: -contentContainerFrame.minX,
            dy: -contentContainerFrame.minY
        )
    }
}

enum SwipeTabBoundaryPolicy {

    static func crossesAITabBoundary(currentIsAITab: Bool, destinationIsAITab: Bool) -> Bool {
        currentIsAITab != destinationIsAITab
    }
}

enum LiveTabSwipePolicy {

    static func shouldUseLiveDestination(isFloatingUIEnabled: Bool, hasWebDestination: Bool) -> Bool {
        isFloatingUIEnabled && hasWebDestination
    }

    static func shouldKeepDestinationView(targetIndex: Int, currentIndex: Int?, tabCount: Int) -> Bool {
        targetIndex < tabCount && targetIndex != (currentIndex ?? targetIndex)
    }
}

/// The rubber band `UIScrollView` gives drags past its content, for drags it doesn't own.
enum SwipeTabsEdgeResistance {

    private static let coefficient: CGFloat = 0.55

    static func offset(for proposed: CGFloat, limits: ClosedRange<CGFloat>, dimension: CGFloat) -> CGFloat {
        if proposed > limits.upperBound {
            return limits.upperBound + damped(proposed - limits.upperBound, dimension: dimension)
        }
        if proposed < limits.lowerBound {
            return limits.lowerBound - damped(limits.lowerBound - proposed, dimension: dimension)
        }
        return proposed
    }

    private static func damped(_ overshoot: CGFloat, dimension: CGFloat) -> CGFloat {
        (1 - 1 / (overshoot * coefficient / dimension + 1)) * dimension
    }
}

/// How swipe chrome copies move between two tabs.
enum SwipeChromeTransition: Equatable {
    /// Copies slide with the pages.
    case slide
    /// Copies stay in place and cross-fade, with the toolbar's embedded omnibar row growing or shrinking.
    case crossFade(leavingNewTabPage: Bool)
}

enum SwipeChromeTransitionPolicy {

    /// Chooses the transition for a swipe between `current` and `destination`.
    static func transition(currentHasInlineSearchInput: Bool,
                           destinationHasInlineSearchInput: Bool,
                           currentIsAITab: Bool,
                           destinationIsAITab: Bool,
                           usesMinimalChromeForWebPages: Bool) -> SwipeChromeTransition {
        guard !usesMinimalChromeForWebPages,
              !currentIsAITab,
              !destinationIsAITab,
              currentHasInlineSearchInput != destinationHasInlineSearchInput else {
            return .slide
        }
        return .crossFade(leavingNewTabPage: currentHasInlineSearchInput)
    }

    /// Alpha of the outgoing chrome copy at `swipeProgress` (0...1).
    static func outgoingAlpha(leavingNewTabPage: Bool, swipeProgress: CGFloat) -> CGFloat {
        let fadeRange = leavingNewTabPage ? newTabPageToolbarClearsEarly : bothCopiesFadeLate
        return 1 - normalized(swipeProgress, over: fadeRange)
    }

    /// Alpha of the incoming chrome copy at `swipeProgress` (0...1).
    static func incomingAlpha(leavingNewTabPage: Bool, swipeProgress: CGFloat) -> CGFloat {
        let fadeRange = leavingNewTabPage ? webPageToolbarAppearsAtOnce : bothCopiesFadeLate
        return normalized(swipeProgress, over: fadeRange)
    }

    private static let newTabPageToolbarClearsEarly: ClosedRange<CGFloat> = 0...0.2
    private static let webPageToolbarAppearsAtOnce: ClosedRange<CGFloat> = 0...0.1
    private static let bothCopiesFadeLate: ClosedRange<CGFloat> = 0.7...1

    private static func normalized(_ value: CGFloat, over range: ClosedRange<CGFloat>) -> CGFloat {
        ((value - range.lowerBound) / (range.upperBound - range.lowerBound)).clamped(to: 0...1)
    }
}

/// Drives a cross-fade between the outgoing and incoming chrome copies during one swipe.
/// The coordinator owns and removes the copies.
final class SwipeChromeCrossFade {

    let leavesNewTabPage: Bool
    private weak var outgoingToolbar: BrowserToolbarView?
    private weak var incomingToolbar: BrowserToolbarView?
    private var capturedInsets: (outgoing: CGFloat, incoming: CGFloat)?

    init(leavesNewTabPage: Bool) {
        self.leavesNewTabPage = leavesNewTabPage
    }

    /// Records the outgoing copy's toolbar, whose omnibar row shrinks as the swipe progresses.
    func attachOutgoingToolbar(_ toolbar: BrowserToolbarView?) {
        outgoingToolbar = toolbar
    }

    /// Records the incoming copy's toolbar and collapses its omnibar row to start hidden.
    func attachIncomingToolbar(_ toolbar: BrowserToolbarView?) {
        incomingToolbar = toolbar
        toolbar?.setEmbeddedOmnibarExpansion(0)
    }

    /// Applies alpha, omnibar row expansion, and blended side insets for `progress` (0...1).
    func update(progress: CGFloat, outgoingChrome: UIView?, incomingChrome: UIView?) {
        if let incomingChrome {
            incomingChrome.alpha = SwipeChromeTransitionPolicy.incomingAlpha(leavingNewTabPage: leavesNewTabPage, swipeProgress: progress)
            incomingToolbar?.setEmbeddedOmnibarExpansion(progress)
            blendInsets(progress: progress)
        }
        outgoingChrome?.alpha = SwipeChromeTransitionPolicy.outgoingAlpha(leavingNewTabPage: leavesNewTabPage, swipeProgress: progress)
        outgoingToolbar?.setEmbeddedOmnibarExpansion(1 - progress)
    }

    private func blendInsets(progress: CGFloat) {
        guard let outgoingToolbar, let incomingToolbar else { return }
        let insets = capturedInsets ?? (outgoing: outgoingToolbar.restingHorizontalOuterInset,
                                        incoming: incomingToolbar.restingHorizontalOuterInset)
        capturedInsets = insets
        let blendedInset = insets.outgoing + (insets.incoming - insets.outgoing) * progress
        outgoingToolbar.setHorizontalOuterInsetsOverride((left: blendedInset, right: blendedInset))
        incomingToolbar.setHorizontalOuterInsetsOverride((left: blendedInset, right: blendedInset))
    }
}

/// Where a live destination page waits while a swipe slides it in, and the safe area it had before.
struct LiveDestinationParking {
    let parkingOffset: CGFloat
    let originalAdditionalSafeAreaInsets: UIEdgeInsets

    /// Additional safe area insets that keep the landing-position safe area on a page translated by `translation`.
    static func landingSafeAreaInsets(original: UIEdgeInsets,
                                      translation: CGFloat,
                                      landingInsets: UIEdgeInsets) -> UIEdgeInsets {
        // The safe area follows the page's on-screen position, so a sliding page loses the part of the camera
        // cutout inset it has moved past, and its content would reflow twice. Add exactly that part back.
        var insets = original
        insets.left += translation.clamped(to: 0...landingInsets.left)
        insets.right += (-translation).clamped(to: 0...landingInsets.right)
        return insets
    }

    /// Translates `controller`'s view by the parking offset plus `swipeTranslation` and holds its safe area.
    func move(_ controller: UIViewController, by swipeTranslation: CGFloat, landingSafeAreaInsets: UIEdgeInsets) {
        let translation = parkingOffset + swipeTranslation
        controller.view.transform = CGAffineTransform(translationX: translation, y: 0)
        let insets = Self.landingSafeAreaInsets(original: originalAdditionalSafeAreaInsets,
                                                translation: translation,
                                                landingInsets: landingSafeAreaInsets)
        if controller.additionalSafeAreaInsets != insets {
            controller.additionalSafeAreaInsets = insets
        }
    }

    /// Returns `controller` to its resting transform and safe area.
    func restore(_ controller: UIViewController) {
        controller.view.transform = .identity
        controller.additionalSafeAreaInsets = originalAdditionalSafeAreaInsets
    }
}

struct SwipeChromeSnapshot {
    let image: UIImage
    let captureRect: CGRect
}

class SwipeTabsCoordinator: NSObject {
    
    static let tabGap: CGFloat = 10
    
    // Set by refresh function
    weak var tabsModel: TabsModelManaging!
    
    weak var coordinator: MainViewCoordinator!
    weak var tabPreviewsSource: TabPreviewsSource!
    weak var appSettings: AppSettings!
    private let omnibarDependencies: OmnibarDependencyProvider
    private let floatingUIManager: FloatingUIManaging
    private let liveTabControllerProvider: (Tab) -> TabViewController?
    private let inputStateProvider: (Tab) -> TabInputState
    private let isPaidAIChatEnabledProvider: () -> Bool
    private let allowsSubscriptionUpsellProvider: () -> Bool
    private let hasInlineSearchInput: (Tab?) -> Bool
    private let usesMinimalChromeForWebPages: () -> Bool
    private let pixelFiring: PixelFiring?

    let selectTab: (Tab) -> Void
    let newTab: () -> Void
    let onSwipeStarted: () -> Void
    
    let feedbackGenerator: UISelectionFeedbackGenerator = {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        return generator
    }()

    private let edgeFeedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private var lastEdgeTickOverscroll: CGFloat = 0
    private var isExternalPanDragging = false

    /// Swipes bounce at the first and last tab, with no new-tab page past the last one. Read once, so a flag
    /// change mid-session can't leave the strip's pages and its gestures disagreeing.
    private let bouncesAtEdges: Bool
    
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
         floatingUIManager: FloatingUIManaging,
         liveTabControllerProvider: @escaping (Tab) -> TabViewController?,
         inputStateProvider: @escaping (Tab) -> TabInputState,
         isPaidAIChatEnabledProvider: @escaping () -> Bool,
         allowsSubscriptionUpsellProvider: @escaping () -> Bool,
         hasInlineSearchInput: @escaping (Tab?) -> Bool = { _ in false },
         usesMinimalChromeForWebPages: @escaping () -> Bool = { false },
         pixelFiring: PixelFiring? = PixelKit.shared,
         selectTab: @escaping (Tab) -> Void,
         newTab: @escaping () -> Void,
         onSwipeStarted: @escaping () -> Void) {
        
        self.coordinator = coordinator
        self.tabPreviewsSource = tabPreviewsSource
        self.appSettings = appSettings
        self.omnibarDependencies = omnibarDependencies
        self.floatingUIManager = floatingUIManager
        self.liveTabControllerProvider = liveTabControllerProvider
        self.inputStateProvider = inputStateProvider
        self.isPaidAIChatEnabledProvider = isPaidAIChatEnabledProvider
        self.allowsSubscriptionUpsellProvider = allowsSubscriptionUpsellProvider
        self.hasInlineSearchInput = hasInlineSearchInput
        self.usesMinimalChromeForWebPages = usesMinimalChromeForWebPages
        self.pixelFiring = pixelFiring
        self.selectTab = selectTab
        self.newTab = newTab
        self.onSwipeStarted = onSwipeStarted
        self.bouncesAtEdges = omnibarDependencies.featureFlagger.isFeatureOn(.aiChatTabHandoffImprovements)
                
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
    
    var state: State = .idle

    /// Tracks the contentOffset when an external pan (driven by a gesture on a view that overlays
    /// the collection view, e.g. the Unified Toggle Input bar) begins, so `.changed` translations
    /// resolve to an absolute offset.
    private var externalPanStartOffset: CGPoint = .zero

    private var pendingSettleCleanup: DispatchWorkItem?
    private var pendingSnapCommit: DispatchWorkItem?

    /// Chrome views (e.g. UTI bar overlay, AI tab header) snapshotted and slid in lockstep with
    /// `currentView` during an external pan — sliding the live views breaks `UIVisualEffectView`
    /// blur and exposes nested shadow/card layers as "stacked screens." See
    /// `prepareAuxiliarySwipeSnapshots` for the snapshot path.
    var auxiliarySwipeViews: [UIView] = []
    /// The live views of `auxiliarySwipeViews`, moved in place while a drag bounces past the first or last tab.
    private var edgePulledChromeViews: [UIView] = []
    var liveSwipeChromeViews: [UIView] = []

    /// Active snapshot views of `auxiliarySwipeViews` during a swipe, parked in the superview
    /// so they ignore the source view's clipping / hierarchy. Reset by `cleanUpViews`.
    private var auxiliarySwipeViewSnapshots: [UIView] = []

    /// Tracks which auxiliary views we hid (alpha=0) at swipe start so we can restore them on
    /// cleanup — we can't blanket-restore everyone in the array because some originals were
    /// already hidden (e.g. AI header on a regular tab) and shouldn't reappear.
    private var hiddenAuxiliaryOriginals: [UIView] = []

    weak var preview: UIView?
    weak var currentView: UIView?

    /// The overlay that hosts per-tab full-screen snapshots during a swipe. Set by the host.
    /// When present, all visual rendering of the swipe is delegated to the overlay and the
    /// legacy mechanisms (cell-based omnibar slide, auxiliary view translation, chromePreview
    /// facade, contentContainer preview) are bypassed.
    weak var swipeOverlayView: TabSwipeOverlayView?

    private var overlayActive = false
    private var floatingIncomingOmnibarController: OmniBarViewController?
    private var liveDestinationController: TabViewController?
    private var liveDestinationParking: LiveDestinationParking?
    private var liveChromeControllers: [UIViewController] = []
    private weak var liveSourceChromeView: UIView?
    private var hiddenLiveSourceChromeViews: [(view: UIView, alpha: CGFloat)] = []

    /// Set while a swipe cross-fades the chrome copies instead of sliding them.
    private var chromeCrossFade: SwipeChromeCrossFade?

    /// Off-screen snapshot of the destination tab's chrome (omnibar / AI header) that slides in
    /// from the lead edge alongside the webview preview. Built only when crossing the
    /// AI↔regular boundary, where the destination's chrome lives at a different position than
    /// the outgoing one — without this the destination chrome would pop into place after the
    /// swipe settles. For regular↔regular swipes the legacy cell-based omnibar already slides
    /// naturally, so we skip the facade.
    weak var chromePreview: UIView?

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
        let collectionWidth = collectionView.bounds.width > 0 ? collectionView.bounds.width : coordinator.superview.frame.size.width
        layout?.itemSize = CGSize(width: collectionWidth, height: omniBarHeight)
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
        signalEdgeIfDraggedPastIt(scrollView)

        switch state {
        case .idle: break

        case .starting(let startPosition):
            let offset = startPosition.x - scrollView.contentOffset.x
            if floatingUIManager.isFloatingUIEnabled {
                chromeCrossFade = makeChromeCrossFade(offset: offset)
                prepareCurrentView()
                let didPrepareLiveDestination = prepareLiveDestination(offset: offset)
                if !didPrepareLiveDestination {
                    preparePreview(offset)
                }
                if isCrossingChromeBoundary(offset: offset) {
                    if !didPrepareLiveDestination {
                        prepareLiveDestinationChrome(offset: offset)
                    }
                    prepareLiveOutgoingChrome()
                } else if destinationIndex(offset: offset) == nil {
                    // Same tab, nothing to swap in: the chrome outside the strip just rides along.
                    edgePulledChromeViews = auxiliarySwipeViews.filter { !$0.isHidden }
                }
                prepareFloatingBottomOmnibarSwipe(offset: offset)
            } else if !activateSwipeOverlay() {
                // Fallback: legacy visual prep when the overlay isn't installed yet.
                prepareCurrentView()
                preparePreview(offset)
                prepareAuxiliarySwipeSnapshots()
            }
            state = .swiping(startPosition, offset.sign)
            if !floatingUIManager.isFloatingUIEnabled {
                onSwipeStarted()
            }

        case .swiping(let startPosition, let sign):
            let offset = startPosition.x - scrollView.contentOffset.x
            if overlayActive, let overlay = swipeOverlayView {
                // Overlay path — chrome and content move as one snapshot, so direction
                // changes are handled natively by just mirroring contentOffset. No need to
                // restart the state machine on sign flip.
                overlay.setContentOffsetX(scrollView.contentOffset.x)
            } else if offset.sign == sign {
                let modifier = sign == .plus ? -1.0 : 1.0
                swipePreviewProportionally(offset: offset, modifier: modifier)
                if let chromeCrossFade {
                    chromeCrossFade.update(progress: swipeProgress(offset: offset),
                                           outgoingChrome: liveSourceChromeView,
                                           incomingChrome: chromePreview)
                } else {
                    swipeChromePreviewProportionally(offset: offset, modifier: modifier)
                    liveSourceChromeView?.transform.tx = offset
                }
                swipeCurrentViewProportionally(offset: offset)
                currentView?.transform.tx = offset
                for snapshot in auxiliarySwipeViewSnapshots {
                    snapshot.transform.tx = offset
                }
                edgePulledChromeViews.forEach { $0.transform.tx = offset }
                updateFloatingBottomOmnibarSwipe(offset: offset)
            } else {
                cleanUpViews()
                state = .starting(startPosition)
            }
        }
    }

    /// Sets up `swipeOverlayView` with per-tab snapshots and shows it on top of the live views.
    /// Returns false when the overlay isn't installed — the caller falls back to the legacy
    /// rendering path.
    ///
    /// Important: this method does **not** hide the live `MainViewController.view` children.
    /// The overlay's pages are opaque (`UIImageView` with `systemBackground` backing), so they
    /// occlude what's underneath. Touching the live views' alpha while a refresh is firing
    /// during the swipe was the cause of the "stacked screens" / "offset chrome" artifacts.
    private func activateSwipeOverlay() -> Bool {
        guard !floatingUIManager.isFloatingUIEnabled, let overlay = swipeOverlayView else {
            return false
        }

        let tabs = tabsModel.tabs
        let currentIndex = tabsModel.currentIndex ?? 0

        // Capture the source page right now from the live view — pixel-perfect, no cache
        // reliance. The overlay is currently alpha=0 (about to be raised), so it won't
        // appear in its own snapshot. We also stash this image into the previews source
        // under the current tab's UID so the next swipe BACK to this tab has fresh chrome.
        let sourceImage: UIImage? = makeFullScreenSnapshot()
        if let sourceImage, currentIndex < tabs.count {
            tabPreviewsSource.updateFullScreenSnapshot(sourceImage, forTab: tabs[currentIndex])
        }

        // Include the trailing "new tab" cell so swiping past the last tab works.
        let extras = hasNewTabDestination(after: tabs) ? 1 : 0
        let pageCount = tabs.count + extras
        // A single swipe can only reach an adjacent page, so we only need snapshots for
        // current ± 1. Non-adjacent pages stay nil — the overlay skips view creation for them.
        let snapshots: [UIImage?] = (0..<pageCount).map { idx in
            if idx == currentIndex {
                return sourceImage
            }
            guard abs(idx - currentIndex) == 1, idx < tabs.count else { return nil }
            // Full-screen snapshot preferred (chrome included). Fall back to the legacy
            // webview-only preview if we haven't captured this tab's screen yet
            if let cached = tabPreviewsSource.fullScreenSnapshot(for: tabs[idx]) {
                return cached
            }
            return tabPreviewsSource.preview(for: tabs[idx])
        }

        overlay.frame = coordinator.superview.bounds
        overlay.populate(snapshots: snapshots, currentIndex: currentIndex)
        overlay.alpha = 1
        overlayActive = true

        return true
    }

    /// Hides the overlay. The live views were never hidden, so there's nothing to restore.
    private func deactivateSwipeOverlay() {
        guard overlayActive else { return }
        overlayActive = false
        swipeOverlayView?.alpha = 0
    }

    func updateFullScreenSnapshotForCurrentTab() {
        guard !floatingUIManager.isFloatingUIEnabled,
              let tab = tabsModel.currentTab else { return }
        // Tab-switcher entry can dismiss editing synchronously in the same run loop.
        // Capture the restored layout rather than the last rendered focused frame.
        coordinator.superview.layoutIfNeeded()
        guard let snapshot = makeFullScreenSnapshot(afterScreenUpdates: true) else { return }
        tabPreviewsSource.updateFullScreenSnapshot(snapshot, forTab: tab)
    }


    /// Renders the live `MainViewController.view` (`coordinator.superview`) into a `UIImage`,
    /// transiently zeroing the overlay's alpha so the overlay doesn't appear in its own
    /// snapshot. The alpha flip happens entirely within a single synchronous block, so UIKit
    /// only paints once — no visible flash.
    private func makeFullScreenSnapshot(afterScreenUpdates: Bool = false) -> UIImage? {
        let superview = coordinator.superview
        guard superview.bounds.width > 0, superview.bounds.height > 0 else { return nil }

        let priorAlpha = swipeOverlayView?.alpha ?? 0
        swipeOverlayView?.alpha = 0
        defer { swipeOverlayView?.alpha = priorAlpha }

        let renderer = UIGraphicsImageRenderer(size: superview.bounds.size)
        return renderer.image { _ in
            superview.drawHierarchy(in: superview.bounds, afterScreenUpdates: afterScreenUpdates)
        }
    }

    /// Snapshots each visible auxiliary chrome view into a flat `UIImageView`, parks it in the
    /// superview at the original's screen position, and hides the original (alpha=0) so the
    /// snapshot is the only thing the user sees. Uses the same `drawHierarchy` path as the
    /// cached destination snapshot — it goes through UIKit's real rendering pipeline, so it
    /// captures `UIVisualEffectView` glass, drop shadows, and nested cardView layout as a
    /// single composited image. `snapshotView(afterScreenUpdates:)` was unreliable here:
    /// it returns a *view* that may still expose internal layering during a transform,
    /// producing the "stacked screens" effect.
    private func prepareAuxiliarySwipeSnapshots() {
        // Defensive: should already be empty (cleanUpViews resets), but if a prior swipe was
        // interrupted mid-flight, restore + clear before starting fresh.
        teardownAuxiliarySwipeSnapshots()

        for view in auxiliarySwipeViews {
            guard !view.isHidden, view.alpha > 0.01, view.bounds.width > 0, view.bounds.height > 0 else {
                continue
            }

            guard let chromeSnapshot = makeChromeSnapshot(of: view) else { continue }
            let snapshot = UIImageView(image: chromeSnapshot.image)

            // Convert the original's frame into the superview's coordinate space — auxiliary
            // views live as descendants (e.g. unifiedToggleInputContainer is inside
            // navigationBarContainer), so their `.frame` is in their parent's coords, not the
            // root's.
            let frameInSuperview = view.convert(chromeSnapshot.captureRect, to: coordinator.superview)
            snapshot.frame = frameInSuperview
            coordinator.superview.addSubview(snapshot)
            auxiliarySwipeViewSnapshots.append(snapshot)

            view.alpha = 0
            hiddenAuxiliaryOriginals.append(view)
        }
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

    private func makeChromeSnapshot(of view: UIView) -> SwipeChromeSnapshot? {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return nil }

        var captureRect = view.bounds
        accumulateVisibleBounds(of: view, relativeTo: view, into: &captureRect)
        captureRect = captureRect.insetBy(dx: -12, dy: -12)

        let renderer = UIGraphicsImageRenderer(size: captureRect.size)
        let image = renderer.image { _ in
            view.drawHierarchy(
                in: view.bounds.offsetBy(dx: -captureRect.minX, dy: -captureRect.minY),
                afterScreenUpdates: false
            )
        }
        return SwipeChromeSnapshot(image: image, captureRect: captureRect)
    }

    private func accumulateVisibleBounds(of view: UIView, relativeTo rootView: UIView, into bounds: inout CGRect) {
        for subview in view.subviews where !subview.isHidden && subview.alpha > 0.01 {
            bounds = bounds.union(subview.convert(subview.bounds, to: rootView))
            accumulateVisibleBounds(of: subview, relativeTo: rootView, into: &bounds)
        }
    }
    
    private func swipeCurrentViewProportionally(offset: CGFloat) {
        currentView?.transform.tx = offset
    }
    
    private func swipePreviewProportionally(offset: CGFloat, modifier: CGFloat) {
        let width = coordinator.contentContainer.frame.width
        let percent = offset / width
        let swipeWidth = width + Self.tabGap
        let x = (swipeWidth * percent) + (Self.tabGap * modifier)
        if let liveDestinationController, preview === liveDestinationController.view {
            liveDestinationParking?.move(liveDestinationController, by: x, landingSafeAreaInsets: coordinator.superview.safeAreaInsets)
        } else {
            preview?.transform.tx = x
        }
    }
    
    private func prepareCurrentView() {

        if !coordinator.logoContainer.isHidden {
            currentView = coordinator.logoContainer
        } else {
            currentView = coordinator.contentContainer.subviews.last
        }
    }

    private func preparePreview(_ offset: CGFloat) {
        guard let index = tabsModel.currentIndex else {
            return
        }
        let modifier = (offset > 0 ? -1 : 1)
        let nextIndex = index + modifier

        guard tabsModel.tabs.indices.contains(nextIndex) || hasNewTabDestination(after: tabsModel.tabs) else {
            return
        }

        let tab = tabsModel.get(tabAt: nextIndex)
        let targetFrame: CGRect
        if floatingUIManager.isFloatingUIEnabled {
            targetFrame = FloatingSwipePreviewGeometry.destinationFrame(
                isAITab: tab?.isAITab == true,
                superviewBounds: coordinator.superview.bounds,
                contentContainerFrame: coordinator.contentContainer.frame,
                safeAreaInsets: coordinator.superview.safeAreaInsets,
                aiHeaderHeight: max(coordinator.aiChatTabChatHeaderContainer.bounds.height, 60),
                aiInputHeight: DefaultOmniBarView.expectedHeight
            )
        } else {
            targetFrame = coordinator.contentContainer.bounds
        }
        var height = targetFrame.height

        if let tab, let image = tabPreviewsSource.preview(for: tab) {
            createPreviewFromImage(image)
            if !floatingUIManager.isFloatingUIEnabled,
               appSettings.currentAddressBarPosition.isBottom,
               tab.link != nil,
               let collectionView = coordinator.navigationBarContainer.subviews.first as? UICollectionView {
                // Adjust the preview height to account for the omnibar at the bottom
                // When the omnibar is at the bottom, the webview content extends underneath it
                // We need to subtract the omnibar height from the total height to get the visible content area
                // Note: We use the collectionView's height directly instead of navigationBarContainer.height
                // because the container height can change when the keyboard appears
                height = targetFrame.height - collectionView.frame.size.height
            }
            preview?.frame = CGRect(x: targetFrame.minX, y: targetFrame.minY, width: targetFrame.width, height: height)
        } else if tab?.link == nil {
            if hasInlineSearchInput(tab) {
                // The legacy centered logo does not match the redesigned page revealed after the swipe.
                let placeholder = UIView()
                placeholder.backgroundColor = UIColor(designSystemColor: .background)
                placeholder.isUserInteractionEnabled = false
                coordinator.contentContainer.addSubview(placeholder)
                preview = placeholder
            } else {
                createPreviewFromLogoContainerWithSize(targetFrame.size)
            }
            preview?.frame = targetFrame
        }

        preview?.frame.origin.x += coordinator.contentContainer.frame.width * CGFloat(modifier)
    }

    private func prepareLiveDestination(offset: CGFloat) -> Bool {
        guard let currentIndex = tabsModel.currentIndex else { return false }
        let modifier = offset > 0 ? -1 : 1
        let destinationIndex = currentIndex + modifier
        guard let tab = tabsModel.get(tabAt: destinationIndex),
              LiveTabSwipePolicy.shouldUseLiveDestination(
                isFloatingUIEnabled: floatingUIManager.isFloatingUIEnabled,
                hasWebDestination: tab.link != nil
              ) else {
            return false
        }
        if liveDestinationController?.tabModel === tab {
            return true
        }
        tearDownLiveSwipeViews()
        guard let controller = liveTabControllerProvider(tab),
              controller.parent == nil else {
            return false
        }

        let frame = FloatingSwipePreviewGeometry.destinationFrame(
            isAITab: tab.isAITab,
            superviewBounds: coordinator.superview.bounds,
            contentContainerFrame: coordinator.contentContainer.frame,
            safeAreaInsets: coordinator.superview.safeAreaInsets,
            aiHeaderHeight: max(coordinator.aiChatTabChatHeaderContainer.bounds.height, 60),
            aiInputHeight: DefaultOmniBarView.expectedHeight
        )

        coordinator.parentController?.addChild(controller)
        controller.view.frame = frame
        let parking = LiveDestinationParking(parkingOffset: CGFloat(modifier) * coordinator.contentContainer.bounds.width,
                                             originalAdditionalSafeAreaInsets: controller.additionalSafeAreaInsets)
        parking.move(controller, by: 0, landingSafeAreaInsets: coordinator.superview.safeAreaInsets)
        liveDestinationParking = parking
        controller.view.isUserInteractionEnabled = false
        coordinator.contentContainer.addSubview(controller.view)
        controller.didMove(toParent: coordinator.parentController)
        liveDestinationController = controller
        preview = controller.view
        if isCrossingChromeBoundary(offset: offset) {
            prepareLiveChromePreview(modifier: modifier, destinationTab: tab)
        }
        return true
    }

    private func prepareLiveChromePreview(modifier: Int, destinationTab: Tab?) {
        chromePreview?.removeFromSuperview()
        chromePreview = nil

        let superview = coordinator.superview
        let container = UIView(frame: CGRect(
            x: chromeCrossFade == nil ? CGFloat(modifier) * superview.bounds.width : 0,
            y: 0,
            width: superview.bounds.width,
            height: superview.bounds.height
        ))
        container.alpha = chromeCrossFade == nil ? 1 : 0
        container.isUserInteractionEnabled = false
        container.overrideUserInterfaceStyle = superview.traitCollection.userInterfaceStyle
        superview.addSubview(container)

        buildChromeCopyOutsideRunningAnimation(in: container) {
            if let destinationTab, destinationTab.isAITab {
                addLiveAIChrome(for: destinationTab, to: container)
            } else {
                let toolbar = addLiveRegularChrome(for: destinationTab, to: container)
                chromeCrossFade?.attachIncomingToolbar(toolbar)
            }
        }

        chromePreview = container
    }

    private func prepareLiveDestinationChrome(offset: CGFloat) {
        guard let currentIndex = tabsModel.currentIndex else { return }
        let modifier = offset > 0 ? -1 : 1
        let destinationIndex = currentIndex + modifier
        let destinationTab = tabsModel.get(tabAt: destinationIndex)
        prepareLiveChromePreview(modifier: modifier, destinationTab: destinationTab)
    }

    private func addLiveAIChrome(for tab: Tab, to container: UIView) {
        let state = inputStateProvider(tab)
        let header = AIChatTabChatHeaderView(
            isFireModeEnabled: true,
            shouldShowImageGeneration: omnibarDependencies.featureFlagger.isFeatureOn(.aiChatNativeSidebar),
            layout: AIChatTabChatHeaderView.Layout(featureFlagger: omnibarDependencies.featureFlagger)
        )
        header.isUserInteractionEnabled = false

        let headerHeight = max(coordinator.aiChatTabChatHeaderContainer.bounds.height, 60)
        header.frame = CGRect(
            x: 0,
            y: coordinator.superview.safeAreaInsets.top,
            width: container.bounds.width,
            height: headerHeight
        )
        container.addSubview(header)
        header.configure(isSubscriptionActive: isPaidAIChatEnabledProvider(),
                         allowsSubscriptionUpsell: allowsSubscriptionUpsellProvider())
        header.setTabIconState(
            count: tabsModel.count,
            hasUnread: tabsModel.hasUnread,
            isFireMode: tab.fireTab
        )
        header.setVoiceSessionActive(state.isVoiceSessionActive)

        guard state.aiChatInputBoxVisibility != .hidden else { return }

        let attachMoreTabsFeature = AIChatContextualAttachMoreTabsFeature(featureFlagger: omnibarDependencies.featureFlagger)
        let inputController = UnifiedToggleInputViewController(
            isToggleEnabled: true,
            isFireTab: tab.fireTab,
            usesCompactAttachmentLayout: attachMoreTabsFeature.usesCompactAttachmentLayout)
        inputController.loadViewIfNeeded()
        inputController.view.isUserInteractionEnabled = false

        let inputHeight = DefaultOmniBarView.expectedHeight
        inputController.view.frame = CGRect(
            x: 0,
            y: container.bounds.height - coordinator.superview.safeAreaInsets.bottom - inputHeight,
            width: container.bounds.width,
            height: inputHeight
        )
        coordinator.parentController?.addChild(inputController)
        container.addSubview(inputController.view)
        inputController.didMove(toParent: coordinator.parentController)
        inputController.apply(
            UTIViewConfig(
                cardLayout: .flanked(.all),
                cardPosition: .bottom,
                usesOmnibarMargins: false,
                inactiveAppearance: false,
                inputMode: .aiChat,
                isTopBarPosition: false,
                isInlineDismissHidden: true,
                isAITab: true
            ),
            animated: false
        )
        inputController.text = state.text
        inputController.setFlankingAccessoriesVisible(.all)
        liveChromeControllers.append(inputController)
    }

    /// Adds a copy of the chrome `tab` shows at rest and returns its toolbar, if it has one.
    private func addLiveRegularChrome(for tab: Tab?, to container: UIView) -> BrowserToolbarView? {
        let usesMinimalChrome = usesMinimalChromeForWebPages()
        return hasInlineSearchInput(tab)
            ? addNewTabPageToolbarCopy(for: tab, to: container, isCompact: usesMinimalChrome)
            : addWebPageChromeCopy(for: tab, to: container, usesMinimalChrome: usesMinimalChrome)
    }

    /// Adds the NTP's buttons-only toolbar copy, compact in minimal chrome layouts.
    private func addNewTabPageToolbarCopy(for tab: Tab?, to container: UIView, isCompact: Bool) -> BrowserToolbarView {
        let toolbar = makeReadOnlyToolbar(for: tab)
        toolbar.usesRedesignedNewTabPageLayout = true
        pinToLiveSideInsets(toolbar)
        toolbar.setCompactStandaloneHeight(isCompact)
        let height = BrowserToolbarView.totalHeight(withOmnibarHeight: 0, isFloating: true, isCompact: isCompact)
        toolbar.frame = CGRect(x: 0,
                               y: liveToolbarBottomEdge(in: container) - height,
                               width: container.bounds.width,
                               height: height)
        container.addSubview(toolbar)
        return toolbar
    }

    /// Adds a web page's omnibar copy, plus its toolbar copy unless minimal chrome draws the bar alone.
    private func addWebPageChromeCopy(for tab: Tab?, to container: UIView, usesMinimalChrome: Bool) -> BrowserToolbarView? {
        let index = tab.flatMap { tab in tabsModel.tabs.firstIndex { $0 === tab } } ?? tabsModel.count
        let omnibarController = makeSwipeTemplateController()
        configureSwipeTemplate(omnibarController, at: index, forcesMinimalChrome: usesMinimalChrome)
        omnibarController.barView.isUserInteractionEnabled = false
        coordinator.parentController?.addChild(omnibarController)
        liveChromeControllers.append(omnibarController)

        let barView = omnibarController.barView
        let omnibarHeight = barView.expectedHeight
        let isBottomAddressBar = appSettings.currentAddressBarPosition.isBottom
        let toolbar = usesMinimalChrome ? nil : makeReadOnlyToolbar(for: tab)
        let toolbarHeight: CGFloat
        if let toolbar, isBottomAddressBar {
            toolbar.setOmnibarView(barView, height: omnibarHeight)
            toolbarHeight = BrowserToolbarView.totalHeight(withOmnibarHeight: omnibarHeight, isFloating: true)
        } else {
            let safeAreaInsets = coordinator.superview.safeAreaInsets
            let barY = isBottomAddressBar
                ? container.bounds.height - safeAreaInsets.bottom - omnibarHeight
                : safeAreaInsets.top
            barView.frame = CGRect(x: 0, y: barY, width: container.bounds.width, height: omnibarHeight)
            container.addSubview(barView)
            toolbarHeight = BrowserToolbarView.floatingButtonsHeight
        }
        omnibarController.didMove(toParent: coordinator.parentController)

        guard let toolbar else { return nil }
        toolbar.frame = CGRect(
            x: 0,
            y: liveToolbarBottomEdge(in: container) - toolbarHeight,
            width: container.bounds.width,
            height: toolbarHeight
        )
        container.addSubview(toolbar)
        return toolbar
    }

    private func liveToolbarBottomEdge(in container: UIView) -> CGFloat {
        if #available(iOS 26.0, *), floatingUIManager.isFloatingUIEnabled {
            let layoutFrame = coordinator.superview.layoutGuide(for: .safeArea(cornerAdaptation: .vertical)).layoutFrame
            if !layoutFrame.isEmpty {
                return layoutFrame.maxY
            }
        }
        return container.bounds.height - coordinator.superview.safeAreaInsets.bottom
    }

    private func pinToLiveSideInsets(_ toolbar: BrowserToolbarView) {
        // A copy parked off screen resolves the camera cutout from where it is rather than from where it
        // will land, so its own inset would differ from the live toolbar it hands over to.
        guard #available(iOS 26.0, *) else { return }
        let insets = BrowserToolbarView.floatingStandaloneOuterInsets(in: coordinator.superview)
        toolbar.setHorizontalOuterInsetsOverride((left: insets.left, right: insets.right))
    }

    private func makeReadOnlyToolbar(for tab: Tab?) -> BrowserToolbarView {
        let toolbar = BrowserToolbarView()
        toolbar.setFloatingStyleEnabled(true)
        toolbar.isUserInteractionEnabled = false
        let showsNewTabPage = tab?.link == nil
        let sourceViews = coordinator.toolbarHandler.toolbarButtonViews(showsNewTabPage: showsNewTabPage)
        let buttons = sourceViews.map { sourceView in
            makeReadOnlyButton(from: sourceView, isEnabled: isToolbarButtonEnabled(sourceView, for: tab))
        }
        toolbar.setToolbarButtons(buttons)
        return toolbar
    }

    private func isToolbarButtonEnabled(_ sourceView: UIView, for tab: Tab?) -> Bool {
        let isBackButton = sourceView === coordinator.toolbarBackButton
        let isForwardButton = sourceView === coordinator.toolbarForwardButton
        guard isBackButton || isForwardButton else { return true }

        if tab === tabsModel.currentTab {
            return (sourceView as? UIControl)?.isEnabled ?? true
        }
        guard let destinationController = liveDestinationController, destinationController.tabModel === tab else {
            return false
        }
        return isBackButton ? destinationController.canGoBack : destinationController.canGoForward
    }

    private func makeReadOnlyButton(from sourceView: UIView, isEnabled: Bool) -> UIView {
        if let tabSwitcher = sourceView as? TabSwitcherStaticButton,
           let snapshot = makeSnapshotOfTabSwitcherDrawnInSubview(tabSwitcher) {
            return snapshot
        }
        guard let sourceButton = sourceView as? UIButton else {
            let spacer = UIView()
            spacer.frame.size = sourceView.bounds.size
            return spacer
        }
        let button = UIButton(type: .system)
        button.configuration = sourceButton.configuration
        button.setImage(sourceButton.image(for: .normal), for: .normal)
        button.tintColor = sourceButton.tintColor
        button.isEnabled = isEnabled
        button.isUserInteractionEnabled = false
        matchLiveToolbarButtonSpacing(button)
        return button
    }

    private func matchLiveToolbarButtonSpacing(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: BrowserChromeButton.toolbarButtonSize),
            button.heightAnchor.constraint(equalToConstant: BrowserChromeButton.toolbarButtonSize),
        ])
    }

    private func makeSnapshotOfTabSwitcherDrawnInSubview(_ tabSwitcher: TabSwitcherStaticButton) -> UIView? {
        guard let snapshot = tabSwitcher.snapshotView(afterScreenUpdates: false) else { return nil }
        snapshot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            snapshot.widthAnchor.constraint(equalToConstant: tabSwitcher.bounds.width),
            snapshot.heightAnchor.constraint(equalToConstant: tabSwitcher.bounds.height),
        ])
        return snapshot
    }

    /// Builds a chrome copy and lays it out at its final size at once.
    private func buildChromeCopyOutsideRunningAnimation(in container: UIView, _ build: () -> Void) {
        UIView.performWithoutAnimation {
            build()
            container.layoutIfNeeded()
        }
    }

    private func prepareLiveOutgoingChrome() {
        guard liveSourceChromeView == nil else { return }
        guard let currentIndex = tabsModel.currentIndex,
              let currentTab = tabsModel.get(tabAt: currentIndex) else {
            return
        }

        let superview = coordinator.superview
        let container = UIView(frame: superview.bounds)
        container.isUserInteractionEnabled = false
        container.overrideUserInterfaceStyle = superview.traitCollection.userInterfaceStyle
        superview.addSubview(container)
        buildChromeCopyOutsideRunningAnimation(in: container) {
            if currentTab.isAITab {
                addLiveAIChrome(for: currentTab, to: container)
            } else {
                let toolbar = addLiveRegularChrome(for: currentTab, to: container)
                chromeCrossFade?.attachOutgoingToolbar(toolbar)
            }
        }
        liveSourceChromeView = container

        hiddenLiveSourceChromeViews = liveSwipeChromeViews.compactMap { view in
            guard !view.isHidden, view.alpha > 0.01 else { return nil }
            let alpha = view.alpha
            view.alpha = 0
            return (view: view, alpha: alpha)
        }
    }

    private func tearDownLiveSwipeViews(keepDestinationView: Bool = false) {
        for entry in hiddenLiveSourceChromeViews {
            entry.view.alpha = entry.alpha
        }
        hiddenLiveSourceChromeViews = []
        liveSourceChromeView?.removeFromSuperview()
        liveSourceChromeView = nil
        chromePreview?.removeFromSuperview()
        chromePreview = nil

        if let liveDestinationController {
            if preview === liveDestinationController.view {
                preview = nil
            }
            liveDestinationParking?.restore(liveDestinationController)
            liveDestinationController.willMove(toParent: nil)
            if !keepDestinationView {
                liveDestinationController.view.removeFromSuperview()
            }
            liveDestinationController.removeFromParent()
            liveDestinationController.view.isUserInteractionEnabled = true
        }
        liveDestinationController = nil
        liveDestinationParking = nil

        for controller in liveChromeControllers {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        liveChromeControllers = []
    }

    private func prepareFloatingBottomOmnibarSwipe(offset: CGFloat) {
        guard appSettings.currentAddressBarPosition.isBottom,
              !isCrossingChromeBoundary(offset: offset),
              coordinator.isOmnibarInToolbar,
              let currentIndex = tabsModel.currentIndex else {
            return
        }

        guard let destinationIndex = destinationIndex(offset: offset) else { return }
        let currentTab = tabsModel.get(tabAt: currentIndex)
        let destinationTab = tabsModel.get(tabAt: destinationIndex)
        guard currentTab?.isAITab != true, destinationTab?.isAITab != true else { return }

        let controller = makeSwipeTemplateController()
        coordinator.parentController?.addChild(controller)
        configureSwipeTemplate(controller, at: destinationIndex)
        controller.barView.setIconContainersAlpha(0)
        coordinator.omniBar.barView.setIconContainersAlpha(0)
        coordinator.toolbar.beginOmnibarSwipe(with: controller.barView)
        controller.didMove(toParent: coordinator.parentController)
        floatingIncomingOmnibarController = controller
        updateFloatingBottomOmnibarSwipe(offset: offset)
    }

    private func updateFloatingBottomOmnibarSwipe(offset: CGFloat) {
        guard floatingIncomingOmnibarController != nil else { return }
        let width = coordinator.contentContainer.bounds.width
        guard width > 0 else { return }

        let direction: FloatingOmnibarSwipeDirection = offset < 0 ? .left : .right
        coordinator.toolbar.updateOmnibarSwipe(
            progress: min(abs(offset) / width, 1),
            direction: direction
        )
    }

    private func cleanUpFloatingBottomOmnibarSwipe() {
        coordinator.toolbar.endOmnibarSwipe()
        coordinator.omniBar.barView.setIconContainersAlpha(1)
        floatingIncomingOmnibarController?.barView.setIconContainersAlpha(1)
        floatingIncomingOmnibarController?.willMove(toParent: nil)
        floatingIncomingOmnibarController?.removeFromParent()
        floatingIncomingOmnibarController = nil
    }

    /// Released past the first or last tab, the strip springs back like a scroll view's bounce.
    private func animateExternalPanSettle(to targetOffset: CGPoint, completion: @escaping (Bool) -> Void) {
        let maxX = max(collectionView.contentSize.width - collectionView.frame.width, 0)
        let isPastAnEdge = collectionView.contentOffset.x < 0 || collectionView.contentOffset.x > maxX
        let animations = { self.collectionView.contentOffset = targetOffset }
        if isPastAnEdge {
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0,
                           options: .curveEaseOut, animations: animations, completion: completion)
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: animations, completion: completion)
        }
    }

    /// Ticks while a finger pulls past the first or last tab, firmer the further it pulls; none on release.
    private func signalEdgeIfDraggedPastIt(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || isExternalPanDragging, bouncesAtEdges else { return }
        let maxOffsetX = scrollView.contentSize.width - scrollView.bounds.width
        let overscroll = max(-scrollView.contentOffset.x, scrollView.contentOffset.x - maxOffsetX, 0)
        guard abs(overscroll - lastEdgeTickOverscroll) >= EdgeHaptics.tickSpacing else { return }
        lastEdgeTickOverscroll = overscroll
        guard overscroll > 0 else { return }
        let tension = min(overscroll / max(scrollView.bounds.width, 1) * EdgeHaptics.tensionGain, 1)
        edgeFeedbackGenerator.impactOccurred(intensity: EdgeHaptics.minimumIntensity + (1 - EdgeHaptics.minimumIntensity) * tension)
        edgeFeedbackGenerator.prepare()
    }

    private enum EdgeHaptics {
        static let tickSpacing: CGFloat = 4
        static let minimumIntensity: CGFloat = 0.35
        static let tensionGain: CGFloat = 4
    }

    /// Swiping past a last tab with content opens a new tab, unless the swipe should bounce there instead.
    private func hasNewTabDestination(after tabs: [Tab]) -> Bool {
        tabs.last?.link != nil && !bouncesAtEdges
    }

    /// The page a swipe in this direction lands on; `nil` past the first or last tab, where it can only bounce.
    private func destinationIndex(offset: CGFloat) -> Int? {
        guard let currentIndex = tabsModel.currentIndex else { return nil }
        let destinationIndex = currentIndex + (offset > 0 ? -1 : 1)
        let isNewTabDestination = destinationIndex == tabsModel.count && hasNewTabDestination(after: tabsModel.tabs)
        return tabsModel.tabs.indices.contains(destinationIndex) || isNewTabDestination ? destinationIndex : nil
    }

    /// Returns the cross-fade for a swipe at `offset`, or nil when the chrome copies slide.
    private func makeChromeCrossFade(offset: CGFloat) -> SwipeChromeCrossFade? {
        guard isCrossingChromeBoundary(offset: offset),
              let currentIndex = tabsModel.currentIndex,
              let currentTab = tabsModel.get(tabAt: currentIndex) else {
            return nil
        }
        let destinationTab = tabsModel.get(tabAt: currentIndex + (offset > 0 ? -1 : 1))
        let transition = SwipeChromeTransitionPolicy.transition(
            currentHasInlineSearchInput: hasInlineSearchInput(currentTab),
            destinationHasInlineSearchInput: hasInlineSearchInput(destinationTab),
            currentIsAITab: currentTab.isAITab,
            destinationIsAITab: destinationTab?.isAITab == true,
            usesMinimalChromeForWebPages: usesMinimalChromeForWebPages())
        guard case .crossFade(let leavingNewTabPage) = transition else { return nil }
        return SwipeChromeCrossFade(leavesNewTabPage: leavingNewTabPage)
    }

    private func swipeProgress(offset: CGFloat) -> CGFloat {
        let width = coordinator.superview.bounds.width
        guard width > 0 else { return 0 }
        return min(abs(offset) / width, 1)
    }

    private func isCrossingChromeBoundary(offset: CGFloat) -> Bool {
        guard let currentIndex = tabsModel.currentIndex,
              let currentTab = tabsModel.get(tabAt: currentIndex) else {
            return false
        }
        guard let destinationIndex = destinationIndex(offset: offset) else { return false }
        let destinationTab = tabsModel.get(tabAt: destinationIndex)
        if hasInlineSearchInput(currentTab) != hasInlineSearchInput(destinationTab) {
            return true
        }
        guard let destinationTab else { return false }
        return SwipeTabBoundaryPolicy.crossesAITabBoundary(
            currentIsAITab: currentTab.isAITab,
            destinationIsAITab: destinationTab.isAITab
        )
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
        imageView.clipsToBounds = true
        coordinator.contentContainer.addSubview(imageView)
        preview = imageView
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
        }
        coordinator.logoContainer.isHidden = isHidden
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        lastEdgeTickOverscroll = 0
        edgeFeedbackGenerator.prepare()
        switch state {
        case .idle:
            if floatingUIManager.isFloatingUIEnabled {
                onSwipeStarted()
            }
            state = .starting(scrollView.contentOffset)

        default: break
        }
    }

    // A drag released on a page boundary with no velocity (e.g. dragged back to the start)
    // never decelerates, so `scrollViewDidEndDecelerating` wouldn't fire and the swipe overlay
    // would stay up over the live UI.
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        if case .swiping = state {
            pixelFiring?.fire(SwipeTabsPixel.stuckSwipeRecovered, frequency: .dailyAndCount)
        }
        scrollViewDidEndDecelerating(scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard !state.isIdle else {
            return
        }

        // Defer cleanup to the next runloop tick. `selectTab` synchronously triggers the tab
        // swap (adding the destination's webview / NTP to `contentContainer`), but the new
        // view typically needs one runloop iteration to lay out and produce its first paint.
        // If we tear down the swipe overlays in the same tick — `preview.removeFromSuperview`
        // plus `currentView.transform = .identity` — UIKit ends up painting a frame where the
        // outgoing currentView has snapped back to its on-screen position while the destination
        // isn't yet rendered. That's the flash. Async-deferring `cleanUpViews` lets the
        // destination settle before we lift the overlays.
        pendingSettleCleanup?.cancel()
        let cleanup = DispatchWorkItem { [weak self] in
            self?.cleanUpViews()
            self?.state = .idle
        }
        pendingSettleCleanup = cleanup
        defer { DispatchQueue.main.async(execute: cleanup) }

        let point = CGPoint(x: coordinator.navigationBarCollectionView.bounds.midX,
                            y: coordinator.navigationBarCollectionView.bounds.midY)

        guard let index = coordinator.navigationBarCollectionView.indexPathForItem(at: point)?.row else {
            assertionFailure("invalid index")
            return
        }
        let keepsLiveDestination = LiveTabSwipePolicy.shouldKeepDestinationView(
            targetIndex: index,
            currentIndex: tabsModel.currentIndex,
            tabCount: tabsModel.count
        )
        tearDownLiveSwipeViews(keepDestinationView: keepsLiveDestination)
        cleanUpFloatingBottomOmnibarSwipe()
        chromePreview?.removeFromSuperview()
        chromePreview = nil
        feedbackGenerator.selectionChanged()
        if index >= tabsModel.count {
            newTab()
        } else {
            if let tab = tabsModel.get(tabAt: index) {
                selectTab(tab)
            }
        }
    }

    private func cleanUpViews() {
        chromeCrossFade = nil
        deactivateSwipeOverlay()
        tearDownLiveSwipeViews()
        cleanUpFloatingBottomOmnibarSwipe()
        currentView?.transform = .identity
        currentView = nil
        edgePulledChromeViews.forEach { $0.transform.tx = 0 }
        edgePulledChromeViews = []
        preview?.removeFromSuperview()
        chromePreview?.removeFromSuperview()
        chromePreview = nil
        teardownAuxiliarySwipeSnapshots()
        if let tab = tabsModel?.currentTab, tab.link != nil {
            liveTabControllerProvider(tab)?.fireSitePermissionDialogImpressionIfVisible()
        }
    }

}

// MARK: Public Interface
extension SwipeTabsCoordinator {

    func refresh(tabsModel: TabsModelManaging, scrollToSelected: Bool = false) {
        if liveDestinationController != nil || liveSourceChromeView != nil || !liveChromeControllers.isEmpty {
            cleanUpViews()
            state = .idle
        }
        self.tabsModel = tabsModel
        coordinator.navigationBarCollectionView.reloadData()
        
        updateLayout()
        
        if scrollToSelected {
            scrollToCurrent()
            collectionView.layoutIfNeeded()
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
            return
        }

        switch gesture.state {
        case .began:
            // A prior external pan's settling animation can still be in flight, or another
            // attached recognizer (UTI bar / AI header) may have left non-idle state behind.
            // Reset before starting so `scrollViewWillBeginDragging` (which only transitions
            // from `.idle`) actually arms the state machine for this gesture.
            pendingSettleCleanup?.cancel()
            pendingSettleCleanup = nil
            pendingSnapCommit?.cancel()
            pendingSnapCommit = nil
            collectionView.layer.removeAllAnimations()
            cleanUpViews()
            state = .idle
            scrollViewWillBeginDragging(collectionView)
            externalPanStartOffset = collectionView.contentOffset
            isExternalPanDragging = true

        case .changed:
            let translation = gesture.translation(in: panView).x
            let pageWidth = collectionView.frame.width
            let proposedX = externalPanStartOffset.x - translation
            let maxX = max(collectionView.contentSize.width - pageWidth, 0)
            let x = bouncesAtEdges
                ? SwipeTabsEdgeResistance.offset(for: proposedX, limits: 0...maxX, dimension: pageWidth)
                : max(0, min(proposedX, maxX))
            collectionView.contentOffset = CGPoint(x: x, y: 0)

        case .ended, .cancelled, .failed:
            isExternalPanDragging = false
            let pageWidth = collectionView.frame.width
            guard pageWidth > 0 else {
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
            pendingSnapCommit?.cancel()
            let commit = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingSnapCommit = nil
                self.scrollViewDidEndDecelerating(self.collectionView)
            }
            pendingSnapCommit = commit
            animateExternalPanSettle(to: targetOffset, completion: { [weak self] finished in
                guard let self else { return }
                if finished {
                    commit.perform()
                } else if !commit.isCancelled {
                    commit.cancel()
                    self.pendingSnapCommit = nil
                    self.cleanUpViews()
                    self.state = .idle
                }
            })

        default:
            break
        }
    }

}

private extension SwipeTabsCoordinator {

    func makeSwipeTemplateController() -> OmniBarViewController {
        OmniBarFactory.createOmniBarViewController(
            with: omnibarDependencies,
            isFloatingUIEnabled: floatingUIManager.isFloatingUIEnabled
        )
    }

    func configureSwipeTemplate(_ omniBar: OmniBar, at index: Int, forcesMinimalChrome: Bool = false) {
        let tab = tabsModel?.get(tabAt: index)
        let isExpandedPhone = coordinator.omniBar.isExpandedPhone || forcesMinimalChrome
        let url = tab?.link?.url

        omniBar.showSeparator()
        omniBar.adjust(for: appSettings.currentAddressBarPosition)
        if floatingUIManager.isFloatingUIEnabled {
            omniBar.barView.makeGlass()
        }
        omniBar.configureForSwipeTemplate(
            isExpandedPhone: isExpandedPhone,
            tabCount: tabsModel.count
        )
        omniBar.barView.setFloatingMinimalChromeBar(
            isExpandedPhone && floatingUIManager.isFloatingUIEnabled
        )

        if tab?.isAITab == true {
            omniBar.enterAIChatMode()
        } else if let url {
            omniBar.startBrowsing()
            omniBar.resetPrivacyIcon(for: url)
        } else {
            omniBar.stopBrowsing()
        }

        omniBar.refreshText(forUrl: url, forceFullURL: appSettings.showFullSiteAddress)
        omniBar.refreshFireMode(fireMode: tab?.fireTab ?? false)
        omniBar.barView.isHidden = hasInlineSearchInput(tab)
    }
}

// MARK: UICollectionViewDataSource
extension SwipeTabsCoordinator: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard isEnabled, let tabsModel else { return 1 }
        let extras = hasNewTabDestination(after: tabsModel.tabs) ? 1 : 0
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
        cell.isFloatingUIEnabledProvider = { [weak self] in
            self?.floatingUIManager.isFloatingUIEnabled ?? false
        }

        if isCurrentTab {
            cell.omniBar = coordinator.omniBar
        } else {
            let controller = cell.controller ?? makeSwipeTemplateController()
            if controller.parent == nil {
                coordinator.parentController?.addChild(controller)
            }

            cell.omniBar = controller
            configureSwipeTemplate(controller, at: indexPath.row)

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
    var isFloatingUIEnabledProvider: (() -> Bool)?

    override var safeAreaInsets: UIEdgeInsets {
        guard let collectionView = superview as? UICollectionView else {
            return super.safeAreaInsets
        }
        return collectionView.safeAreaInsets
    }

    weak var omniBar: OmniBar? {
        willSet {
            guard omniBar !== newValue || omniBar?.barView.superview !== self else { return }
            let isFloatingUIEnabled = isFloatingUIEnabledProvider?() ?? false
            if isFloatingUIEnabled {
                guard let currentBarView = omniBar?.barView, currentBarView.superview === self else { return }
                (currentBarView as? DefaultOmniBarView)?.safeAreaManagedByContainer = false
                currentBarView.removeFromSuperview()
            } else {
                (omniBar?.barView as? DefaultOmniBarView)?.safeAreaManagedByContainer = false
                omniBar?.barView.removeFromSuperview()
            }
        }
        didSet {
            guard oldValue !== omniBar || omniBar?.barView.superview !== self else { return }
            guard let omniBarView = omniBar?.barView else { return }
            let isFloatingUIEnabled = isFloatingUIEnabledProvider?() ?? false
            if isFloatingUIEnabled {
                guard coordinator?.isOmnibarInToolbar != true else { return }
                guard omniBarView.superview == nil || omniBarView.superview === self else { return }
            }

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
