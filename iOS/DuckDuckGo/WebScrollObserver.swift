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
/// (`debugInteractionWedgedRecognizer`, via `checkForWedgedRecognizer`). Logs every failed attempt so the
/// Interaction Diagnostics snapshot has the recent history even below the pixel threshold.
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
    private var autoRecoveredThisStreak = false
    private var pendingOutcomeCheck = false
    private var outcomeArmedAt: Date?

    private weak var wedgeCandidate: UIGestureRecognizer?

    /// Human-readable last outcome, surfaced in the Interaction Diagnostics snapshot.
    private(set) var recentStatus = "no scroll attempt observed yet"

    /// Called exactly once per confirmed freeze episode, after the region-spread gate passes. Returns `true`
    /// only if it actually ran the recovery (so the outcome pixel is armed ONLY then). The default returns
    /// `false`, keeping the production path unchanged; inject a real action only when auto-recovery is enabled.
    private let autoRecover: () -> Bool

    init(container: UIView,
         scrollView: @escaping () -> UIScrollView?,
         currentURL: @escaping () -> URL?,
         firePixelDailyAndCount: @escaping (Pixel.Event, [String: String]) -> Void = {
            DailyPixel.fireDailyAndCount(pixel: $0, withAdditionalParameters: $1)
         },
         now: @escaping () -> Date = { Date() },
         captureFreeze: @escaping () -> Void = {},
         autoRecover: @escaping () -> Bool = { false }) {
        self.container = container
        self.scrollViewProvider = scrollView
        self.currentURL = currentURL
        self.firePixelDailyAndCount = firePixelDailyAndCount
        self.now = now
        self.captureFreeze = captureFreeze
        self.autoRecover = autoRecover
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
        autoRecoveredThisStreak = false
        pendingOutcomeCheck = false
        outcomeArmedAt = nil
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
    ///
    /// Also resolves a pending auto-recovery outcome: a stale one (older than the streak window, with no
    /// real scroll attempt to resolve it) is dropped so it can't be mis-attributed to a later/unrelated
    /// drag; otherwise `recovery_outcome` fires on the next eligible vertical drag. reset() clears it on
    /// navigation / tab change / streak expiry.
    func classifyDrag(dx: CGFloat, dy: CGFloat, startOffsetY: CGFloat, startScreenY: CGFloat) {
        if pendingOutcomeCheck, let armedAt = outcomeArmedAt,
           now().timeIntervalSince(armedAt) > Constant.streakWindow {
            pendingOutcomeCheck = false
            outcomeArmedAt = nil
        }

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
        if pendingOutcomeCheck {
            pendingOutcomeCheck = false
            outcomeArmedAt = nil
            firePixelDailyAndCount(.debugInteractionRecoveryOutcome, ["outcome": moved ? "recovered" : "still_frozen"])
        }
        if moved {
            reset()
            recentStatus = "last drag scrolled OK (\(formatted(now())))"
        } else {
            registerFailedAttempt(direction: fingerUp ? "up" : "down", startScreenY: startScreenY)
        }
    }

    private func registerFailedAttempt(direction: String, startScreenY: CGFloat) {
        if let last = lastFailureAt, now().timeIntervalSince(last) > Constant.streakWindow {
            reset()
        }
        failureStreak += 1
        lastFailureAt = now()
        streakDirections.insert(direction)
        streakRegions.insert(screenRegion(forY: startScreenY))
        recentStatus = "\(failureStreak) failed scroll attempt(s) (\(formatted(now())))"
        Logger.interaction.error("Web scroll did not move: failed attempt #\(self.failureStreak, privacy: .public), direction \(direction, privacy: .public), regions \(self.streakRegions.count, privacy: .public)")

        guard failureStreak >= Constant.streakThreshold else { return }

        // Capture LIBERALLY (once per streak, before the precision gate) so a real freeze always leaves the
        // touch/recognizer snapshot. Injected closure: a no-op in production, the real capture only when the
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

        let scrollView = scrollViewProvider()
        firePixelDailyAndCount(.debugInteractionRepeatedFailedScroll, [
            "attempt_count_bucket": bucket,
            "direction": streakDirections.count > 1 ? "mixed" : (streakDirections.first ?? "mixed"),
            "mechanism": mechanism,
            "web_scroll_pan_state": webScrollPanState(scrollView),
            "web_scroll_pan_touches": webScrollPanTouches(scrollView),
            "wk_deferring_count_bucket": deferringCountBucket(),
            "wk_possible_zero_touch_count_bucket": possibleZeroTouchCountBucket(),
            "window_active_no_touch_bucket": windowActiveNoTouchBucket()
        ])

        if !autoRecoveredThisStreak {
            if autoRecover() {
                autoRecoveredThisStreak = true
                pendingOutcomeCheck = true
                outcomeArmedAt = now()
            }
        }
    }

    // MARK: - Production pixel param helpers

    func webScrollPanState(_ scrollView: UIScrollView?) -> String {
        guard let pan = scrollView?.panGestureRecognizer else { return "none" }
        switch pan.state {
        case .possible:   return "possible"
        case .began:      return "began"
        case .changed:    return "changed"
        case .ended:      return "ended"
        case .cancelled:  return "cancelled"
        case .failed:     return "failed"
        @unknown default: return "possible"
        }
    }

    func webScrollPanTouches(_ scrollView: UIScrollView?) -> String {
        guard let pan = scrollView?.panGestureRecognizer else { return "0" }
        switch pan.numberOfTouches {
        case 0:  return "0"
        case 1:  return "1"
        default: return "2_plus"
        }
    }

    /// Maps a raw recognizer count to the 4-level param bucket (deferring-gate + possible-zero-touch params).
    /// Pure, so it is unit-tested directly — the live window scans that feed it read `UIApplication` state
    /// that a test host can't control deterministically.
    static func countBucket3Plus(_ count: Int) -> String {
        switch count {
        case 0:  return "0"
        case 1:  return "1"
        case 2:  return "2"
        default: return "3_plus"
        }
    }

    /// Maps a raw recognizer count to the 2-level param bucket (window-active-no-touch param, where a single
    /// active-but-touchless recognizer is already a strong signal). Pure — see `countBucket3Plus`.
    static func countBucket2Plus(_ count: Int) -> String {
        switch count {
        case 0:  return "0"
        case 1:  return "1"
        default: return "2_plus"
        }
    }

    private func deferringCountBucket() -> String {
        guard let container else { return "0" }
        return Self.countBucket3Plus(WebScrollFreezeDebugProbe.deferringGates(in: container).count)
    }

    static func possibleZeroTouchCountRaw() -> Int {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var count = 0
        for window in windows {
            forEachPossibleZeroTouchWebKitRecognizer(in: window) { _ in count += 1 }
        }
        return count
    }

    static func forEachPossibleZeroTouchWebKitRecognizer(in view: UIView, _ body: (UIGestureRecognizer) -> Void) {
        if let recognizers = view.gestureRecognizers {
            for r in recognizers where r.state == .possible && r.numberOfTouches == 0 {
                let typeName = String(describing: type(of: r))
                if typeName.hasPrefix("_") || typeName.hasPrefix("WK") || typeName.contains("WebTouch") {
                    body(r)
                }
            }
        }
        for subview in view.subviews {
            forEachPossibleZeroTouchWebKitRecognizer(in: subview, body)
        }
    }

    func possibleZeroTouchCountBucket() -> String {
        Self.countBucket3Plus(Self.possibleZeroTouchCountRaw())
    }

    static func windowActiveNoTouchCountRaw() -> Int {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var count = 0
        for window in windows {
            forEachRecognizer(in: window) { r in
                if (r.state == .began || r.state == .changed) && r.numberOfTouches == 0 {
                    count += 1
                }
            }
        }
        return count
    }

    func windowActiveNoTouchBucket() -> String {
        Self.countBucket2Plus(Self.windowActiveNoTouchCountRaw())
    }

    private static func forEachRecognizer(in view: UIView, _ body: (UIGestureRecognizer) -> Void) {
        view.gestureRecognizers?.forEach(body)
        view.subviews.forEach { forEachRecognizer(in: $0, body) }
    }

    /// Bucket the drag's start position into vertical thirds of the container, for the spatial-spread gate.
    func screenRegion(forY y: CGFloat) -> Int {
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

    func attemptBucket(_ count: Int) -> String {
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

// MARK: - Active touch probe (internal-only)

/// Passive window-level map of active touches, noting when touches begin and end, keyed by touch identity.
/// Installed as a single bystander recognizer on a `UIWindow`; never recognizes or interferes.
///
/// A non-zero active-touch count while no finger is on screen indicates an orphaned touch — the leading
/// hypothesis for why WebKit's deferring gate stays blocked and scroll never begins.
@MainActor
enum WebScrollFreezeDebugActiveTouchProbe {

    private static var activeTouches: [ObjectIdentifier: Date] = [:]
    private static var lastBegan: Date?
    private static var lastEnded: Date?
    private static var lastCancelled: Date?

    private static weak var installedRecognizer: WebScrollFreezeDebugActiveTouchRecognizer?

    /// True once a `WebScrollFreezeDebugActiveTouchRecognizer` has been installed on a window.
    static var isInstalled: Bool { installedRecognizer != nil }

    /// Adds exactly one passive `WebScrollFreezeDebugActiveTouchRecognizer` to `window`. Idempotent — returns immediately if
    /// a recognizer is already installed and alive.
    static func installIfNeeded(on window: UIWindow) {
        if let existing = installedRecognizer, existing.view != nil { return }
        let r = WebScrollFreezeDebugActiveTouchRecognizer()
        r.onBegan = { touches in
            let now = Date()
            for touch in touches {
                activeTouches[ObjectIdentifier(touch)] = now
            }
            lastBegan = now
        }
        r.onEnded = { touches in
            let now = Date()
            for touch in touches {
                activeTouches.removeValue(forKey: ObjectIdentifier(touch))
            }
            lastEnded = now
        }
        r.onCancelled = { touches in
            let now = Date()
            for touch in touches {
                activeTouches.removeValue(forKey: ObjectIdentifier(touch))
            }
            lastCancelled = now
        }
        window.addGestureRecognizer(r)
        installedRecognizer = r
    }

    /// Returns the body lines for an "Active touches" capture section. If not installed, returns a
    /// single line noting the feature is off.
    static func report() -> String {
        guard isInstalled else {
            return "- (not installed — enable webScrollFreezeCapture)\n"
        }
        let now = Date()
        var lines = ""
        lines += "- active touch count: \(activeTouches.count)"
        if !activeTouches.isEmpty {
            let oldest = activeTouches.values.map { now.timeIntervalSince($0) }.max() ?? 0
            lines += " (oldest \(String(format: "%.2f", oldest))s)"
            lines += " — NOTE: non-zero active touches while no finger is on screen = orphaned touch (leading hypothesis: may keep a deferring gate blocked below the recognizer layer; compare pre/post captures to assess)"
        }
        lines += "\n"
        if let date = lastBegan {
            lines += "- last began: \(String(format: "%.2f", now.timeIntervalSince(date)))s ago\n"
        }
        if let date = lastEnded {
            lines += "- last ended: \(String(format: "%.2f", now.timeIntervalSince(date)))s ago\n"
        }
        if let date = lastCancelled {
            lines += "- last cancelled: \(String(format: "%.2f", now.timeIntervalSince(date)))s ago\n"
        }
        return lines
    }
}

/// A pure bystander recognizer attached to a `UIWindow` by `WebScrollFreezeDebugActiveTouchProbe`. Modeled on
/// `WebScrollObserverGestureRecognizer`: never recognizes; never cancels or blocks other gestures.
final class WebScrollFreezeDebugActiveTouchRecognizer: UIGestureRecognizer {

    var onBegan: ((Set<UITouch>) -> Void)?
    var onEnded: ((Set<UITouch>) -> Void)?
    var onCancelled: ((Set<UITouch>) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onBegan?(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {}

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        onEnded?(touches)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        onCancelled?(touches)
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

// MARK: - Transition log (internal-only)

/// Lightweight transition-event log for scroll-freeze diagnostics. Callers add a note before
/// and after any navigation or tab-switch transition so that a freeze capture includes recent activity.
///
/// Each entry is a snapshot of observable UI state at the moment it is noted — not a proof of cause,
/// just evidence to compare across captures.
@MainActor
enum WebScrollFreezeDebugTransitionLog {

    private struct Entry {
        let timestamp: Date
        let label: String
        let touchInFlight: Bool
        let activeRecognizerCount: Int
        let webScrollPanState: String
        let wkSuspectCount: Int
    }

    private static var ring: [Entry] = []
    private static let ringCapacity = 20

    /// Captures a lightweight snapshot and appends it to the in-memory ring buffer (capped at ~20 entries);
    /// logs a concise summary via `Logger.interaction`. `nonisolated` so non-`@MainActor` call sites (e.g.
    /// `SwipeTabsCoordinator`) can add a note without each needing the annotation; `assumeIsolated`
    /// bridges to the main actor — safe because every call site (gesture handlers, view transitions)
    /// already runs on the main thread.
    nonisolated static func note(_ label: String) {
        MainActor.assumeIsolated {
            let touchInFlight = anyTouchInFlight()
            let activeCount = activeRecognizerCount()
            let panState = webScrollPanStateName()
            let suspectCount = wkSuspectCount()
            Logger.interaction.debug("Transition [\(label, privacy: .public)]: touchInFlight=\(touchInFlight, privacy: .public) activeRecognizers=\(activeCount, privacy: .public) webScrollPan=\(panState, privacy: .public) wkSuspects=\(suspectCount, privacy: .public)")
            let entry = Entry(
                timestamp: Date(),
                label: label,
                touchInFlight: touchInFlight,
                activeRecognizerCount: activeCount,
                webScrollPanState: panState,
                wkSuspectCount: suspectCount
            )
            if ring.count >= ringCapacity { ring.removeFirst() }
            ring.append(entry)
        }
    }

    /// Formats the ring buffer as a multi-line string for inclusion in a freeze capture. Returns a
    /// `(none)` line when the buffer is empty.
    static func recent() -> String {
        guard !ring.isEmpty else { return "- (none)\n" }
        let now = Date()
        var lines = ""
        for entry in ring {
            let age = String(format: "%.1f", now.timeIntervalSince(entry.timestamp))
            lines += "- \(age)s ago [\(entry.label)] touchInFlight=\(entry.touchInFlight) activeRecognizers=\(entry.activeRecognizerCount) webScrollPan=\(entry.webScrollPanState) wkSuspects=\(entry.wkSuspectCount)\n"
        }
        return lines
    }

    private static func anyTouchInFlight() -> Bool {
        var found = false
        for window in windows() {
            forEachRecognizer(in: window) { if $0.numberOfTouches > 0 { found = true } }
        }
        return found
    }

    private static func activeRecognizerCount() -> Int {
        var count = 0
        for window in windows() {
            forEachRecognizer(in: window) { r in
                if r.state == .began || r.state == .changed { count += 1 }
            }
        }
        return count
    }

    private static func webScrollPanStateName() -> String {
        guard let pan = WebScrollFreezeDebugProbe.findMainViewController()?.currentTab?.webView?.scrollView.panGestureRecognizer else {
            return "unavailable"
        }
        switch pan.state {
        case .possible:   return "possible"
        case .began:      return "began"
        case .changed:    return "changed"
        case .ended:      return "ended"
        case .cancelled:  return "cancelled"
        case .failed:     return "failed"
        @unknown default: return "possible"
        }
    }

    /// Count of WK/private-class recognizers (type name starts with `_` or `WK`, or contains `WebTouch`)
    /// that are in `.possible` with zero active touches, window-wide. A non-zero count is a suspect
    /// reading — compare across transition notes rather than treating any single value as conclusive.
    private static func wkSuspectCount() -> Int {
        var count = 0
        for window in windows() {
            forEachPossibleZeroTouchWebKitRecognizer(in: window) { _ in count += 1 }
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

    private static func forEachPossibleZeroTouchWebKitRecognizer(in view: UIView, _ body: (UIGestureRecognizer) -> Void) {
        if let recognizers = view.gestureRecognizers {
            for r in recognizers where r.state == .possible && r.numberOfTouches == 0 {
                let typeName = String(describing: type(of: r))
                if typeName.hasPrefix("_") || typeName.hasPrefix("WK") || typeName.contains("WebTouch") {
                    body(r)
                }
            }
        }
        for subview in view.subviews {
            forEachPossibleZeroTouchWebKitRecognizer(in: subview, body)
        }
    }
}

// MARK: - Recovery (single manual debug rung — internal only)

/// Diagnostic recovery rungs for the web-scroll-freeze. Two rungs are available: `resetDeferringGates`
/// and `resetScrollPan`. Neither is a proven fix — both are diagnostic tools that save pre/post captures
/// so you can compare recognizer state before and after. The leading hypothesis is that a
/// `WKDeferringGestureRecognizer` becomes wedged in `.possible`, but that remains unconfirmed; recovery
/// is intended to produce evidence (via captures), not to silently fix the problem.
///
/// Both rungs are guarded against live touches: toggling `isEnabled` while a touch is in flight orphans
/// that touch and can re-trigger the freeze. Manual rungs are debug-only; `autoRecover()` is a
/// gated scoped sequence intended for production when enabled by a feature flag in a calling layer.
@MainActor
enum WebScrollFreezeRecovery {

    enum Rung { case resetDeferringGates, resetScrollPan }

    @discardableResult
    static func runRung(_ rung: Rung) -> String {
        switch rung {
        case .resetDeferringGates: return resetDeferringGates()
        case .resetScrollPan:      return resetScrollPan()
        }
    }

    private static func savePrePostCaptures(label: String, reset: () -> Void) -> String {
        let pre = WebScrollFreezeDebugProbe.captureNow()
        WebScrollFreezeDebugCaptureStore.save(pre)
        reset()
        let post = WebScrollFreezeDebugProbe.captureNow()
        WebScrollFreezeDebugCaptureStore.save(post)
        return "\(label); pre/post captures saved — compare them"
    }

    /// Resets ONLY the WKWebView's `WKDeferringGestureRecognizer` instances. The deferring gate is the
    /// leading hypothesis for why the scroll pan never begins, but this is unconfirmed. Surgical + guarded.
    @discardableResult
    private static func resetDeferringGates() -> String {
        guard !anyTouchInFlight() else {
            return "skipped — touch in flight (would orphan it)"
        }
        guard let webView = WebScrollFreezeDebugProbe.findMainViewController()?.currentTab?.webView else {
            return "deferring-gate reset: no webView found"
        }
        return savePrePostCaptures(label: "reset deferring gate(s)") {
            applyDeferringGateReset(in: webView)
        }
    }

    /// Resets ONLY the web scroll view's `panGestureRecognizer` by toggling `isEnabled` off then on.
    /// A complementary suspect path to the deferring-gate hypothesis — compare pre/post captures to
    /// assess whether the pan state changed meaningfully.
    @discardableResult
    private static func resetScrollPan() -> String {
        guard !anyTouchInFlight() else {
            return "skipped — touch in flight (would orphan it)"
        }
        guard let pan = WebScrollFreezeDebugProbe.findMainViewController()?.currentTab?.webView?.scrollView.panGestureRecognizer else {
            return "scroll-pan reset: no webView found"
        }
        return savePrePostCaptures(label: "reset web scroll pan") {
            applyScrollPanReset(pan)
        }
    }

    /// Gated auto-recovery sequence. Applies the safe scoped resets once — pan only, then deferring gates
    /// only — bracketed by exactly one pre-capture and one post-capture. The closure is intentionally
    /// narrow: no broad window resets, no flushAll. Call only when no touch is in flight.
    ///
    /// Returns `true` ONLY if it actually ran the resets — `false` if it skipped (a touch is in flight, or
    /// no web view was found). Callers MUST gate the attempt pixel + outcome arming on this, so a skipped
    /// attempt does not emit a misleading recovery outcome. The leading hypothesis is that one or both
    /// resets may help; compare the pre/post captures rather than treating the return value as confirmation.
    @discardableResult
    static func autoRecover(scrollView: UIScrollView?) -> Bool {
        guard !anyTouchInFlight() else { return false }
        guard let scrollView else { return false }
        WebScrollFreezeDebugCaptureStore.save(WebScrollFreezeDebugProbe.captureNow())
        applyScrollPanReset(scrollView.panGestureRecognizer)
        applyDeferringGateReset(in: scrollView)
        WebScrollFreezeDebugCaptureStore.save(WebScrollFreezeDebugProbe.captureNow())
        Logger.interaction.error("Auto-recover: applied scroll-pan + deferring-gate resets; pre/post captures saved")
        return true
    }

    /// Core: toggle the web scroll pan recognizer off then on. Does NOT save captures — callers are
    /// responsible for bracketing with pre/post saves.
    private static func applyScrollPanReset(_ pan: UIPanGestureRecognizer) {
        pan.isEnabled = false
        pan.isEnabled = true
        Logger.interaction.error("Scroll-pan reset: toggled panGestureRecognizer isEnabled")
    }

    /// Core: toggle all deferring-gate recognizers off then on. Does NOT save captures — callers are
    /// responsible for bracketing with pre/post saves.
    private static func applyDeferringGateReset(in webView: UIView) {
        let gates = WebScrollFreezeDebugProbe.deferringGates(in: webView)
        for gate in gates {
            gate.isEnabled = false
            gate.isEnabled = true
        }
        Logger.interaction.error("Deferring-gate reset: toggled \(gates.count, privacy: .public) deferring recognizer(s)")
    }

    /// True if any recogniser in any window currently has touches in flight — i.e. a gesture is live and it is
    /// NOT safe to toggle `isEnabled` (that would strand the touch).
    private static func anyTouchInFlight() -> Bool {
        var found = false
        for window in windows() {
            forEachRecognizer(in: window) { if $0.numberOfTouches > 0 { found = true } }
        }
        return found
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
