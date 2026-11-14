//
//  FirstPaintCover.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import WebKit
import DesignResourcesKit
import PixelKit

/// Hides the previous page after a typed search or URL until the new page first paints.
///
/// Choreography: the outgoing input panel's snapshot fades off the cover while the cover moves to the
/// expected page colour; once real content paints, the page fades in over a matching background.
@MainActor
final class FirstPaintCover {

    enum Phase: Equatable {
        case idle
        case awaitingCommit
        case awaitingPaint
        /// Something is on screen; waiting briefly for real content so the reveal isn't a near-empty page.
        case awaitingMeaningfulPaint
        /// A results page has laid out; waiting for its first result, which its tabs row fills in alongside.
        case awaitingContent
    }

    /// How the cover takes over from the input panel that is leaving.
    struct Handoff {
        /// Frozen frame of the outgoing panel, placed at `exitSnapshotWindowFrame`.
        var exitSnapshot: UIView?
        var exitSnapshotWindowFrame: CGRect = .zero
        /// Expected background of the incoming page; nil keeps the panel colour.
        var destinationColor: UIColor?
        /// Outlines the results page while it loads; only for searches, never for websites.
        var showsSearchResultsSkeleton = false
        /// The results page header as it last rendered; replaces the header's outline when it fits.
        var searchResultsHeader: UIImage?
        /// Whether the page shows what it's for yet; set for searches, where first layout is a half-built header.
        var isContentReady: ContentCheck?
    }

    /// Reports whether the covered page shows its content yet.
    typealias ContentCheck = (_ completion: @escaping @MainActor (Bool) -> Void) -> Void

    /// Returns a closure that cancels the scheduled action.
    typealias Scheduler = (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void
    typealias FadeOut = (_ view: UIView, _ completion: @escaping @MainActor () -> Void) -> UIViewPropertyAnimator?
    typealias AnimateHandoff = (_ cover: UIView, _ exitSnapshot: UIView?, _ destinationColor: UIColor?) -> [UIViewPropertyAnimator]

    enum Constants {
        static let baseColor = UIColor(designSystemColor: .panel)
        /// Last resort before commit, when revealing can only show the old page; the app may still be re-issuing the request.
        static let commitTimeout: TimeInterval = 15
        /// After a main-frame policy decision that starts no provisional load, such as a cancel with nothing re-issued.
        static let noNavigationGrace: TimeInterval = 1
        /// After commit, while waiting for the new page to paint.
        static let paintTimeout: TimeInterval = 5
        /// Caps the wait after first layout; meaningful paint can be late or never fire.
        static let meaningfulPaintGrace: TimeInterval = 0.3
        /// Caps the wait for a results page's first result after first layout; a page may have none.
        static let contentGrace: TimeInterval = 2
        static let contentPollInterval: TimeInterval = 0.1

        static let revealDuration: TimeInterval = 0.18
        static let exitDuration: TimeInterval = 0.15
        static let colorHandoffDuration: TimeInterval = 0.25
        static let reducedMotionScale: Double = 0.5

        // https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/API/Cocoa/_WKRenderingProgressEvents.h
        static let firstVisuallyNonEmptyLayout: UInt = 1 << 1
        static let didRenderSignificantAmountOfText: UInt = 1 << 7
        static let firstMeaningfulPaint: UInt = 1 << 8
        static let meaningfulContent = didRenderSignificantAmountOfText | firstMeaningfulPaint
        /// WebKit only reports the first layouts unless the web view opts into the rest.
        static let observedEvents = firstVisuallyNonEmptyLayout | meaningfulContent
    }

    private(set) var phase: Phase = .idle
    private(set) var coverView: UIView?
    private(set) var exitSnapshotView: UIView?
    private(set) var skeletonView: SearchResultsSkeletonView?

    private let scheduler: Scheduler
    private let fadeOut: FadeOut
    private let animateHandoff: AnimateHandoff
    private let pixelFiring: PixelFiring?
    private var destination: FirstPaintCoverPixel.Destination = .website
    private var cancelTimeout: (() -> Void)?
    private var fadeAnimator: UIViewPropertyAnimator?
    private var handoffAnimators: [UIViewPropertyAnimator] = []
    private var coveredNavigation: CoveredNavigation = .notStarted
    private var pendingPolicyDecisions = 0
    private var armedAt: CFTimeInterval?
    private var cancelHold: (() -> Void)?
    private var contentCheck: ContentCheck?
    /// Moves on with every arm, so a content answer for an earlier load can't lift a later cover.
    private var armGeneration = 0
    private var cancelContentPoll: (() -> Void)?

    /// The navigation the cover waits for; anything else belongs to the previous page.
    private enum CoveredNavigation {
        case notStarted
        /// Nil when WebKit didn't hand over a navigation object.
        case started(ObjectIdentifier?)
    }

    init(scheduler: @escaping Scheduler = FirstPaintCover.mainQueueScheduler,
         fadeOut: @escaping FadeOut = FirstPaintCover.defaultFadeOut,
         animateHandoff: @escaping AnimateHandoff = FirstPaintCover.defaultHandoff,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.scheduler = scheduler
        self.fadeOut = fadeOut
        self.animateHandoff = animateHandoff
        self.pixelFiring = pixelFiring
    }

    var isCovering: Bool { phase != .idle }

    /// Covers `webView` straight away; re-arming mid-fade brings the cover back without a flash.
    /// `contentTop` is where the page's content starts in `container`, below a floating address bar.
    func arm(in container: UIView, above webView: UIView, handoff: Handoff = Handoff(), contentTop: CGFloat = 0) {
        stopAnimators()
        cancelDebugHold()
        cancelContentPolling()
        armedAt = CACurrentMediaTime()
        armGeneration += 1
        contentCheck = handoff.isContentReady
        destination = handoff.showsSearchResultsSkeleton ? .search : .website

        let view = coverView ?? makeCoverView()
        if view.superview !== container {
            container.insertSubview(view, aboveSubview: webView)
        }
        view.frame = container.bounds
        view.alpha = 1
        view.backgroundColor = Constants.baseColor
        coverView = view

        skeletonView?.removeFromSuperview()
        skeletonView = nil
        if handoff.showsSearchResultsSkeleton {
            let skeleton = SearchResultsSkeletonView(frame: view.bounds)
            skeleton.contentTop = contentTop
            skeleton.pageView = webView
            skeleton.headerImage = handoff.searchResultsHeader
            view.insertSubview(skeleton, at: 0)
            // Lay out now, or an animation already running, such as the input collapsing, carries the header in from its corner.
            UIView.performWithoutAnimation { skeleton.layoutIfNeeded() }
            skeleton.appear()
            skeletonView = skeleton
        }

        exitSnapshotView?.removeFromSuperview()
        exitSnapshotView = handoff.exitSnapshot
        if let snapshot = handoff.exitSnapshot {
            // Cover spans the container's bounds, so container coordinates are cover coordinates.
            snapshot.frame = container.convert(handoff.exitSnapshotWindowFrame, from: nil)
            snapshot.isUserInteractionEnabled = false
            view.addSubview(snapshot)
        }
        handoffAnimators = animateHandoff(view, handoff.exitSnapshot, handoff.destinationColor)

        phase = .awaitingCommit
        coveredNavigation = .notStarted
        pendingPolicyDecisions = 0
        restartTimeout(after: Constants.commitTimeout)
    }

    /// A main-frame policy check can wait on content blocking or a re-issued request, so it gets the full commit window.
    func willDecidePolicy() {
        guard isAwaitingStart else { return }
        pendingPolicyDecisions += 1
        restartTimeout(after: Constants.commitTimeout)
    }

    /// Cancelled and same-document navigations never start a provisional load, so nothing else would lift the cover.
    /// A re-issued request can enter `willDecidePolicy` before the cancel lands, so the grace waits for every pending decision.
    func didDecidePolicy(allowed: Bool, isSameDocument: Bool) {
        // Decisions requested before arming belong to the previous page.
        guard isAwaitingStart, pendingPolicyDecisions > 0 else { return }
        pendingPolicyDecisions -= 1
        if allowed && isSameDocument {
            reveal(animated: true)
        } else if pendingPolicyDecisions == 0 {
            restartTimeout(after: Constants.noNavigationGrace)
        }
    }

    /// The first navigation after arming is the covered one; a later start, such as a re-issued SERP request, replaces it.
    func didStartNavigation(_ navigation: AnyObject?) {
        guard phase == .awaitingCommit else { return }
        coveredNavigation = .started(navigation.map(ObjectIdentifier.init))
        restartTimeout(after: Constants.commitTimeout)
    }

    func didCommit(_ navigation: AnyObject?) {
        guard phase == .awaitingCommit, isCovered(navigation) else { return }
        phase = .awaitingPaint
        restartTimeout(after: Constants.paintTimeout)
    }

    func renderingProgressDidChange(_ events: UInt) {
        // Milestones before commit belong to the previous page.
        switch phase {
        case .idle, .awaitingCommit, .awaitingContent:
            return
        case .awaitingPaint, .awaitingMeaningfulPaint:
            let hasLaidOut = events & Constants.firstVisuallyNonEmptyLayout != 0
            if let contentCheck, events & Constants.meaningfulContent != 0 || hasLaidOut {
                awaitContent(contentCheck)
            } else if events & Constants.meaningfulContent != 0 {
                reveal(animated: true)
            } else if phase == .awaitingPaint, hasLaidOut {
                phase = .awaitingMeaningfulPaint
                restartTimeout(after: Constants.meaningfulPaintGrace)
            }
        }
    }

    /// The covered page finished loading; whatever it shows now is as good as it gets.
    func didFinish(_ navigation: AnyObject?) {
        guard [.awaitingPaint, .awaitingMeaningfulPaint, .awaitingContent].contains(phase), isCovered(navigation) else { return }
        reveal(animated: true)
    }

    func navigationDidFail(_ error: Error, navigation: AnyObject?) {
        guard isCovering, isCovered(navigation) else { return }
        let nsError = error as NSError
        // Cancelled covers re-issued SERP requests and replaced navigations; a newer load will follow.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        reveal(animated: true)
    }

    /// Ends the cover now, e.g. on stop, process termination or tab teardown.
    func cancel() {
        guard isCovering || fadeAnimator != nil else { return }
        reveal(animated: false)
    }

    /// Keeps the cover up as long again as the load took (times the slowdown), so its stages are visible.
    private func holdForDebugSlowdown() -> Bool {
        guard Self.debugSlowdown > 1 else { return false }
        if cancelHold != nil { return true }
        guard let armedAt else { return false }
        self.armedAt = nil
        let hold = (CACurrentMediaTime() - armedAt) * (Self.debugSlowdown - 1)
        cancelTimeout?()
        cancelTimeout = nil
        cancelHold = scheduler(hold) { [weak self] in
            self?.cancelHold = nil
            self?.reveal(animated: true)
        }
        return true
    }

    private func cancelDebugHold() {
        cancelHold?()
        cancelHold = nil
    }

    /// Asks the page until its content is in, or until the grace runs out.
    private func awaitContent(_ check: @escaping ContentCheck) {
        phase = .awaitingContent
        restartTimeout(after: Constants.contentGrace)
        pollContent(check)
    }

    private func pollContent(_ check: @escaping ContentCheck) {
        let generation = armGeneration
        check { [weak self] isReady in
            guard let self, self.isAwaitingContent(armedIn: generation) else { return }
            guard !isReady else { return self.reveal(animated: true) }
            self.cancelContentPoll = self.scheduler(Constants.contentPollInterval) { [weak self] in
                guard let self, self.isAwaitingContent(armedIn: generation) else { return }
                self.pollContent(check)
            }
        }
    }

    private func isAwaitingContent(armedIn generation: Int) -> Bool {
        phase == .awaitingContent && armGeneration == generation
    }

    private func cancelContentPolling() {
        cancelContentPoll?()
        cancelContentPoll = nil
    }

    private var isAwaitingStart: Bool {
        guard phase == .awaitingCommit, case .notStarted = coveredNavigation else { return false }
        return true
    }

    private func isCovered(_ navigation: AnyObject?) -> Bool {
        guard case .started(let coveredID) = coveredNavigation else { return false }
        guard let coveredID, let navigation else { return true }
        return coveredID == ObjectIdentifier(navigation)
    }

    private func reveal(animated: Bool) {
        if animated, holdForDebugSlowdown() { return }
        cancelDebugHold()
        cancelContentPolling()
        phase = .idle
        coveredNavigation = .notStarted
        cancelTimeout?()
        cancelTimeout = nil

        guard let view = coverView else { return }
        guard animated else {
            stopAnimators()
            removeCover(view)
            return
        }
        // The hand-off may still be running on a fast load; it finishes under the fade.
        fadeAnimator = fadeOut(view) { [weak self, weak view] in
            guard let self, let view, self.phase == .idle else { return }
            self.stopAnimators()
            self.removeCover(view)
        }
    }

    private func stopAnimators() {
        fadeAnimator?.stopAnimation(true)
        fadeAnimator = nil
        handoffAnimators.forEach { $0.stopAnimation(true) }
        handoffAnimators = []
    }

    private func removeCover(_ view: UIView) {
        exitSnapshotView?.removeFromSuperview()
        exitSnapshotView = nil
        skeletonView?.removeFromSuperview()
        skeletonView = nil
        view.removeFromSuperview()
        view.alpha = 1
    }

    private func restartTimeout(after delay: TimeInterval) {
        cancelTimeout?()
        cancelTimeout = scheduler(delay) { [weak self] in
            guard let self else { return }
            // Commit window ran out: lifting on the old page. Other waits ending is normal.
            if delay == Constants.commitTimeout, self.phase == .awaitingCommit {
                self.pixelFiring?.fire(FirstPaintCoverPixel.commitTimeout(self.destination), frequency: .dailyAndCount)
            }
            self.reveal(animated: true)
        }
    }

    private func makeCoverView() -> UIView {
        let view = UIView()
        view.backgroundColor = Constants.baseColor
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isAccessibilityElement = false
        return view
    }
}

extension FirstPaintCover {

    static let mainQueueScheduler: Scheduler = { delay, action in
        let item = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }

    private static func duration(_ base: TimeInterval) -> TimeInterval {
        let scaled = base * debugSlowdown
        return UIAccessibility.isReduceMotionEnabled ? scaled * Constants.reducedMotionScale : scaled
    }

    /// Testing aid for debug builds: launch with `-firstPaintCoverSlowdown 2` to run the cover at half speed.
    static var debugSlowdown: Double {
        #if DEBUG
        return max(1, UserDefaults.standard.double(forKey: "firstPaintCoverSlowdown"))
        #else
        return 1
        #endif
    }

    // Strong ease-out: responsive start for things entering or leaving.
    private static let strongEaseOut = (CGPoint(x: 0.23, y: 1), CGPoint(x: 0.32, y: 1))
    // Ease-in-out: for a colour that changes in place.
    private static let easeInOut = (CGPoint(x: 0.45, y: 0), CGPoint(x: 0.25, y: 1))

    /// The page fades in over the cover; opacity only, so Reduce Motion just shortens it.
    static let defaultFadeOut: FadeOut = { view, completion in
        let animator = UIViewPropertyAnimator(duration: duration(Constants.revealDuration),
                                              controlPoint1: strongEaseOut.0,
                                              controlPoint2: strongEaseOut.1) {
            view.alpha = 0
        }
        animator.addCompletion { position in
            guard position == .end else { return }
            MainActor.assumeIsolated { completion() }
        }
        animator.startAnimation()
        return animator
    }

    /// Suggestions leave first and fast; the background settles on the page colour alongside the bar collapse.
    static let defaultHandoff: AnimateHandoff = { cover, exitSnapshot, destinationColor in
        var animators: [UIViewPropertyAnimator] = []
        if let exitSnapshot {
            let exit = UIViewPropertyAnimator(duration: duration(Constants.exitDuration),
                                              controlPoint1: strongEaseOut.0,
                                              controlPoint2: strongEaseOut.1) {
                exitSnapshot.alpha = 0
            }
            exit.startAnimation()
            animators.append(exit)
        }
        if let destinationColor {
            let color = UIViewPropertyAnimator(duration: duration(Constants.colorHandoffDuration),
                                               controlPoint1: easeInOut.0,
                                               controlPoint2: easeInOut.1) {
                cover.backgroundColor = destinationColor
            }
            color.startAnimation()
            animators.append(color)
        }
        return animators
    }
}

extension WKWebView {

    /// Adds `events` to the rendering milestones WebKit reports to the navigation delegate.
    func observeRenderingProgressEvents(_ events: UInt) {
        let getter = NSSelectorFromString("_observedRenderingProgressEvents")
        let setter = NSSelectorFromString("_setObservedRenderingProgressEvents:")
        guard let getMethod = class_getInstanceMethod(object_getClass(self), getter),
              let setMethod = class_getInstanceMethod(object_getClass(self), setter) else { return }

        typealias Getter = @convention(c) (WKWebView, Selector) -> UInt
        typealias Setter = @convention(c) (WKWebView, Selector, UInt) -> Void
        let current = unsafeBitCast(method_getImplementation(getMethod), to: Getter.self)(self, getter)
        guard current & events != events else { return }
        unsafeBitCast(method_getImplementation(setMethod), to: Setter.self)(self, setter, current | events)
    }
}
