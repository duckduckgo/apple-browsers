//
//  InteractionDiagnosticsDebugScreen.swift
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

import SwiftUI
import UIKit
import OSLog
import Core

/// Debug screen that captures a root-cause-agnostic snapshot of the current scroll / gesture /
/// overlay state of the foreground web tab, plus recent `Logger.interaction` entries.
///
/// Built to diagnose the hard-to-reproduce "web view can't be scrolled but taps still work" freeze
/// seen on internal builds: when it happens, open this screen, tap Capture, then Copy and paste the
/// report into the bug. The report is structural (it walks the live view tree) so it stays valid even
/// though this screen is presented on top of the frozen tab.
struct InteractionDiagnosticsDebugScreen: View {

    @StateObject private var model: InteractionDiagnosticsModel

    init(tabManager: TabManager) {
        _model = StateObject(wrappedValue: InteractionDiagnosticsModel(tabManager: tabManager))
    }

    var body: some View {
        List {
            Section {
                Button {
                    model.capture()
                } label: {
                    Text(verbatim: "Capture Snapshot")
                }

                if !model.report.isEmpty {
                    Button {
                        model.copy()
                    } label: {
                        Text(verbatim: "Copy to Clipboard")
                    }
                }
            } header: {
                Text(verbatim: "Actions")
            } footer: {
                Text(verbatim: "Capture reads the live view tree of the foreground tab. Persistent state "
                     + "(isScrollEnabled, overlays, which recognizers are enabled) is reliable here. A gesture "
                     + "recognizer's transient .state may reset when this screen is presented — for that, rely "
                     + "on the live logs below / the Log Viewer (subsystem: Interaction).")
            }

            if !model.report.isEmpty {
                Section {
                    TextEditor(text: .constant(model.report))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 360)
                } header: {
                    Text(verbatim: "Snapshot")
                }
            }
        }
        .navigationTitle("Interaction Diagnostics")
    }
}

final class InteractionDiagnosticsModel: ObservableObject {

    @Published var report = ""

    private let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func copy() {
        UIPasteboard.general.string = report
    }

    @MainActor
    func capture() {
        report = buildSnapshot() + "\n\n## Recent interaction logs (last 5 min)\n" + Self.recentInteractionLogs()
    }

    // MARK: - Snapshot

    @MainActor
    private func buildSnapshot() -> String {
        var out = "# Interaction Diagnostics — \(Date())\n"
        out += "App: \(Self.appVersion)\n\n"
        out += featureFlagsSection()
        out += "\n" + currentTabSection()
        return out
    }

    private func featureFlagsSection() -> String {
        let flagger = AppDependencyProvider.shared.featureFlagger
        var out = "## Feature flags\n"
        out += "- unifiedToggleInput: \(flagger.isFeatureOn(.unifiedToggleInput))\n"
        out += "- experimentalAddressBar: \(flagger.isFeatureOn(.experimentalAddressBar))\n"
        out += "- showAIChatAddressBarChoiceScreen: \(flagger.isFeatureOn(.showAIChatAddressBarChoiceScreen))\n"
        return out
    }

    @MainActor
    private func currentTabSection() -> String {
        guard let tab = tabManager.current(createIfNeeded: false) else {
            return "## Current tab\n- No current TabViewController\n"
        }
        guard let webView = tab.webView else {
            return "## Current tab\n- TabViewController has no webView\n"
        }

        let scrollView = webView.scrollView
        var out = "## Current tab\n"
        out += "- URL host: \(webView.url?.host ?? "nil")\n"
        out += "- TabViewController: \(Self.typeName(tab))\n"
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
        out += "- delegate: \(scrollView.delegate.map { Self.typeName($0) } ?? "nil")\n"

        out += "\n" + Self.panGesture(of: scrollView)
        out += "\n" + Self.gestureChainSection(from: webView)
        out += "\n" + Self.competingRecognizersSection()
        out += "\n" + Self.overlaySection(over: webView, boundary: Self.findMainViewController()?.view)
        out += "\n" + coordinatorSection()
        return out
    }

    /// Window-wide scan for the swipe-tabs recognizers. They live on chrome containers (toolbar, UTI
    /// container, chat header) that are siblings of the web view, so they never appear in the
    /// webView→window chain above — but a wedge in one is the prime scroll-freeze suspect.
    private static func competingRecognizersSection() -> String {
        var out = "## Swipe-tabs recognizers (window-wide)\n"
        var found = false
        forEachWindowGestureRecognizer { recognizer in
            guard recognizer is UnifiedInputSwipeTabsPanGestureRecognizer else { return }
            found = true
            let host = recognizer.view.map { typeName($0) } ?? "nil"
            out += "• on \(host): \(describe(recognizer))\n"
        }
        if !found {
            out += "- (none found)\n"
        }
        return out
    }

    /// The scroll view's own pan recognizer — the one that actually drives web scrolling.
    private static func panGesture(of scrollView: UIScrollView) -> String {
        var out = "## webView.scrollView.panGestureRecognizer\n"
        out += "- \(describe(scrollView.panGestureRecognizer))\n"
        return out
    }

    /// Walk webView → window collecting every gesture recognizer on the chain. A recognizer stuck in
    /// `began`/`changed` on an ancestor, or a stray pan with `cancelsTouchesInView`, is the prime
    /// scroll-blocking suspect and is flagged inline.
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
        if !found {
            out += "- (none)\n"
        }
        return out
    }

    /// Structural overlay check (modal-safe — does not use hitTest). Walks webView up to MainViewController's
    /// view (so the presented debug screen isn't itself reported as a blocker) and flags any sibling drawn
    /// above our branch that can receive touches and covers any of three sample points down the web view —
    /// a leftover transition snapshot / scrim / cover left interactive would block pans here.
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
        if !found {
            out += "- (none over the web view)\n"
        }
        return out
    }

    /// Best-effort UTI / swipe-tabs coordinator state, reached by locating MainViewController in the tree.
    @MainActor
    private func coordinatorSection() -> String {
        guard let mainVC = Self.findMainViewController() else {
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

    // MARK: - Logs

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

    // MARK: - Helpers

    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    private static func typeName(_ object: Any) -> String {
        String(describing: type(of: object))
    }

    private static func describe(_ recognizer: UIGestureRecognizer) -> String {
        let active = (recognizer.state == .began || recognizer.state == .changed)
        return "\(typeName(recognizer)) state=\(recognizer.state.diagnosticName)\(active ? " ⚠️ ACTIVE" : "")"
            + " enabled=\(recognizer.isEnabled) cancelsTouchesInView=\(recognizer.cancelsTouchesInView)"
            + " delaysTouchesBegan=\(recognizer.delaysTouchesBegan) touches=\(recognizer.numberOfTouches)"
    }

    private static func findMainViewController() -> MainViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows {
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
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows {
            walk(window, body)
        }
    }

    private static func walk(_ view: UIView, _ body: (UIGestureRecognizer) -> Void) {
        view.gestureRecognizers?.forEach(body)
        view.subviews.forEach { walk($0, body) }
    }
}
