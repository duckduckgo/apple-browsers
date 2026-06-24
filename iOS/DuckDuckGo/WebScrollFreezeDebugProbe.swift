//
//  WebScrollFreezeDebugProbe.swift
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

// MARK: - Capture authority

/// Single source of truth for a freeze capture. Self-contained (locates the foreground tab via the view
/// tree), so it is callable from the Interaction Diagnostics debug screen, from the auto-capture in
/// `WebScrollObserver` (gated by `webScrollFreezeCapture`, internal-only), and from lldb:
///
///     expr -l Swift -O -- print(WebScrollFreezeDebugProbe.captureNow())
enum WebScrollFreezeDebugProbe {

    @MainActor
    static func captureNow() -> String {
        var out = "# Interaction Diagnostics — \(Date())\n"
        out += "App: \(appVersion)\n\n"
        out += touchSection() + "\n"
        out += transitionLogSection() + "\n"
        out += featureFlagsSection() + "\n"
        out += currentTabSection() + "\n"
        out += scrollViewsSection() + "\n"
        out += allScrollViewsSection() + "\n"
        out += windowWideRecognizerSuspectsSection() + "\n"
        out += presentationSection() + "\n"
        out += windowSection() + "\n"
        out += "## Recent interaction logs (last 5 min)\n" + recentInteractionLogs()
        return out
    }

    // MARK: Active touches

    @MainActor
    private static func touchSection() -> String {
        "## Active touches\n" + WebScrollFreezeDebugActiveTouchProbe.report() + "\n"
    }

    @MainActor
    private static func transitionLogSection() -> String {
        "## Recent transitions\n" + WebScrollFreezeDebugTransitionLog.recent() + "\n"
    }

    private static func featureFlagsSection() -> String {
        let flagger = AppDependencyProvider.shared.featureFlagger
        var out = "## Feature flags\n"
        out += "- unifiedToggleInput: \(flagger.isFeatureOn(.unifiedToggleInput))\n"
        out += "- experimentalAddressBar: \(flagger.isFeatureOn(.experimentalAddressBar))\n"
        out += "- showAIChatAddressBarChoiceScreen: \(flagger.isFeatureOn(.showAIChatAddressBarChoiceScreen))\n"
        return out
    }

    @MainActor
    private static func currentTabSection() -> String {
        guard let tab = findMainViewController()?.currentTab else {
            return "## Current tab\n- No current TabViewController\n"
        }
        guard let webView = tab.webView else {
            return "## Current tab\n- TabViewController has no webView\n"
        }

        let scrollView = webView.scrollView
        var out = "## Current tab\n"
        out += "- URL host: \(webView.url?.host ?? "nil")\n"
        out += "- TabViewController: \(typeName(tab))\n"
        out += "- scroll observer: \(tab.webScrollObserver?.recentStatus ?? "not installed")\n\n"

        out += "## webView.scrollView\n"
        out += "- isScrollEnabled: \(scrollView.isScrollEnabled)\(scrollView.isScrollEnabled ? "" : "  ⚠️ SCROLL DISABLED")\n"
        out += "- isUserInteractionEnabled: \(scrollView.isUserInteractionEnabled)\n"
        out += "- delaysContentTouches: \(scrollView.delaysContentTouches)  canCancelContentTouches: \(scrollView.canCancelContentTouches)\n"
        out += "- bounces: \(scrollView.bounces)  alwaysBounceVertical: \(scrollView.alwaysBounceVertical)\n"
        out += "- isDragging: \(scrollView.isDragging)  isDecelerating: \(scrollView.isDecelerating)"
            + "  isTracking: \(scrollView.isTracking)  isZooming: \(scrollView.isZooming)\n"
        out += "- contentOffset: \(scrollView.contentOffset)\n"
        out += "- contentSize: \(scrollView.contentSize)\n"
        out += "- bounds: \(scrollView.bounds)\n"
        out += "- adjustedContentInset: \(scrollView.adjustedContentInset)\n"
        out += "- zoomScale: \(scrollView.zoomScale) (min \(scrollView.minimumZoomScale) / max \(scrollView.maximumZoomScale))\n"
        out += "- delegate: \(scrollView.delegate.map { typeName($0) } ?? "nil")\n"

        out += "\n" + panGesture(of: scrollView)
        out += "\n" + webViewSubtreeSection(of: webView)
        out += "\n" + gestureChainSection(from: webView)
        out += "\n" + competingRecognizersSection()
        out += "\n" + overlaySection(over: webView, boundary: findMainViewController()?.view)
        out += "\n" + coordinatorSection()
        return out
    }

    /// Every scroll view that is mid-gesture — a different scroll view stuck `isDragging`/`isTracking`
    /// could be holding the gesture environment, which would freeze pans app-wide.
    private static func scrollViewsSection() -> String {
        var out = "## Scroll views mid-gesture (window-wide)\n"
        var found = false
        forEachWindowSubview { view in
            guard let scrollView = view as? UIScrollView,
                  scrollView.isDragging || scrollView.isTracking || scrollView.isDecelerating else { return }
            found = true
            out += "- ⚠️ \(typeName(scrollView)) dragging=\(scrollView.isDragging) tracking=\(scrollView.isTracking)"
                + " decel=\(scrollView.isDecelerating) scrollEnabled=\(scrollView.isScrollEnabled) offset=\(scrollView.contentOffset)\n"
        }
        if !found { out += "- (none active — all idle)\n" }
        return out
    }

    /// Every UIScrollView in every window — regardless of gesture state — so a frozen scroll view that is
    /// NOT mid-gesture (e.g. stuck after a failed reset) still shows up. Listed per window with host view
    /// type, interaction flags, gesture state, content geometry, and whether it could be the culprit.
    private static func allScrollViewsSection() -> String {
        var out = "## All scroll views (window-wide)\n"
        var count = 0
        for window in allWindows() {
            let windowName = typeName(window)
            walkSubviews(window) { view in
                guard let sv = view as? UIScrollView else { return }
                count += 1
                let pan = sv.panGestureRecognizer
                let contentRange = sv.contentSize.height - sv.bounds.height
                out += "- \(typeName(sv)) in \(windowName)\n"
                out += "    scrollEnabled=\(sv.isScrollEnabled) userInteractionEnabled=\(sv.isUserInteractionEnabled)\n"
                out += "    tracking=\(sv.isTracking) dragging=\(sv.isDragging) decelerating=\(sv.isDecelerating)\n"
                out += "    pan: state=\(pan.state.diagnosticName) touches=\(pan.numberOfTouches)\n"
                out += "    contentOffset=\(sv.contentOffset) contentSize.h=\(sv.contentSize.height)"
                    + " bounds.h=\(sv.bounds.height) range=\(contentRange)\n"
            }
        }
        if count == 0 { out += "- (no UIScrollViews found)\n" }
        return out
    }

    /// Window-wide scan of all gesture recognizers, grouped into four buckets:
    ///   (a) `.began` / `.changed` — actively recognizing a gesture right now,
    ///   (b) `.began` / `.changed` AND `numberOfTouches == 0` — active with no live touches, a suspect
    ///       pattern worth comparing against a healthy baseline (a recognizer in (b) also appears in (a)),
    ///   (c) `numberOfTouches > 0` — holding touch references without being active,
    ///   (d) WebKit/private recognizers in `.possible`, `.began`, or `.changed` — compare against a
    ///       healthy baseline; `.possible`/0-touches is also the normal idle state for these gates.
    /// Each entry includes a short superview-chain path, frame, window, visibility, and alpha.
    private static func windowWideRecognizerSuspectsSection() -> String {
        var active: [(UIGestureRecognizer, UIView, UIWindow)] = []
        var activeZeroTouches: [(UIGestureRecognizer, UIView, UIWindow)] = []
        var holdingTouches: [(UIGestureRecognizer, UIView, UIWindow)] = []
        var webKitNonEnded: [(UIGestureRecognizer, UIView, UIWindow)] = []

        for window in allWindows() {
            walkSubviews(window) { view in
                guard let recognizers = view.gestureRecognizers else { return }
                for recognizer in recognizers {
                    let state = recognizer.state
                    let touches = recognizer.numberOfTouches
                    let isActive = state == .began || state == .changed
                    if isActive {
                        active.append((recognizer, view, window))
                        if touches == 0 {
                            activeZeroTouches.append((recognizer, view, window))
                        }
                    } else if touches > 0 {
                        holdingTouches.append((recognizer, view, window))
                    }
                    if isWebKitPrivate(recognizer) && (state == .possible || state == .began || state == .changed) {
                        webKitNonEnded.append((recognizer, view, window))
                    }
                }
            }
        }

        var out = "## Window-wide recognizer suspects\n"

        out += "\n### (a) Active recognizers (.began / .changed)\n"
        out += formatRecognizerBucket(active)
        out += "\n### (b) Active with zero touches (.began / .changed, numberOfTouches == 0 — wedge suspects)\n"
        out += "- NOTE: active-but-zero-touches is a suspect pattern; compare against a healthy-baseline capture to assess.\n"
        out += formatRecognizerBucket(activeZeroTouches)
        out += "\n### (c) Recognizers holding touches (numberOfTouches > 0, not active)\n"
        out += formatRecognizerBucket(holdingTouches)
        out += "\n### (d) WebKit/private recognizers (.possible / .began / .changed)\n"
        out += "- NOTE: .possible/0-touches is the NORMAL idle state for WebKit gates."
            + " Useful only when diffed against a healthy-baseline capture.\n"
        out += formatRecognizerBucket(webKitNonEnded, warning: false)

        return out
    }

    private static func formatRecognizerBucket(
        _ entries: [(UIGestureRecognizer, UIView, UIWindow)],
        warning: Bool = true
    ) -> String {
        guard !entries.isEmpty else { return "- (none)\n" }
        return entries.map { recognizer, view, window in
            "- \(warning ? "⚠️ " : "")\(typeName(recognizer)) state=\(recognizer.state.diagnosticName)"
                + " touches=\(recognizer.numberOfTouches)\n"
                + "    \(viewContextDescription(view, window: window))\n"
        }.joined()
    }

    /// Short description of a view's position in the window hierarchy: superview type chain, frame,
    /// which window it lives in, and visibility.
    private static func viewContextDescription(_ view: UIView, window: UIWindow) -> String {
        var chain: [String] = []
        var cursor: UIView? = view.superview
        while let current = cursor, !(current is UIWindow) {
            chain.append(typeName(current))
            cursor = current.superview
        }
        let path = chain.isEmpty ? "(root)" : chain.joined(separator: " > ")
        return "host=\(typeName(view)) superviews=[\(path)] frame=\(view.frame)"
            + " window=\(typeName(window)) hidden=\(view.isHidden) alpha=\(view.alpha)"
    }

    /// A presentation/transition left mid-flight can wedge UIKit's pan routing while taps still work.
    @MainActor
    private static func presentationSection() -> String {
        var out = "## Presentation / transition state\n"
        guard let root = keyWindow()?.rootViewController else {
            out += "- no key window root\n"
            return out
        }
        var viewController: UIViewController? = root
        var found = false
        while let current = viewController {
            let hasCoordinator = current.transitionCoordinator != nil
            if current.isBeingPresented || current.isBeingDismissed || hasCoordinator {
                found = true
                out += "- ⚠️ \(typeName(current)) beingPresented=\(current.isBeingPresented)"
                    + " beingDismissed=\(current.isBeingDismissed) transitionCoordinator=\(hasCoordinator)"
                    + " style=\(current.modalPresentationStyle.rawValue)\n"
            }
            viewController = current.presentedViewController
        }
        if !found { out += "- (no view controller mid-transition)\n" }
        return out
    }

    private static func windowSection() -> String {
        var out = "## Windows\n"
        for window in allWindows() {
            out += "- \(typeName(window)) level=\(window.windowLevel.rawValue) hidden=\(window.isHidden)"
                + " key=\(window.isKeyWindow) root=\(window.rootViewController.map { typeName($0) } ?? "nil")\n"
        }
        return out
    }

    /// Window-wide scan for the swipe-tabs recognizers (siblings of the web view, never in its chain).
    private static func competingRecognizersSection() -> String {
        var out = "## Swipe-tabs recognizers (window-wide)\n"
        var found = false
        forEachWindowGestureRecognizer { recognizer in
            guard recognizer is UnifiedInputSwipeTabsPanGestureRecognizer else { return }
            found = true
            let host = recognizer.view.map { typeName($0) } ?? "nil"
            out += "• on \(host): \(describe(recognizer))\n"
        }
        if !found { out += "- (none found)\n" }
        return out
    }

    private static func panGesture(of scrollView: UIScrollView) -> String {
        "## webView.scrollView.panGestureRecognizer\n- \(describe(scrollView.panGestureRecognizer))\n"
    }

    /// Dumps EVERY gesture recogniser in the webView's SUBTREE (descending into WKScrollView / WKContentView)
    /// — the recognisers the `webView → window` ancestor chain never reaches, and where a suspected wedge
    /// may reside (e.g. a WebKit deferring/gating recogniser). We list all of them (robust to not knowing the
    /// exact WebKit class names) with full public state, classify each, and flag `.possible`-with-0-touches
    /// WebKit recognisers as SUSPECTS — deliberately NOT "wedged", because those states are also the normal idle state.
    @MainActor
    private static func webViewSubtreeSection(of webView: UIView) -> String {
        var entries: [(recognizer: UIGestureRecognizer, host: UIView)] = []
        collectSubtreeRecognizers(in: webView, into: &entries)

        var out = "## WKWebView subtree recognizers (descending into WKContentView — NOT the ancestor chain)\n"
        if entries.isEmpty {
            out += "- (no recognizers found under the web view subtree)\n"
            return out
        }
        for entry in entries {
            out += "    \(describeSubtreeRecognizer(entry.recognizer, host: entry.host))\n"
        }

        out += "\n### Possible gate suspects (WebKit/private recognizers .possible, 0 touches — SUSPECTS ONLY)\n"
        let suspects = entries.filter {
            isWebKitPrivate($0.recognizer) && $0.recognizer.state == .possible && $0.recognizer.numberOfTouches == 0
        }
        if suspects.isEmpty {
            out += "- (none)\n"
        } else {
            for suspect in suspects {
                out += "    - \(typeName(suspect.recognizer)) on \(typeName(suspect.host))\n"
            }
        }
        out += "- NOTE: WebKit gates sit .possible/0-touches in the NORMAL idle state too. This list confirms"
            + " nothing on its own — it is diagnostic only when a FREEZE capture is diffed against a healthy"
            + " baseline (which gate failed to reset / differs in state).\n"
        return out
    }

    private static func collectSubtreeRecognizers(
        in view: UIView,
        into entries: inout [(recognizer: UIGestureRecognizer, host: UIView)]
    ) {
        view.gestureRecognizers?.forEach { entries.append(($0, view)) }
        view.subviews.forEach { collectSubtreeRecognizers(in: $0, into: &entries) }
    }

    @MainActor
    private static func describeSubtreeRecognizer(_ recognizer: UIGestureRecognizer, host: UIView) -> String {
        let active = (recognizer.state == .began || recognizer.state == .changed)
        return "[\(suspectClass(recognizer))] \(typeName(recognizer)) on \(typeName(host))"
            + " — state=\(recognizer.state.diagnosticName)\(active ? " ⚠️ ACTIVE" : "")"
            + " enabled=\(recognizer.isEnabled) touches=\(recognizer.numberOfTouches)"
            + " cancels=\(recognizer.cancelsTouchesInView)"
            + " delaysBegan=\(recognizer.delaysTouchesBegan) delaysEnded=\(recognizer.delaysTouchesEnded)"
            + (isWebKitPrivate(recognizer) ? " (private)" : "")
    }

    /// Classify by runtime type name only (no private API). WebKit/private recognisers first, then fall back
    /// to the existing app-recogniser buckets so app recognisers keep their established labels.
    @MainActor
    private static func suspectClass(_ recognizer: UIGestureRecognizer) -> String {
        let name = String(describing: type(of: recognizer))
        if name.contains("WKDeferring") { return "wk_deferring" }
        if name.contains("WKTouchAction") { return "wk_touch_action" }
        if name.contains("WebTouchEvents") || name.contains("UIWebTouch") { return "wk_touch_events" }
        if name.contains("WKContent") { return "wk_content" }
        if name.hasPrefix("WK") || name.hasPrefix("_") { return "wk_other" }
        return WebScrollObserver.bucket(for: recognizer)
    }

    private static func isWebKitPrivate(_ recognizer: UIGestureRecognizer) -> Bool {
        let name = String(describing: type(of: recognizer))
        return name.hasPrefix("WK") || name.hasPrefix("_") || name.contains("WebTouch") || name.contains("UIWebTouch")
    }

    /// Recursively collect recognisers whose class is a WebKit deferring gate (WKDeferringGestureRecognizer)
    /// from the webView's subtree. Shared with `WebScrollFreezeRecovery` so recovery resets exactly what the
    /// capture reports.
    static func deferringGates(in view: UIView) -> [UIGestureRecognizer] {
        var gates: [UIGestureRecognizer] = []
        collectDeferringGates(in: view, into: &gates)
        return gates
    }

    private static func collectDeferringGates(in view: UIView, into gates: inout [UIGestureRecognizer]) {
        view.gestureRecognizers?.forEach { recognizer in
            if String(describing: type(of: recognizer)).contains("Deferring") {
                gates.append(recognizer)
            }
        }
        view.subviews.forEach { collectDeferringGates(in: $0, into: &gates) }
    }

    private static func gestureChainSection(from start: UIView) -> String {
        var out = "## Gesture recognizers (webView → window)\n"
        var view: UIView? = start
        var found = false
        while let current = view {
            if let recognizers = current.gestureRecognizers, !recognizers.isEmpty {
                found = true
                out += "• \(typeName(current)) [\(current.frame)]\n"
                for recognizer in recognizers {
                    out += "    - \(describe(recognizer))\n"
                }
            }
            view = current.superview
        }
        if !found { out += "- (none)\n" }
        return out
    }

    private static func overlaySection(over webView: UIView, boundary: UIView?) -> String {
        var out = "## Potential blocking overlays over the web view\n"
        let bounds = webView.bounds
        let samples = [CGPoint(x: bounds.midX, y: bounds.minY + 20),
                       CGPoint(x: bounds.midX, y: bounds.midY),
                       CGPoint(x: bounds.midX, y: bounds.maxY - 20)].map { webView.convert($0, to: nil) }
        var branch = webView
        var found = false
        while branch !== boundary, let container = branch.superview {
            if let branchIndex = container.subviews.firstIndex(of: branch) {
                for sibling in container.subviews[(branchIndex + 1)...] where sibling.isUserInteractionEnabled
                    && !sibling.isHidden && sibling.alpha > 0.01 {
                    let frameInWindow = sibling.convert(sibling.bounds, to: nil)
                    if samples.contains(where: { frameInWindow.contains($0) }) {
                        found = true
                        out += "- ⚠️ \(typeName(sibling)) above \(typeName(container))"
                            + " [\(sibling.frame)] alpha \(sibling.alpha)\n"
                    }
                }
            }
            branch = container
        }
        if !found { out += "- (none over the web view)\n" }
        return out
    }

    @MainActor
    private static func coordinatorSection() -> String {
        guard let mainVC = findMainViewController() else {
            return "## Coordinator state\n- MainViewController not found\n"
        }
        var out = "## Coordinator state\n"
        if let swipe = mainVC.swipeTabsCoordinator {
            out += "- swipeTabsCoordinator.isEnabled: \(swipe.isEnabled)\n"
            out += "- swipeTabsCoordinator.state: \(String(describing: swipe.state))\n"
        } else {
            out += "- swipeTabsCoordinator: nil\n"
        }
        if let uti = mainVC.unifiedToggleInputCoordinator {
            out += "- unifiedToggleInputCoordinator.displayState: \(String(describing: uti.displayState))\n"
        } else {
            out += "- unifiedToggleInputCoordinator: nil\n"
        }
        return out
    }

    private static func recentInteractionLogs() -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else {
            return "(OSLogStore unavailable)"
        }
        let since = store.position(date: Date().addingTimeInterval(-300))
        let predicate = NSPredicate(format: "subsystem == %@", "Interaction")
        guard let entries = try? store.getEntries(at: since, matching: predicate) else {
            return "(failed to read log store)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.suffix(300).map {
            "\(formatter.string(from: $0.date)) \($0.composedMessage)"
        }
        return lines.isEmpty ? "(no interaction logs in window)" : lines.joined(separator: "\n")
    }

    // MARK: Shared helpers

    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    static func typeName(_ object: Any) -> String { String(describing: type(of: object)) }

    static func describe(_ recognizer: UIGestureRecognizer) -> String {
        let active = (recognizer.state == .began || recognizer.state == .changed)
        return "\(typeName(recognizer)) state=\(recognizer.state.diagnosticName)\(active ? " ⚠️ ACTIVE" : "")"
            + " enabled=\(recognizer.isEnabled) cancelsTouchesInView=\(recognizer.cancelsTouchesInView)"
            + " delaysTouchesBegan=\(recognizer.delaysTouchesBegan) touches=\(recognizer.numberOfTouches)"
    }

    static func allWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }

    @MainActor
    static func keyWindow() -> UIWindow? {
        allWindows().first { $0.isKeyWindow } ?? allWindows().first
    }

    static func findMainViewController() -> MainViewController? {
        for window in allWindows() {
            if let root = window.rootViewController, let match = firstDescendant(MainViewController.self, in: root) {
                return match
            }
        }
        return nil
    }

    private static func firstDescendant<T: UIViewController>(_ type: T.Type, in viewController: UIViewController) -> T? {
        if let match = viewController as? T { return match }
        for child in viewController.children {
            if let match = firstDescendant(type, in: child) { return match }
        }
        return nil
    }

    private static func forEachWindowGestureRecognizer(_ body: (UIGestureRecognizer) -> Void) {
        for window in allWindows() { walkRecognizers(window, body) }
    }

    private static func walkRecognizers(_ view: UIView, _ body: (UIGestureRecognizer) -> Void) {
        view.gestureRecognizers?.forEach(body)
        view.subviews.forEach { walkRecognizers($0, body) }
    }

    private static func forEachWindowSubview(_ body: (UIView) -> Void) {
        for window in allWindows() { walkSubviews(window, body) }
    }

    private static func walkSubviews(_ view: UIView, _ body: (UIView) -> Void) {
        body(view)
        view.subviews.forEach { walkSubviews($0, body) }
    }
}

// MARK: - Persistent ring buffer

/// Last N freeze captures, written to Caches so they survive leaving the debug screen and can be exported
/// after the fact (the freeze persists, so the user has time). No pixel — purely on-device, no triage.
enum WebScrollFreezeDebugCaptureStore {

    private static let maxCaptures = 10

    private static var directory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = caches.appendingPathComponent("freeze-captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Monotonic counter so back-to-back saves (e.g. a recovery's pre + post captures, written within the
    /// same wall-clock second) get distinct filenames.
    private static var sequence = 0

    static func save(_ text: String) {
        guard let directory else { return }
        sequence += 1
        let name = "capture-\(Int(Date().timeIntervalSince1970))-\(String(format: "%03d", sequence)).txt"
        try? text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        prune()
    }

    static func count() -> Int { files().count }

    static func exportAll() -> String {
        files().reversed().compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n\n========================================\n\n")
    }

    static func clear() {
        files().forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private static func files() -> [URL] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                      includingPropertiesForKeys: nil,
                                                                      options: [.skipsHiddenFiles]) else { return [] }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func prune() {
        let all = files()
        guard all.count > maxCaptures else { return }
        all.prefix(all.count - maxCaptures).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
