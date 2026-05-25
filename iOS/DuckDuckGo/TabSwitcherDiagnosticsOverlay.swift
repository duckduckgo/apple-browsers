//
//  TabSwitcherDiagnosticsOverlay.swift
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
import Core
import os.log
import OSLog

/// Self-diagnostic overlay for the "unresponsive Tab Switcher" bug.
/// Triggered when the user taps the tab switcher button rapidly without the switcher opening,
/// snapshots app state into a screenshottable overlay so the team can capture it from the field.
///
/// Why a UIWindow-attached overlay rather than UIViewController.present? The whole bug
/// hypothesis is that UIKit's modal presentation is silently failing — so we cannot rely on
/// `present(_:animated:)` to display the diagnostic. Adding a UIView directly to the key
/// window's subview list puts the overlay above any presented modal containers.
@MainActor
enum TabSwitcherDiagnosticsOverlay {

    /// Number of taps within `tapWindow` that triggers the overlay. Fires regardless of
    /// the current tab-switcher visibility state — we want the diagnostic any time the
    /// user is tap-mashing the button, so the team can capture full state.
    static let tapThreshold = 3
    /// Sliding window over which `tapThreshold` is measured.
    static let tapWindow: TimeInterval = 5

    // MARK: Module-level mutable state (main-actor isolated by the enclosing enum)

    private static var tapTimestamps: [Date] = []
    private static var overlayVisible = false
    /// Ring buffer of the last `maxRecentEvents` outcomes from the tab-switcher launch
    /// pipeline (entered → guard hit / presenting / present completion / dismissed). This
    /// is the trace that tells whether the bug is "guard rejected the tap", "present
    /// silently failed", or "nothing at all reached the chain".
    private static var recentEvents: [(Date, String)] = []
    private static let maxRecentEvents = 12

    /// Append an event to the per-request outcome trace. Cheap; safe to call from any
    /// point in the tab-switcher launch chain.
    static func recordEvent(_ label: String) {
        recentEvents.append((Date(), label))
        let overflow = recentEvents.count - maxRecentEvents
        if overflow > 0 {
            recentEvents.removeFirst(overflow)
        }
    }

    /// Whether the overlay is allowed to surface to the user. Limited to non-production
    /// builds (DEBUG/ALPHA/EXPERIMENTAL) and to internal users on production builds.
    /// Production users tap-mashing the button won't see this dialog.
    static var isEnabled: Bool {
        if !BuildFlags.isProductionBuild { return true }
        return AppDependencyProvider.shared.internalUserDecider.isInternalUser
    }

    /// Record a tab-switcher tap. Returns `true` when the caller should *also* show the
    /// diagnostic overlay — fires purely on the tap-rate threshold, irrespective of whether
    /// the switcher is currently open. The diagnostic itself captures everything about the
    /// hierarchy state so we can tell whether the switcher is missing, hidden behind another
    /// view, in the wrong window, etc.
    static func recordTapAndShouldShow() -> Bool {
        guard isEnabled else { return false }
        let now = Date()
        tapTimestamps = tapTimestamps.filter { now.timeIntervalSince($0) <= tapWindow }
        tapTimestamps.append(now)
        if overlayVisible { return false }
        return tapTimestamps.count >= tapThreshold
    }

    /// Show the diagnostic overlay over the supplied MainViewController's key window.
    /// Logs the same content via `Logger.lifecycle.error` so it also appears in device logs.
    static func show(from mainVC: MainViewController) {
        guard isEnabled else { return }
        guard !overlayVisible, let window = mainVC.view.window else { return }
        let snapshot = collect(from: mainVC)
        Logger.lifecycle.error("[TabSwitcherDiagnostics]\n\(snapshot, privacy: .public)")
        let overlay = OverlayView(text: snapshot) {
            overlayVisible = false
            tapTimestamps.removeAll()
        }
        overlay.frame = window.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlay)
        overlayVisible = true
    }

    // MARK: - Diagnostics

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func collect(from mainVC: MainViewController) -> String {
        var lines: [String] = []
        lines.append(contentsOf: collectRecentRequests())
        lines.append(contentsOf: collectTabSwitcherVC(mainVC))
        lines.append(contentsOf: collectMainVC(mainVC))
        lines.append(contentsOf: collectPresentationChain(mainVC))
        lines.append(contentsOf: collectFullVCTree(mainVC))
        lines.append(contentsOf: collectToolbarTSButton(mainVC))
        lines.append(contentsOf: collectHeaderTSButton(mainVC))
        lines.append(contentsOf: collectFirstResponder(mainVC))
        lines.append(contentsOf: collectToolbarContainerGestures(mainVC))
        lines.append(contentsOf: collectCurrentTab(mainVC))
        lines.append(contentsOf: collectExperimentState(mainVC))
        lines.append(contentsOf: collectWindows(mainVC))

        // Recent in-process log entries pulled from OSLogStore. Limited to our own
        // subsystems and the last few minutes so the dump stays readable. Lets us see
        // assertion-style errors, warning logs, and lifecycle traces that ran in the
        // run-up to the user mashing the button. Cannot capture stderr (UIKit constraint
        // warnings, NSLog) — those go through a separate sink and aren't reachable.
        lines.append("[RECENT LOGS]")
        let logLines = collectRecentLogs(lookbackSeconds: 60, maxEntries: 60)
        if logLines.isEmpty {
            lines.append("(none captured)")
        } else {
            lines.append(contentsOf: logLines)
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Section collectors

    /// Per-request timeline — most actionable signal. Tells us whether each recent tap
    /// reached `present`, was rejected by a guard, or completed presentation.
    private static func collectRecentRequests() -> [String] {
        var lines: [String] = ["[RECENT REQUESTS] (last \(maxRecentEvents))"]
        if recentEvents.isEmpty {
            lines.append("(none recorded)")
        } else {
            let now = Date()
            for (ts, label) in recentEvents {
                let age = String(format: "%6.2fs ago", now.timeIntervalSince(ts))
                lines.append("\(age)  \(label)")
            }
        }
        lines.append("")
        return lines
    }

    private static func collectTabSwitcherVC(_ mainVC: MainViewController) -> [String] {
        var lines: [String] = ["[TAB SWITCHER VC]"]
        guard let tsvc = mainVC.tabSwitcherController else {
            lines.append("ref: nil (weak — never presented, or fully released)")
            lines.append("")
            return lines
        }
        lines.append("ref: live(\(addr(tsvc)))")
        lines.append("isViewLoaded: \(tsvc.isViewLoaded)")
        if let view = tsvc.viewIfLoaded {
            lines.append(contentsOf: describeTSVCView(view))
        }
        lines.append("isBeingPresented: \(tsvc.isBeingPresented)")
        lines.append("isBeingDismissed: \(tsvc.isBeingDismissed)")
        lines.append("parent: \(tsvc.parent.map { String(describing: type(of: $0)) } ?? "nil")")
        lines.append("presentingVC: \(tsvc.presentingViewController.map { String(describing: type(of: $0)) } ?? "nil")")
        lines.append("")
        return lines
    }

    /// Walk the TSVC view's superview ancestry + sibling z-order + hit-test sample.
    private static func describeTSVCView(_ view: UIView) -> [String] {
        var lines: [String] = []
        let windowTag = view.window.map { "in-window(level=\($0.windowLevel.rawValue))" } ?? "no-window"
        lines.append("view.window: \(windowTag)")
        lines.append("view.alpha: \(view.alpha)")
        lines.append("view.isHidden: \(view.isHidden)")
        lines.append("view.frame: \(stringify(view.frame))")
        lines.append("view.bounds: \(stringify(view.bounds))")
        lines.append("view ancestry (innermost → outermost):")
        var cursor: UIView? = view
        var depth = 0
        while let v = cursor, depth < 14 {
            lines.append(ancestryLine(for: v, depth: depth, includeGestures: false))
            cursor = v.superview
            depth += 1
        }
        if let parent = view.superview {
            lines.append("siblings in superview (back → front, * = TSVC view):")
            for (idx, sib) in parent.subviews.enumerated() {
                let marker = sib === view ? " *" : ""
                let alphaTag = sib.alpha < 1 ? " α=\(sib.alpha)" : ""
                let hiddenTag = sib.isHidden ? " HIDDEN" : ""
                lines.append("  [\(idx)]\(marker) \(type(of: sib))(\(addr(sib))) frame=\(stringify(sib.frame))\(alphaTag)\(hiddenTag)")
            }
        }
        if let window = view.window {
            let centerInWindow = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
            if let hit = window.hitTest(centerInWindow, with: nil) {
                lines.append("hitTest @ tsvc-center: \(type(of: hit))(\(addr(hit))) frame=\(stringify(hit.frame))")
            } else {
                lines.append("hitTest @ tsvc-center: nil")
            }
        }
        return lines
    }

    private static func collectMainVC(_ mainVC: MainViewController) -> [String] {
        return [
            "[MAIN VC]",
            "presentedVC: \(describe(vc: mainVC.presentedViewController))",
            "presentingVC: \(describe(vc: mainVC.presentingViewController))",
            "isBeingPresented: \(mainVC.isBeingPresented)",
            "isBeingDismissed: \(mainVC.isBeingDismissed)",
            "transitionCoordinator: \(mainVC.transitionCoordinator != nil ? "ACTIVE" : "nil")",
            "view.window: \(mainVC.view.window != nil ? "in-window" : "no-window")",
            ""
        ]
    }

    private static func collectPresentationChain(_ mainVC: MainViewController) -> [String] {
        var lines: [String] = ["[PRESENTATION CHAIN]"]
        var current: UIViewController? = mainVC.view.window?.rootViewController
        var depth = 0
        while let vc = current, depth < 12 {
            let indent = String(repeating: "  ", count: depth)
            let bP = vc.isBeingPresented ? " [bP]" : ""
            let bD = vc.isBeingDismissed ? " [bD]" : ""
            let tc = vc.transitionCoordinator != nil ? " [TC]" : ""
            lines.append("\(indent)\(type(of: vc))(\(addr(vc)))\(bP)\(bD)\(tc)")
            current = vc.presentedViewController
            depth += 1
        }
        lines.append("")
        return lines
    }

    /// children + presentedVC at every level. Catches container VCs (nav controllers, custom
    /// containers) and child VCs that the linear presentation chain would miss.
    private static func collectFullVCTree(_ mainVC: MainViewController) -> [String] {
        var lines: [String] = ["[FULL VC TREE]"]
        guard let key = mainVC.view.window?.windowScene?.windows.first(where: { $0.isKeyWindow }),
              let root = key.rootViewController else {
            lines.append("(no key window)")
            lines.append("")
            return lines
        }
        var emitted = 0
        walkVCTree(root, depth: 0, emitted: &emitted, lines: &lines)
        if emitted >= 80 {
            lines.append("… (truncated at 80 entries)")
        }
        lines.append("")
        return lines
    }

    private static func walkVCTree(_ vc: UIViewController, depth: Int, emitted: inout Int, lines: inout [String]) {
        guard emitted < 80, depth < 12 else { return }
        let indent = String(repeating: "  ", count: depth)
        let viewTag: String
        if let v = vc.viewIfLoaded {
            let attached = v.window != nil ? "win" : "no-win"
            viewTag = " view=\(attached) frame=\(stringify(v.frame))"
        } else {
            viewTag = " view-not-loaded"
        }
        let bP = vc.isBeingPresented ? " [bP]" : ""
        let bD = vc.isBeingDismissed ? " [bD]" : ""
        let tc = vc.transitionCoordinator != nil ? " [TC]" : ""
        lines.append("\(indent)- \(type(of: vc))(\(addr(vc)))\(viewTag)\(bP)\(bD)\(tc)")
        emitted += 1
        for child in vc.children {
            walkVCTree(child, depth: depth + 1, emitted: &emitted, lines: &lines)
        }
        if let presented = vc.presentedViewController {
            lines.append("\(indent)  ↳ presents:")
            walkVCTree(presented, depth: depth + 1, emitted: &emitted, lines: &lines)
        }
    }

    private static func collectToolbarTSButton(_ mainVC: MainViewController) -> [String] {
        var lines: [String] = ["[TOOLBAR TS BUTTON]"]
        if let customView = mainVC.viewCoordinator.toolbarTabSwitcherButton.customView {
            lines.append("type: \(type(of: customView))")
            lines.append("alpha: \(customView.alpha)")
            lines.append("isHidden: \(customView.isHidden)")
            lines.append("isUserInteractionEnabled: \(customView.isUserInteractionEnabled)")
            lines.append("frame: \(stringify(customView.frame))")
            lines.append("bounds: \(stringify(customView.bounds))")
            lines.append("window: \(customView.window != nil ? "in-window" : "no-window")")
            lines.append("gestureRecognizers: \(customView.gestureRecognizers?.count ?? 0)")
            for r in customView.gestureRecognizers ?? [] {
                lines.append("  - \(type(of: r)) state=\(stringify(r.state)) enabled=\(r.isEnabled)")
            }
        } else {
            lines.append("customView: nil")
        }
        lines.append("barButton.isEnabled: \(mainVC.viewCoordinator.toolbarTabSwitcherButton.isEnabled)")
        lines.append("")
        return lines
    }

    /// Duck.ai chrome's tab switcher button — the one the bug has been reported against.
    /// Includes ancestry + hit-test routing to surface "touch can't reach button" cases.
    private static func collectHeaderTSButton(_ mainVC: MainViewController) -> [String] {
        guard let header = mainVC.aiChatTabChatHeaderView else { return [] }
        let btn = header.tabSwitcherButton
        var lines: [String] = ["[HEADER TS BUTTON]"]
        lines.append("alpha: \(btn.alpha)")
        lines.append("isHidden: \(btn.isHidden)")
        lines.append("isEnabled: \(btn.isEnabled)")
        lines.append("isUserInteractionEnabled: \(btn.isUserInteractionEnabled)")
        lines.append("frame: \(stringify(btn.frame))")
        lines.append("bounds: \(stringify(btn.bounds))")
        lines.append("window: \(btn.window != nil ? "in-window" : "no-window")")
        lines.append("gestureRecognizers on button: \(btn.gestureRecognizers?.count ?? 0)")
        for r in btn.gestureRecognizers ?? [] {
            lines.append("  - \(type(of: r)) state=\(stringify(r.state)) enabled=\(r.isEnabled)")
        }
        lines.append(headerHitTestLine(for: btn))
        lines.append("button ancestry (innermost → outermost):")
        var cursor: UIView? = btn
        var depth = 0
        while let v = cursor, depth < 14 {
            lines.append(ancestryLine(for: v, depth: depth, includeGestures: true))
            let indent = String(repeating: "  ", count: depth + 1)
            for r in v.gestureRecognizers ?? [] {
                lines.append("\(indent)    · \(type(of: r)) state=\(stringify(r.state)) enabled=\(r.isEnabled) cancels=\(r.cancelsTouchesInView)")
            }
            cursor = v.superview
            depth += 1
        }
        lines.append("")
        return lines
    }

    private static func headerHitTestLine(for btn: UIView) -> String {
        guard let window = btn.window else { return "hitTest @ button-center: (no window)" }
        let centerInWindow = btn.convert(CGPoint(x: btn.bounds.midX, y: btn.bounds.midY), to: window)
        guard let hit = window.hitTest(centerInWindow, with: nil) else {
            return "hitTest @ button-center: nil"
        }
        let isSelfOrDescendant = hit === btn || hit.isDescendant(of: btn)
        let routingTag = isSelfOrDescendant ? "OK (routes to button)" : "INTERCEPTED — touch would NOT reach the button"
        return "hitTest @ button-center: \(type(of: hit))(\(addr(hit))) — \(routingTag)"
    }

    /// Renders one ancestry line; `includeGestures` controls whether the gesture-count
    /// tag is appended (the per-ancestor list is rendered separately by the caller).
    private static func ancestryLine(for v: UIView, depth: Int, includeGestures: Bool) -> String {
        let indent = String(repeating: "  ", count: depth + 1)
        let alphaTag = v.alpha < 1 ? " α=\(v.alpha)" : ""
        let hiddenTag = v.isHidden ? " HIDDEN" : ""
        let interactiveTag = v.isUserInteractionEnabled ? "" : " NO-UI"
        let grTag: String
        if includeGestures {
            let count = v.gestureRecognizers?.count ?? 0
            grTag = count > 0 ? " gestures=\(count)" : ""
        } else {
            grTag = ""
        }
        return "\(indent)- \(type(of: v))(\(addr(v))) frame=\(stringify(v.frame))\(alphaTag)\(hiddenTag)\(interactiveTag)\(grTag)"
    }

    private static func collectFirstResponder(_ mainVC: MainViewController) -> [String] {
        var lines: [String] = ["[FIRST RESPONDER]"]
        guard let key = mainVC.view.window?.windowScene?.windows.first(where: { $0.isKeyWindow }) else {
            lines.append("no key window")
            lines.append("")
            return lines
        }
        if let fr = findFirstResponder(in: key) {
            lines.append("type: \(type(of: fr))(\(addr(fr)))")
            if let v = fr as? UIView {
                lines.append("inWindow: \(v.window != nil)")
                lines.append("frame: \(stringify(v.frame))")
            }
        } else {
            lines.append("none")
        }
        lines.append("")
        return lines
    }

    private static func collectToolbarContainerGestures(_ mainVC: MainViewController) -> [String] {
        var lines: [String] = ["[TOOLBAR CONTAINER GESTURES]"]
        for r in mainVC.viewCoordinator.toolbar.gestureRecognizers ?? [] {
            lines.append("  - \(type(of: r)) state=\(stringify(r.state)) enabled=\(r.isEnabled) cancels=\(r.cancelsTouchesInView)")
        }
        lines.append("")
        return lines
    }

    private static func collectCurrentTab(_ mainVC: MainViewController) -> [String] {
        var lines: [String] = ["[CURRENT TAB]"]
        if let tabVC = mainVC.currentTab {
            lines.append("isAITab: \(tabVC.isAITab)")
            lines.append("link.url.host: \(tabVC.link?.url.host ?? "nil")")
        } else {
            lines.append("currentTab: nil")
        }
        lines.append("browsingMode: \(mainVC.tabManager.currentBrowsingMode.pixelParamValue)")
        lines.append("")
        return lines
    }

    private static func collectExperimentState(_ mainVC: MainViewController) -> [String] {
        return [
            "[EXPERIMENT FIRE-ONBOARDING]",
            "controlsLocked: \(mainVC.experimentDuckAIFireOnboardingFlow.controlsLocked)",
            "state: \(mainVC.experimentDuckAIFireOnboardingFlow.state)",
            ""
        ]
    }

    private static func collectWindows(_ mainVC: MainViewController) -> [String] {
        var lines: [String] = ["[WINDOWS]"]
        if let scene = mainVC.view.window?.windowScene {
            for (i, window) in scene.windows.enumerated() {
                let key = window.isKeyWindow ? "key" : "   "
                let level = window.windowLevel.rawValue
                let root = window.rootViewController.map { String(describing: type(of: $0)) } ?? "nil"
                lines.append("[\(i)] \(key) level=\(level) class=\(type(of: window)) root=\(root)")
            }
        }
        lines.append("")
        return lines
    }

    private static let interestingLogSubsystems: Set<String> = [
        "Lifecycle",
        "Configuration",
        "DuckPlayer",
        "LaunchSource",
        "AddressBar Picker",
        "Custom Product Page",
        "AD Attribution"
    ]

    private static func collectRecentLogs(lookbackSeconds: TimeInterval, maxEntries: Int) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date(timeIntervalSinceNow: -lookbackSeconds))
            let allEntries = try store.getEntries(at: position)
            var collected: [String] = []
            for entry in allEntries {
                guard let log = entry as? OSLogEntryLog else { continue }
                guard interestingLogSubsystems.contains(log.subsystem) else { continue }
                let age = String(format: "%6.1fs ago", -log.date.timeIntervalSinceNow)
                let level = levelTag(log.level)
                let category = log.category.isEmpty ? "" : "/\(log.category)"
                collected.append("\(age) [\(level)] \(log.subsystem)\(category): \(log.composedMessage)")
            }
            // Take the most recent N — `allEntries` is in chronological order.
            return Array(collected.suffix(maxEntries))
        } catch {
            return ["(OSLogStore unavailable: \(error.localizedDescription))"]
        }
    }

    private static func levelTag(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: return "—"
        case .debug: return "D"
        case .info: return "I"
        case .notice: return "N"
        case .error: return "E"
        case .fault: return "F"
        @unknown default: return "?"
        }
    }

    // MARK: - Helpers

    private static func addr(_ obj: AnyObject) -> String {
        let raw = Unmanaged.passUnretained(obj).toOpaque()
        return String(describing: raw)
    }

    private static func describe(vc: UIViewController?) -> String {
        guard let vc else { return "nil" }
        return "\(type(of: vc))(\(addr(vc)))"
    }

    private static func stringify(_ rect: CGRect) -> String {
        return "{\(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.size.width))x\(Int(rect.size.height))}"
    }

    private static func findFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let fr = findFirstResponder(in: sub) { return fr }
        }
        return nil
    }

    private static func stringify(_ state: UIGestureRecognizer.State) -> String {
        switch state {
        case .possible: return "possible"
        case .began: return "began"
        case .changed: return "changed"
        case .ended: return "ended"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }
}

// MARK: - OverlayView

@MainActor
private final class OverlayView: UIView {
    private let textView = UITextView()
    private let dismissHandler: () -> Void

    init(text: String, dismissHandler: @escaping () -> Void) {
        self.dismissHandler = dismissHandler
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.85)
        accessibilityIdentifier = "tabSwitcherDiagnosticsOverlay"

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.systemBackground
        card.layer.cornerRadius = 14
        card.clipsToBounds = true
        addSubview(card)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "⚠️ Did you find Tab Switcher unresponsive?"
        title.font = .preferredFont(forTextStyle: .headline)
        title.numberOfLines = 0
        card.addSubview(title)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "If so, please screenshot this and share with the team — it's the data we need to find the cause. Otherwise, just dismiss."
        subtitle.font = .preferredFont(forTextStyle: .footnote)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0
        card.addSubview(subtitle)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.text = text
        textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.backgroundColor = UIColor.secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        card.addSubview(textView)

        let copyButton = UIButton(type: .system)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.setTitle("Copy", for: .normal)
        // Capture `text` directly (closure copies the value) so the copy works even if
        // `self` is gone; use [weak copyButton] to avoid the button → closure → button cycle.
        copyButton.addAction(UIAction { [weak copyButton] _ in
            UIPasteboard.general.string = text
            // Read back to confirm — visible feedback also tells the user the copy went through.
            let written = UIPasteboard.general.string ?? ""
            copyButton?.setTitle("Copied (\(written.count) chars)", for: .normal)
            Logger.lifecycle.error("[TabSwitcherDiagnostics] copied \(written.count, privacy: .public) chars to pasteboard")
        }, for: .touchUpInside)
        card.addSubview(copyButton)

        let dismissButton = UIButton(type: .system)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.setTitle("Dismiss", for: .normal)
        dismissButton.addAction(UIAction { [weak self, handler = dismissHandler] _ in
            self?.removeFromSuperview()
            handler()
        }, for: .touchUpInside)
        card.addSubview(dismissButton)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 24),
            card.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),

            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            textView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            copyButton.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            copyButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            copyButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            dismissButton.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
            dismissButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
