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
    static let tapWindow: TimeInterval = 6

    /// Shared mutable state used by `MainViewController` to track tap timestamps, recent
    /// request outcomes, and avoid re-presenting the overlay while it's already on screen.
    final class State {
        static let shared = State()
        var tapTimestamps: [Date] = []
        var overlayVisible = false
        /// Ring buffer of the last `maxRecentEvents` outcomes from the tab-switcher launch
        /// pipeline (entered → guard hit / presenting / present completion / dismissed).
        /// This is the trace you actually need to tell whether the bug is "guard rejected
        /// the tap", "present silently failed", or "nothing at all reached the chain".
        var recentEvents: [(Date, String)] = []
        static let maxRecentEvents = 12
        private init() {}
    }

    /// Append an event to the per-request outcome trace. Cheap; safe to call from any
    /// point in the tab-switcher launch chain.
    static func recordEvent(_ label: String) {
        State.shared.recentEvents.append((Date(), label))
        let overflow = State.shared.recentEvents.count - State.maxRecentEvents
        if overflow > 0 {
            State.shared.recentEvents.removeFirst(overflow)
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
        let state = State.shared
        let now = Date()
        state.tapTimestamps = state.tapTimestamps.filter { now.timeIntervalSince($0) <= tapWindow }
        state.tapTimestamps.append(now)
        if state.overlayVisible { return false }
        return state.tapTimestamps.count >= tapThreshold
    }

    /// Clear the tap counter — call from the `present` completion when the tab switcher
    /// actually appears, so a subsequent tap doesn't carry stale history.
    static func clearTapHistory() {
        State.shared.tapTimestamps.removeAll()
    }

    /// Show the diagnostic overlay over the supplied MainViewController's key window.
    /// Logs the same content via `Logger.lifecycle.error` so it also appears in device logs.
    static func show(from mainVC: MainViewController) {
        guard isEnabled else { return }
        guard !State.shared.overlayVisible, let window = mainVC.view.window else { return }
        let snapshot = collect(from: mainVC)
        Logger.lifecycle.error("[TabSwitcherDiagnostics]\n\(snapshot, privacy: .public)")
        let overlay = OverlayView(text: snapshot) {
            State.shared.overlayVisible = false
            State.shared.tapTimestamps.removeAll()
        }
        overlay.frame = window.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlay)
        State.shared.overlayVisible = true
    }

    // MARK: - Diagnostics

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func collect(from mainVC: MainViewController) -> String {
        var lines: [String] = []

        // Per-request timeline — most actionable signal. Tells us whether each recent
        // tap reached `present`, was rejected by a guard, or completed presentation.
        lines.append("[RECENT REQUESTS] (last \(State.maxRecentEvents))")
        if State.shared.recentEvents.isEmpty {
            lines.append("(none recorded)")
        } else {
            let now = Date()
            for (ts, label) in State.shared.recentEvents {
                let age = String(format: "%6.2fs ago", now.timeIntervalSince(ts))
                lines.append("\(age)  \(label)")
            }
        }
        lines.append("")

        // Tab switcher VC state
        lines.append("[TAB SWITCHER VC]")
        if let tsvc = mainVC.tabSwitcherController {
            lines.append("ref: live(\(addr(tsvc)))")
            lines.append("isViewLoaded: \(tsvc.isViewLoaded)")
            if let view = tsvc.viewIfLoaded {
                lines.append("view.window: \(view.window != nil ? "in-window(level=\(view.window!.windowLevel.rawValue))" : "no-window")")
                lines.append("view.alpha: \(view.alpha)")
                lines.append("view.isHidden: \(view.isHidden)")
                lines.append("view.frame: \(stringify(view.frame))")
                lines.append("view.bounds: \(stringify(view.bounds))")
                // Walk superview ancestry — if the view is detached or buried under
                // some unexpected container, this shows where it lives now.
                lines.append("view ancestry (innermost → outermost):")
                var cursor: UIView? = view
                var ancestryDepth = 0
                while let v = cursor, ancestryDepth < 14 {
                    let indent = String(repeating: "  ", count: ancestryDepth + 1)
                    let alphaTag = v.alpha < 1 ? " α=\(v.alpha)" : ""
                    let hiddenTag = v.isHidden ? " HIDDEN" : ""
                    let interactiveTag = v.isUserInteractionEnabled ? "" : " NO-UI"
                    lines.append("\(indent)- \(type(of: v))(\(addr(v))) frame=\(stringify(v.frame))\(alphaTag)\(hiddenTag)\(interactiveTag)")
                    cursor = v.superview
                    ancestryDepth += 1
                }
                // Sibling z-order — if the TSVC view is in a window but covered by a sibling
                // with a higher index, we want to see the sibling on top.
                if let parent = view.superview {
                    lines.append("siblings in superview (back → front, * = TSVC view):")
                    for (idx, sib) in parent.subviews.enumerated() {
                        let marker = sib === view ? " *" : ""
                        let alphaTag = sib.alpha < 1 ? " α=\(sib.alpha)" : ""
                        let hiddenTag = sib.isHidden ? " HIDDEN" : ""
                        lines.append("  [\(idx)]\(marker) \(type(of: sib))(\(addr(sib))) frame=\(stringify(sib.frame))\(alphaTag)\(hiddenTag)")
                    }
                }
                // Hit-test sample at center to see what UIKit would route a tap to if
                // someone tried to interact with where the TSVC should be.
                if let window = view.window {
                    let centerInWindow = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
                    if let hit = window.hitTest(centerInWindow, with: nil) {
                        lines.append("hitTest @ tsvc-center: \(type(of: hit))(\(addr(hit))) frame=\(stringify(hit.frame))")
                    } else {
                        lines.append("hitTest @ tsvc-center: nil")
                    }
                }
            }
            lines.append("isBeingPresented: \(tsvc.isBeingPresented)")
            lines.append("isBeingDismissed: \(tsvc.isBeingDismissed)")
            lines.append("parent: \(tsvc.parent.map { String(describing: type(of: $0)) } ?? "nil")")
            lines.append("presentingVC: \(tsvc.presentingViewController.map { String(describing: type(of: $0)) } ?? "nil")")
        } else {
            lines.append("ref: nil (weak — never presented, or fully released)")
        }
        lines.append("")

        // MainVC state
        lines.append("[MAIN VC]")
        lines.append("presentedVC: \(describe(vc: mainVC.presentedViewController))")
        lines.append("presentingVC: \(describe(vc: mainVC.presentingViewController))")
        lines.append("isBeingPresented: \(mainVC.isBeingPresented)")
        lines.append("isBeingDismissed: \(mainVC.isBeingDismissed)")
        lines.append("transitionCoordinator: \(mainVC.transitionCoordinator != nil ? "ACTIVE" : "nil")")
        lines.append("view.window: \(mainVC.view.window != nil ? "in-window" : "no-window")")
        lines.append("")

        // Presentation chain
        lines.append("[PRESENTATION CHAIN]")
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

        // Full VC tree — children + presentedVC at every level. Catches container VCs
        // (nav controllers, custom containers) and child VCs that the linear presentation
        // chain would miss. Capped at 80 lines / depth 12 to keep the dump readable.
        lines.append("[FULL VC TREE]")
        if let key = mainVC.view.window?.windowScene?.windows.first(where: { $0.isKeyWindow }),
           let root = key.rootViewController {
            var emitted = 0
            func walk(_ vc: UIViewController, depth: Int) {
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
                    walk(child, depth: depth + 1)
                }
                if let presented = vc.presentedViewController {
                    lines.append("\(indent)  ↳ presents:")
                    walk(presented, depth: depth + 1)
                }
            }
            walk(root, depth: 0)
            if emitted >= 80 {
                lines.append("… (truncated at 80 entries)")
            }
        } else {
            lines.append("(no key window)")
        }
        lines.append("")

        // Toolbar tab switcher button
        lines.append("[TOOLBAR TS BUTTON]")
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

        // Header tab switcher button (Duck.ai chrome)
        if let header = mainVC.aiChatTabChatHeaderView {
            lines.append("[HEADER TS BUTTON]")
            let btn = header.tabSwitcherButton
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
            // Hit-test sample at the button's center, from the window down. If hit-test
            // returns anything OTHER than this button (or a descendant that forwards to
            // it), some other view is sitting on top and stealing the touch — exactly the
            // case where `touchesBegan` would never fire and this overlay would never appear.
            if let window = btn.window {
                let centerInWindow = btn.convert(CGPoint(x: btn.bounds.midX, y: btn.bounds.midY), to: window)
                if let hit = window.hitTest(centerInWindow, with: nil) {
                    let isSelfOrDescendant = hit === btn || hit.isDescendant(of: btn)
                    let routingTag = isSelfOrDescendant ? "OK (routes to button)" : "INTERCEPTED — touch would NOT reach the button"
                    lines.append("hitTest @ button-center: \(type(of: hit))(\(addr(hit))) — \(routingTag)")
                } else {
                    lines.append("hitTest @ button-center: nil")
                }
            }
            // Ancestry: walk button → … → window. Any ancestor with isHidden=true,
            // alpha < 0.01, or isUserInteractionEnabled=false blocks the touch from
            // reaching the button regardless of the button's own state. Per-ancestor
            // gestures show recognizers that might cancel touches mid-flight.
            lines.append("button ancestry (innermost → outermost):")
            var cursor: UIView? = btn
            var depth = 0
            while let v = cursor, depth < 14 {
                let indent = String(repeating: "  ", count: depth + 1)
                let alphaTag = v.alpha < 1 ? " α=\(v.alpha)" : ""
                let hiddenTag = v.isHidden ? " HIDDEN" : ""
                let interactiveTag = v.isUserInteractionEnabled ? "" : " NO-UI"
                let grCount = v.gestureRecognizers?.count ?? 0
                let grTag = grCount > 0 ? " gestures=\(grCount)" : ""
                lines.append("\(indent)- \(type(of: v))(\(addr(v))) frame=\(stringify(v.frame))\(alphaTag)\(hiddenTag)\(interactiveTag)\(grTag)")
                for r in v.gestureRecognizers ?? [] {
                    lines.append("\(indent)    · \(type(of: r)) state=\(stringify(r.state)) enabled=\(r.isEnabled) cancels=\(r.cancelsTouchesInView)")
                }
                cursor = v.superview
                depth += 1
            }
            lines.append("")
        }

        // First responder — useful if the keyboard or a text field is holding focus and
        // diverting touches/events. Walk the responder chain from the key window.
        lines.append("[FIRST RESPONDER]")
        if let key = mainVC.view.window?.windowScene?.windows.first(where: { $0.isKeyWindow }) {
            if let fr = findFirstResponder(in: key) {
                lines.append("type: \(type(of: fr))(\(addr(fr)))")
                if let v = fr as? UIView {
                    lines.append("inWindow: \(v.window != nil)")
                    lines.append("frame: \(stringify(v.frame))")
                }
            } else {
                lines.append("none")
            }
        } else {
            lines.append("no key window")
        }
        lines.append("")

        // Gesture recognizers on the toolbar container (UnifiedInputSwipeTabsPanGestureRecognizer etc.)
        lines.append("[TOOLBAR CONTAINER GESTURES]")
        for r in mainVC.viewCoordinator.toolbar.gestureRecognizers ?? [] {
            lines.append("  - \(type(of: r)) state=\(stringify(r.state)) enabled=\(r.isEnabled) cancels=\(r.cancelsTouchesInView)")
        }
        lines.append("")

        // Current tab context
        lines.append("[CURRENT TAB]")
        if let tabVC = mainVC.currentTab {
            lines.append("isAITab: \(tabVC.isAITab)")
            lines.append("link.url.host: \(tabVC.link?.url.host ?? "nil")")
        } else {
            lines.append("currentTab: nil")
        }
        lines.append("browsingMode: \(mainVC.tabManager.currentBrowsingMode.pixelParamValue)")
        lines.append("")

        // Experiment lock — separate code path that disables the button entirely
        lines.append("[EXPERIMENT FIRE-ONBOARDING]")
        lines.append("controlsLocked: \(mainVC.experimentDuckAIFireOnboardingFlow.controlsLocked)")
        lines.append("state: \(mainVC.experimentDuckAIFireOnboardingFlow.state)")
        lines.append("")

        // Windows summary
        lines.append("[WINDOWS]")
        if let scene = mainVC.view.window?.windowScene {
            for (i, window) in scene.windows.enumerated() {
                let key = window.isKeyWindow ? "key" : "   "
                let level = window.windowLevel.rawValue
                let root = window.rootViewController.map { String(describing: type(of: $0)) } ?? "nil"
                lines.append("[\(i)] \(key) level=\(level) class=\(type(of: window)) root=\(root)")
            }
        }
        lines.append("")

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
        dismissButton.addAction(UIAction { [weak self] _ in
            self?.removeFromSuperview()
            self?.dismissHandler()
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
