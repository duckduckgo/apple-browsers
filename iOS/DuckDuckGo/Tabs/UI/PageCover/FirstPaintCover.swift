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
import DesignResourcesKit

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
    }

    /// How the cover takes over from the input panel that is leaving.
    struct Handoff {
        /// Frozen frame of the outgoing panel, placed at `exitSnapshotWindowFrame`.
        var exitSnapshot: UIView?
        var exitSnapshotWindowFrame: CGRect = .zero
        /// Expected background of the incoming page; nil keeps the panel colour.
        var destinationColor: UIColor?
    }

    /// Returns a closure that cancels the scheduled action.
    typealias Scheduler = (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void
    typealias FadeOut = (_ view: UIView, _ completion: @escaping @MainActor () -> Void) -> UIViewPropertyAnimator?
    typealias AnimateHandoff = (_ cover: UIView, _ exitSnapshot: UIView?, _ destinationColor: UIColor?) -> [UIViewPropertyAnimator]

    enum Constants {
        static let baseColor = UIColor(designSystemColor: .panel)
        /// Last resort before commit, when revealing can only show the old page; the app may still be re-issuing the request.
        static let commitTimeout: TimeInterval = 15
        /// After commit, while waiting for the new page to paint.
        static let paintTimeout: TimeInterval = 5
        /// Caps the wait after first layout; meaningful paint can be late or never fire.
        static let meaningfulPaintGrace: TimeInterval = 0.3

        static let revealDuration: TimeInterval = 0.18
        static let exitDuration: TimeInterval = 0.15
        static let colorHandoffDuration: TimeInterval = 0.25
        static let reducedMotionScale: Double = 0.5

        // https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/API/Cocoa/_WKRenderingProgressEvents.h
        static let firstVisuallyNonEmptyLayout: UInt = 1 << 1
        static let didRenderSignificantAmountOfText: UInt = 1 << 7
        static let firstMeaningfulPaint: UInt = 1 << 8
        static let meaningfulContent = didRenderSignificantAmountOfText | firstMeaningfulPaint
    }

    private(set) var phase: Phase = .idle
    private(set) var coverView: UIView?
    private(set) var exitSnapshotView: UIView?

    private let scheduler: Scheduler
    private let fadeOut: FadeOut
    private let animateHandoff: AnimateHandoff
    private var cancelTimeout: (() -> Void)?
    private var fadeAnimator: UIViewPropertyAnimator?
    private var handoffAnimators: [UIViewPropertyAnimator] = []
    private var coveredNavigation: CoveredNavigation = .notStarted

    /// The navigation the cover waits for; anything else belongs to the previous page.
    private enum CoveredNavigation {
        case notStarted
        /// Nil when WebKit didn't hand over a navigation object.
        case started(ObjectIdentifier?)
    }

    init(scheduler: @escaping Scheduler = FirstPaintCover.mainQueueScheduler,
         fadeOut: @escaping FadeOut = FirstPaintCover.defaultFadeOut,
         animateHandoff: @escaping AnimateHandoff = FirstPaintCover.defaultHandoff) {
        self.scheduler = scheduler
        self.fadeOut = fadeOut
        self.animateHandoff = animateHandoff
    }

    var isCovering: Bool { phase != .idle }

    /// Covers `webView` straight away; re-arming mid-fade brings the cover back without a flash.
    func arm(in container: UIView, above webView: UIView, handoff: Handoff = Handoff()) {
        stopAnimators()

        let view = coverView ?? makeCoverView()
        if view.superview !== container {
            container.insertSubview(view, aboveSubview: webView)
        }
        view.frame = container.bounds
        view.alpha = 1
        view.backgroundColor = Constants.baseColor
        coverView = view

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
        restartTimeout(after: Constants.commitTimeout)
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
        case .idle, .awaitingCommit:
            return
        case .awaitingPaint, .awaitingMeaningfulPaint:
            if events & Constants.meaningfulContent != 0 {
                reveal(animated: true)
            } else if phase == .awaitingPaint, events & Constants.firstVisuallyNonEmptyLayout != 0 {
                phase = .awaitingMeaningfulPaint
                restartTimeout(after: Constants.meaningfulPaintGrace)
            }
        }
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

    private func isCovered(_ navigation: AnyObject?) -> Bool {
        guard case .started(let coveredID) = coveredNavigation else { return false }
        guard let coveredID, let navigation else { return true }
        return coveredID == ObjectIdentifier(navigation)
    }

    private func reveal(animated: Bool) {
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
        view.removeFromSuperview()
        view.alpha = 1
    }

    private func restartTimeout(after delay: TimeInterval) {
        cancelTimeout?()
        cancelTimeout = scheduler(delay) { [weak self] in
            self?.reveal(animated: true)
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
        UIAccessibility.isReduceMotionEnabled ? base * Constants.reducedMotionScale : base
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
