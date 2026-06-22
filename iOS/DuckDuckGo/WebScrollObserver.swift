//
//  WebScrollObserver.swift
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
import OSLog
import QuartzCore
import Core

/// Detects the symptom of the hard-to-reproduce "web page visible, taps work, scroll dead" freeze:
/// the user drags to scroll a scrollable web page and the content doesn't move, repeatedly.
///
/// Owned per `TabViewController`, attached to `webViewContainer` via a passive bystander recognizer that
/// never interferes with scrolling or taps. Detection is intentionally web-only: the recognizer is on the
/// web container (not the window) and "did it move" is measured against the web view's own `contentOffset`,
/// so it counts failed drags on the page itself — the canonical first symptom. The freeze is actually
/// window-wide (a modal like Settings presented over the page is frozen too, even though it's a brand-new
/// view), but we only count where we own the scroll view; the window-wide nature is captured instead by the
/// app-wide wedge scan (`firstWedgedRecognizer`). Discrete taps keep flowing during a freeze, so the
/// recognizer still receives the drag touches it needs to classify.
///
/// Fires two pixels: the symptom signal (`debugInteractionRepeatedFailedScroll`) and a mechanism signal
/// (`debugInteractionWedgedRecognizer`, via `checkForWedgedRecognizer`). Logs every failed attempt as a
/// breadcrumb so the Interaction Diagnostics snapshot has the recent history even below the pixel threshold.
/// No Swift concurrency — the post-gesture and wedge re-checks use `asyncAfter` on the main queue.
/// `firePixel*` closures are injected so the detectors are unit-testable without the static pipeline.
@MainActor
final class WebScrollObserver: NSObject {

    private enum Constant {
        static let minScrollableRange: CGFloat = 64
        static let minHeadroom: CGFloat = 16
        static let minVerticalDrag: CGFloat = 48
        static let verticalDominance: CGFloat = 1.5
        static let movedThreshold: CGFloat = 3
        static let postEndRecheck: TimeInterval = 0.2
        static let streakThreshold = 3
        static let minRegionSpread = 2
        static let streakWindow: TimeInterval = 30
        static let wedgeRecheck: TimeInterval = 1.0
    }

    private weak var container: UIView?
    private let scrollViewProvider: () -> UIScrollView?
    private let currentURL: () -> URL?
    private let firePixelDailyAndCount: (Pixel.Event, [String: String]) -> Void
    /// Debug-only freeze capture, injected by `TabViewController` only when `webScrollFreezeCapture`
    /// is on. The production observer (symptom detection + pixels) is unaffected — default is a no-op.
    private let captureFreeze: () -> Void
    private let now: () -> Date

    private var recognizer: WebScrollObserverGestureRecognizer?
    private var dragStartOffsetY: CGFloat = 0

    private var failureStreak = 0
    private var lastFailureAt: Date?
    private var streakDirections: Set<String> = []
    private var streakRegions: Set<Int> = []
    private var highestBucketFired: String?
    private var capturedThisStreak = false

    private weak var wedgeCandidate: UIGestureRecognizer?

    /// Human-readable last outcome, surfaced in the Interaction Diagnostics snapshot.
    private(set) var recentStatus = "no scroll attempt observed yet"

    init(container: UIView,
         scrollView: @escaping () -> UIScrollView?,
         currentURL: @escaping () -> URL?,
         firePixelDailyAndCount: @escaping (Pixel.Event, [String: String]) -> Void = {
            DailyPixel.fireDailyAndCount(pixel: $0, withAdditionalParameters: $1)
         },
         now: @escaping () -> Date = { Date() },
         captureFreeze: @escaping () -> Void = {}) {
        self.container = container
        self.scrollViewProvider = scrollView
        self.currentURL = currentURL
        self.firePixelDailyAndCount = firePixelDailyAndCount
        self.now = now
        self.captureFreeze = captureFreeze
        super.init()
    }

    func install() {
        guard recognizer == nil, let container else { return }
        let recognizer = WebScrollObserverGestureRecognizer(target: nil, action: nil)
        recognizer.delegate = self
        recognizer.onBegan = { [weak self] in self?.dragBegan() }
        recognizer.onEnded = { [weak self] dx, dy, start in self?.dragEnded(dx: dx, dy: dy, start: start) }
        container.addGestureRecognizer(recognizer)
        self.recognizer = recognizer
    }

    /// Reset the failure streak — call on navigation, tab disappearance, or backgrounding.
    func reset() {
        failureStreak = 0
        lastFailureAt = nil
        streakDirections = []
        streakRegions = []
        highestBucketFired = nil
        capturedThisStreak = false
    }

    // MARK: - Symptom detection (C1)

    private func dragBegan() {
        dragStartOffsetY = scrollViewProvider()?.contentOffset.y ?? 0
    }

    private func dragEnded(dx: CGFloat, dy: CGFloat, start: CGPoint) {
        // Capture the start offset by value now — a second drag within the recheck window would
        // otherwise overwrite `dragStartOffsetY` before this closure runs.
        let startOffsetY = dragStartOffsetY
        // Re-sample after a beat so late settling counts as movement.
        DispatchQueue.main.asyncAfter(deadline: .now() + Constant.postEndRecheck) { [weak self] in
            self?.classifyDrag(dx: dx, dy: dy, startOffsetY: startOffsetY, startScreenY: start.y)
        }
    }

    /// Internal (not private) so unit tests can drive classification directly, bypassing the post-gesture
    /// `asyncAfter` recheck. In production this is only ever called from `dragEnded`.
    func classifyDrag(dx: CGFloat, dy: CGFloat, startOffsetY: CGFloat, startScreenY: CGFloat) {
        guard isEligible(), let scrollView = scrollViewProvider() else { return }

        // Only count vertical-dominant drags long enough to be a real scroll attempt.
        guard abs(dy) >= Constant.minVerticalDrag, abs(dy) >= abs(dx) * Constant.verticalDominance else {
            return
        }

        let metrics = scrollMetrics(scrollView)
        let fingerUp = dy < 0
        let hasHeadroom = fingerUp
            ? startOffsetY < metrics.maxY - Constant.minHeadroom
            : startOffsetY > metrics.minY + Constant.minHeadroom
        // At the top/bottom edge there's nothing to scroll in this direction — skip, don't reset the streak.
        guard hasHeadroom else { return }

        let moved = abs(scrollView.contentOffset.y - startOffsetY) >= Constant.movedThreshold
        if moved {
            reset()
            recentStatus = "last drag scrolled OK (\(formatted(now())))"
        } else {
            registerFailedAttempt(direction: fingerUp ? "up" : "down", startScreenY: startScreenY)
        }
    }

    private func registerFailedAttempt(direction: String, startScreenY: CGFloat) {
        if let last = lastFailureAt, now().timeIntervalSince(last) > Constant.streakWindow {
            failureStreak = 0
            streakDirections = []
            streakRegions = []
            highestBucketFired = nil
            capturedThisStreak = false
        }
        failureStreak += 1
        lastFailureAt = now()
        streakDirections.insert(direction)
        streakRegions.insert(screenRegion(forY: startScreenY))
        recentStatus = "\(failureStreak) failed scroll attempt(s) (\(formatted(now())))"
        Logger.interaction.error("Web scroll did not move: failed attempt #\(self.failureStreak, privacy: .public), direction \(direction, privacy: .public), regions \(self.streakRegions.count, privacy: .public)")

        guard failureStreak >= Constant.streakThreshold else { return }

        // Capture LIBERALLY (once per streak, before the precision gate) so a real freeze always leaves the
        // touch/recognizer census. Injected closure: a no-op in production, the real capture only when the
        // debug flag `webScrollFreezeCapture` is on. The pixel below ships to everyone regardless.
        if !capturedThisStreak {
            capturedThisStreak = true
            captureFreeze()
        }

        // Fire the population pixel ONLY for our case. A benign content-consumed drag (carousel, map,
        // overflow scroller, sticky element) is localised; the genuine freeze fails EVERYWHERE — so
        // require the failed drags to span ≥2 distinct screen regions before counting it as our freeze.
        guard streakRegions.count >= Constant.minRegionSpread else { return }
        let bucket = attemptBucket(failureStreak)
        guard bucket != highestBucketFired else { return }
        highestBucketFired = bucket
        // Scan for a wedged recognizer at the moment we confirm the freeze (not just at viewDidAppear),
        // so `none_wedged` is meaningful evidence for the phantom-touch hypothesis.
        let mechanism: String
        if let wedged = Self.firstWedgedRecognizer() {
            mechanism = "wedged:\(Self.bucket(for: wedged))"
        } else {
            mechanism = "none_wedged"
        }
        firePixelDailyAndCount(.debugInteractionRepeatedFailedScroll, [
            "attempt_count_bucket": bucket,
            "direction": streakDirections.count > 1 ? "mixed" : (streakDirections.first ?? "mixed"),
            "mechanism": mechanism
        ])
    }

    /// Bucket the drag's start position into vertical thirds of the container, for the spatial-spread gate.
    private func screenRegion(forY y: CGFloat) -> Int {
        let height = container?.bounds.height ?? UIScreen.main.bounds.height
        guard height > 0 else { return 0 }
        return max(0, min(2, Int(y / (height / 3))))
    }

    // MARK: - Wedged-recognizer detection (C2)

    /// Look for a non-scroll recognizer stuck active with no touches; confirm with a re-check ~1s later
    /// (to exclude transient cancellation/reset states) before firing.
    func checkForWedgedRecognizer() {
        guard isEligible(), let wedged = Self.firstWedgedRecognizer() else { return }
        wedgeCandidate = wedged
        DispatchQueue.main.asyncAfter(deadline: .now() + Constant.wedgeRecheck) { [weak self, weak wedged] in
            guard let self, let wedged, let candidate = self.wedgeCandidate, candidate === wedged,
                  Self.isWedged(candidate) else { return }
            self.wedgeCandidate = nil
            Logger.interaction.error("Wedged recognizer detected: \(Self.bucket(for: candidate), privacy: .public)")
            self.firePixelDailyAndCount(.debugInteractionWedgedRecognizer, [
                "recognizer": Self.bucket(for: candidate)
            ])
        }
    }

    // MARK: - Helpers

    private func isEligible() -> Bool {
        guard let scheme = currentURL()?.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let scrollView = scrollViewProvider() else { return false }
        let metrics = scrollMetrics(scrollView)
        return metrics.maxY - metrics.minY > Constant.minScrollableRange
    }

    private func scrollMetrics(_ scrollView: UIScrollView) -> (minY: CGFloat, maxY: CGFloat) {
        let minY = -scrollView.adjustedContentInset.top
        let maxY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        return (minY, max(minY, maxY))
    }

    private func attemptBucket(_ count: Int) -> String {
        switch count {
        case ..<4: return "3"
        case 4...5: return "4_5"
        default: return "6_plus"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private func formatted(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static func isWedged(_ recognizer: UIGestureRecognizer) -> Bool {
        (recognizer.state == .began || recognizer.state == .changed) && recognizer.numberOfTouches == 0
    }

    private static func firstWedgedRecognizer() -> UIGestureRecognizer? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows {
            if let match = firstWedged(in: window) { return match }
        }
        return nil
    }

    private static func firstWedged(in view: UIView) -> UIGestureRecognizer? {
        if let wedged = view.gestureRecognizers?.first(where: isWedged) { return wedged }
        for subview in view.subviews {
            if let match = firstWedged(in: subview) { return match }
        }
        return nil
    }

    static func bucket(for recognizer: UIGestureRecognizer) -> String {
        if recognizer is UnifiedInputSwipeTabsPanGestureRecognizer { return "swipe_tabs" }
        if recognizer is UIScreenEdgePanGestureRecognizer { return "edge_pan" }
        if recognizer is UITapGestureRecognizer { return "tap" }
        if recognizer is UILongPressGestureRecognizer { return "long_press" }
        let typeName = String(describing: type(of: recognizer)).lowercased()
        if typeName.contains("refresh") || typeName.contains("pullto") { return "pull_to_refresh_pan" }
        if let scrollView = recognizer.view as? UIScrollView, recognizer === scrollView.panGestureRecognizer {
            return "web_scroll_pan"
        }
        if recognizer is UIPanGestureRecognizer { return "other_pan" }
        return "other"
    }
}

extension WebScrollObserver: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// A pure bystander: it observes the touch stream to measure drag distance but never recognizes, cancels,
/// or blocks any other gesture (so it can't interfere with scrolling or taps).
final class WebScrollObserverGestureRecognizer: UIGestureRecognizer {

    var onBegan: (() -> Void)?
    var onEnded: ((CGFloat, CGFloat, CGPoint) -> Void)?

    private var startPoint: CGPoint = .zero
    private var lastPoint: CGPoint = .zero

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view, let touch = touches.first else { return }
        startPoint = touch.location(in: view)
        lastPoint = startPoint
        onBegan?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view, let touch = touches.first else { return }
        lastPoint = touch.location(in: view)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish()
    }

    private func finish() {
        onEnded?(lastPoint.x - startPoint.x, lastPoint.y - startPoint.y, startPoint)
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

// MARK: - Recovery (manual debug rungs — internal only)

/// Self-heal actions for the web-scroll-freeze. `recover()` is the surgical reset (pan + wedged recognizers);
/// the individual rungs are exposed for the debug Recovery screen to find the minimal sufficient action.
/// Debug-only and manual for now — there is no production auto-recovery; that is productionised in Part 3.
/// All are idempotent and meant to run BETWEEN gestures (no active touch).
@MainActor
enum WebScrollFreezeRecovery {

    enum Rung { case flushAppRecognizers, bounceWindowInteraction, flushAll }

    /// Surgical self-heal: reset only the recognisers that can actually block scrolling — pan recognisers
    /// (incl. the web scroll view's own pan) and anything stuck mid-gesture. Does NOT touch window
    /// interaction (toggling `isUserInteractionEnabled` orphans touches into a stuck Stationary/nil-window
    /// state — the very freeze we're fixing) and leaves taps untouched.
    @discardableResult
    static func recover() -> String {
        let count = resetBlockingRecognizers()
        Logger.interaction.error("Manual recovery ran: reset \(count, privacy: .public) pan/wedged recognizers")
        return "recover: reset \(count) pan/wedged recognizers"
    }

    /// Reset pan recognisers + any recogniser stuck in `began`/`changed`. Skips UIKit-internal (`_UI…`)
    /// system gates and all taps. Typically a handful, not the whole app.
    @discardableResult
    private static func resetBlockingRecognizers() -> Int {
        var count = 0
        for window in windows() {
            forEachRecognizer(in: window) { recognizer in
                guard !String(describing: type(of: recognizer)).hasPrefix("_") else { return }
                let isPan = recognizer is UIPanGestureRecognizer
                let isWedged = recognizer.state == .began || recognizer.state == .changed
                guard isPan || isWedged else { return }
                recognizer.isEnabled = false
                recognizer.isEnabled = true
                count += 1
            }
        }
        return count
    }

    @discardableResult
    static func runRung(_ rung: Rung) -> String {
        switch rung {
        case .flushAppRecognizers: return "reset \(flushAppRecognizers()) app recognizers"
        case .bounceWindowInteraction: bounceWindowInteraction(); return "bounced window interaction"
        case .flushAll: return "reset \(flushAll()) recognizers (all, incl. system)"
        }
    }

    /// Reset every non-UIKit-internal recogniser (skip `_UI…` classes so we don't disturb system gates).
    /// This also re-arms the web scroll view's own pan.
    @discardableResult
    private static func flushAppRecognizers() -> Int {
        var count = 0
        for window in windows() {
            forEachRecognizer(in: window) { recognizer in
                guard !String(describing: type(of: recognizer)).hasPrefix("_") else { return }
                recognizer.isEnabled = false
                recognizer.isEnabled = true
                count += 1
            }
        }
        return count
    }

    /// Cancel any touches the gesture environment is still tracking (the phantom-touch flush). The async
    /// re-enable lets UIKit process the cancellation; the gap is one run-loop tick, imperceptible.
    private static func bounceWindowInteraction() {
        for window in windows() where window.isKeyWindow {
            window.isUserInteractionEnabled = false
            DispatchQueue.main.async { window.isUserInteractionEnabled = true }
        }
    }

    @discardableResult
    private static func flushAll() -> Int {
        var count = 0
        for window in windows() {
            forEachRecognizer(in: window) { recognizer in
                recognizer.isEnabled = false
                recognizer.isEnabled = true
                count += 1
            }
        }
        return count
    }

    private static func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }

    private static func forEachRecognizer(in view: UIView, _ body: (UIGestureRecognizer) -> Void) {
        view.gestureRecognizers?.forEach(body)
        view.subviews.forEach { forEachRecognizer(in: $0, body) }
    }
}
