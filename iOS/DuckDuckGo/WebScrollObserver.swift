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
import Core

/// Detects the symptom of the hard-to-reproduce "web page visible, taps work, scroll dead" freeze:
/// the user drags to scroll a scrollable web page and the content doesn't move, repeatedly.
///
/// Owned per `TabViewController`, attached to `webViewContainer` via a passive bystander recognizer that
/// never interferes with scrolling or taps. Fires three telemetry signals (symptom + two daily liveness
/// heartbeats) and a separate mechanism signal (`checkForWedgedRecognizer`). Logs every failed attempt as
/// a breadcrumb so the Interaction Diagnostics snapshot has the recent history even below the pixel
/// threshold. No Swift concurrency — the post-gesture and wedge re-checks use `asyncAfter` on the main
/// queue. `firePixel*` closures are injected so the detectors are unit-testable without the static pipeline.
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
        static let streakWindow: TimeInterval = 30
        static let wedgeRecheck: TimeInterval = 1.0
    }

    private weak var container: UIView?
    private let scrollViewProvider: () -> UIScrollView?
    private let currentURL: () -> URL?
    private let firePixelDailyAndCount: (Pixel.Event, [String: String]) -> Void
    private let now: () -> Date

    private var recognizer: WebScrollObserverGestureRecognizer?
    private var dragStartOffsetY: CGFloat = 0

    private var failureStreak = 0
    private var lastFailureAt: Date?
    private var streakDirections: Set<String> = []
    private var highestBucketFired: String?

    private weak var wedgeCandidate: UIGestureRecognizer?

    /// Human-readable last outcome, surfaced in the Interaction Diagnostics snapshot.
    private(set) var recentStatus = "no scroll attempt observed yet"

    init(container: UIView,
         scrollView: @escaping () -> UIScrollView?,
         currentURL: @escaping () -> URL?,
         firePixelDailyAndCount: @escaping (Pixel.Event, [String: String]) -> Void = {
            DailyPixel.fireDailyAndCount(pixel: $0, withAdditionalParameters: $1)
         },
         now: @escaping () -> Date = { Date() }) {
        self.container = container
        self.scrollViewProvider = scrollView
        self.currentURL = currentURL
        self.firePixelDailyAndCount = firePixelDailyAndCount
        self.now = now
        super.init()
    }

    func install() {
        guard recognizer == nil, let container else { return }
        let recognizer = WebScrollObserverGestureRecognizer(target: nil, action: nil)
        recognizer.delegate = self
        recognizer.onBegan = { [weak self] in self?.dragBegan() }
        recognizer.onEnded = { [weak self] dx, dy in self?.dragEnded(dx: dx, dy: dy) }
        container.addGestureRecognizer(recognizer)
        self.recognizer = recognizer
    }

    /// Reset the failure streak — call on navigation, tab disappearance, or backgrounding.
    func reset() {
        failureStreak = 0
        lastFailureAt = nil
        streakDirections = []
        highestBucketFired = nil
    }

    // MARK: - Symptom detection (C1)

    private func dragBegan() {
        dragStartOffsetY = scrollViewProvider()?.contentOffset.y ?? 0
    }

    private func dragEnded(dx: CGFloat, dy: CGFloat) {
        // Capture the start offset by value now — a second drag within the recheck window would
        // otherwise overwrite `dragStartOffsetY` before this closure runs.
        let startOffsetY = dragStartOffsetY
        // Re-sample after a beat so late settling counts as movement.
        DispatchQueue.main.asyncAfter(deadline: .now() + Constant.postEndRecheck) { [weak self] in
            self?.classifyDrag(dx: dx, dy: dy, startOffsetY: startOffsetY)
        }
    }

    private func classifyDrag(dx: CGFloat, dy: CGFloat, startOffsetY: CGFloat) {
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
            registerFailedAttempt(direction: fingerUp ? "up" : "down")
        }
    }

    private func registerFailedAttempt(direction: String) {
        if let last = lastFailureAt, now().timeIntervalSince(last) > Constant.streakWindow {
            failureStreak = 0
            streakDirections = []
            highestBucketFired = nil
        }
        failureStreak += 1
        lastFailureAt = now()
        streakDirections.insert(direction)
        recentStatus = "\(failureStreak) failed scroll attempt(s) (\(formatted(now())))"
        Logger.interaction.error("Web scroll did not move: failed attempt #\(self.failureStreak, privacy: .public), direction \(direction, privacy: .public)")

        guard failureStreak >= Constant.streakThreshold else { return }
        let bucket = attemptBucket(failureStreak)
        guard bucket != highestBucketFired else { return }
        highestBucketFired = bucket
        firePixelDailyAndCount(.debugInteractionRepeatedFailedScroll, [
            "attempt_count_bucket": bucket,
            "direction": streakDirections.count > 1 ? "mixed" : (streakDirections.first ?? "mixed")
        ])
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
    var onEnded: ((CGFloat, CGFloat) -> Void)?

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
        onEnded?(lastPoint.x - startPoint.x, lastPoint.y - startPoint.y)
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
