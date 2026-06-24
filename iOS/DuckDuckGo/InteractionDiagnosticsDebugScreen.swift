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
import QuartzCore
import Core

/// Debug screen for the hard-to-reproduce "web view can't be scrolled but taps still work" freeze.
///
/// The freeze is PERSISTENT (it stays until the app is force-closed), so a capture taken minutes later
/// is still valid. Dumps every scroll view's drag state, presentation/transition state, and a full
/// window census. Captures auto-persist to a ring buffer so they can be exported after the fact, and
/// the Provocation section forces the suspected triggers so a reproduction *indicates the cause*.
struct InteractionDiagnosticsDebugScreen: View {

    @StateObject private var model: InteractionDiagnosticsModel

    init() {
        _model = StateObject(wrappedValue: InteractionDiagnosticsModel())
    }

    var body: some View {
        List {
            if !model.actionResult.isEmpty {
                Section {
                    Text(verbatim: model.actionResult).font(.footnote)
                } header: {
                    Text(verbatim: "Last action")
                }
            }
            Section {
                NavigationLink { InteractionRecoveryView(model: model) } label: { Text(verbatim: "Recovery") }
                NavigationLink { InteractionCaptureView(model: model) } label: { Text(verbatim: "Capture & snapshot") }
                NavigationLink { InteractionProvocationsView(model: model) } label: { Text(verbatim: "Provocations (debug)") }
            } header: {
                Text(verbatim: "Interaction Diagnostics")
            } footer: {
                Text(verbatim: "During a freeze this list itself may not scroll — so each action lives in a short "
                     + "submenu that fits without scrolling, and the Recover button (top right) is always reachable.")
            }
        }
        .navigationTitle("Interaction Diagnostics")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { model.recover() } label: { Text(verbatim: "🛟 Recover") }
            }
        }
    }
}

private struct InteractionRecoveryView: View {
    @ObservedObject var model: InteractionDiagnosticsModel
    var body: some View {
        List {
            Section {
                Button { model.recover() } label: { Text(verbatim: "Recover (surgical — reset pan/wedged recognizers)") }
                Button { model.resetScrollPan() } label: { Text(verbatim: "R1 · Reset web scroll pan only") }
                Button { model.runRecovery(.flushAppRecognizers) } label: { Text(verbatim: "R2 · Reset app recognizers") }
                Button { model.runRecovery(.bounceWindowInteraction) } label: { Text(verbatim: "R3 · Bounce window interaction") }
                Button(role: .destructive) { model.runRecovery(.flushAll) } label: { Text(verbatim: "Flush ALL recognizers (incl. system)") }
                if !model.actionResult.isEmpty {
                    Text(verbatim: model.actionResult).font(.footnote)
                }
            } header: {
                Text(verbatim: "Recovery ladder")
            } footer: {
                Text(verbatim: "Run least→most invasive against a live freeze to find the minimal action that recovers. "
                     + "R1 should fail (victim-side), R2 should clear a wedged recognizer, R3 targets a phantom touch. "
                     + "'Recover' resets only pan/wedged recognizers (no window bounce). Recovery is debug-only here — "
                     + "productionised in Part 3.")
            }
        }
        .navigationTitle("Recovery")
    }
}

private struct InteractionCaptureView: View {
    @ObservedObject var model: InteractionDiagnosticsModel
    var body: some View {
        List {
            Section {
                Button { model.capture() } label: { Text(verbatim: "Capture Snapshot") }
                if !model.report.isEmpty {
                    Button { model.copy() } label: { Text(verbatim: "Copy to Clipboard") }
                }
            } footer: {
                Text(verbatim: "Reads the live view tree of the foreground tab. Auto-saved to the ring buffer.")
            }
            Section {
                Text(verbatim: "Saved captures: \(model.savedCount)")
                if model.savedCount > 0 {
                    Button { model.copySaved() } label: { Text(verbatim: "Copy All Saved Captures") }
                    Button(role: .destructive) { model.clearSaved() } label: { Text(verbatim: "Clear Saved Captures") }
                }
            } header: {
                Text(verbatim: "Ring buffer")
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
        .navigationTitle("Capture")
    }
}

private struct InteractionProvocationsView: View {
    @ObservedObject var model: InteractionDiagnosticsModel
    var body: some View {
        List {
            Section {
                Button { model.run(.injectStuckGesture) } label: { Text(verbatim: "E1 · Inject stuck gesture") }
                Button { model.run(.clearStuckGesture) } label: { Text(verbatim: "E1 · Clear injection") }
                Button { model.run(.reparentWebView) } label: { Text(verbatim: "E2 · Reparent web view mid-drag") }
                Button { model.run(.utiHide) } label: { Text(verbatim: "E2 · UTI transition mid-drag") }
                Button { model.run(.newTab) } label: { Text(verbatim: "E2 · New tab mid-drag") }
                if !model.actionResult.isEmpty {
                    Text(verbatim: model.actionResult).font(.footnote)
                }
            } header: {
                Text(verbatim: "Provocation")
            } footer: {
                Text(verbatim: "Force a suspected trigger so a reproduction indicates the cause. E1 wedges a gesture "
                     + "(taps stay alive); E2 fires on your next drag after dismissing this screen.")
            }
        }
        .navigationTitle("Provocations")
    }
}

final class InteractionDiagnosticsModel: ObservableObject {

    @Published var report = ""
    @Published var actionResult = ""
    @Published var savedCount = FreezeCaptureStore.count()

    @MainActor
    func capture() {
        report = WebScrollFreezeProbe.captureNow()
        FreezeCaptureStore.save(report)
        savedCount = FreezeCaptureStore.count()
    }

    func copy() {
        UIPasteboard.general.string = report
    }

    func copySaved() {
        UIPasteboard.general.string = FreezeCaptureStore.exportAll()
    }

    func clearSaved() {
        FreezeCaptureStore.clear()
        savedCount = FreezeCaptureStore.count()
    }

    @MainActor
    func run(_ action: InteractionProvocation.Action) {
        actionResult = InteractionProvocation.run(action)
    }

    @MainActor
    func recover() {
        actionResult = WebScrollFreezeRecovery.recover()
    }

    @MainActor
    func runRecovery(_ rung: WebScrollFreezeRecovery.Rung) {
        actionResult = WebScrollFreezeRecovery.runRung(rung)
    }

    @MainActor
    func resetScrollPan() {
        guard let scrollView = WebScrollFreezeProbe.findMainViewController()?.currentTab?.webView?.scrollView else {
            actionResult = "R1: no web scroll view found"
            return
        }
        scrollView.panGestureRecognizer.isEnabled = false
        scrollView.panGestureRecognizer.isEnabled = true
        actionResult = "R1: reset web scroll pan"
    }
}

// MARK: - Provocation (forces a suspected trigger so a reproduction indicates the cause)

@MainActor
enum InteractionProvocation {

    enum Action {
        case injectStuckGesture, clearStuckGesture, reparentWebView, utiHide, newTab, forceFlush
    }

    private static var injected: StuckGestureRecognizer?
    private static var armer: ProvocationArmingRecognizer?

    static func run(_ action: Action) -> String {
        switch action {
        case .injectStuckGesture: return injectStuckGesture()
        case .clearStuckGesture: return clearStuckGesture()
        case .reparentWebView: return armOnNextDrag(.reparentWebView, label: "reparent the web view")
        case .utiHide: return armOnNextDrag(.utiHide, label: "UTI hide()")
        case .newTab: return armOnNextDrag(.newTab, label: "open a new tab")
        case .forceFlush: return forceFlush()
        }
    }

    /// E1 — wedge a window-level continuous gesture to test whether that signature reproduces the freeze.
    /// Models the bug faithfully: `cancelsTouchesInView = false` (taps stay alive), it only prevents pans
    /// (scroll), and it wedges once a DRAG starts (a tap never arms it), then stays in `.changed` forever.
    private static func injectStuckGesture() -> String {
        guard injected == nil else { return "Already armed. Clear it first." }
        guard let window = WebScrollFreezeProbe.keyWindow() else { return "No key window." }
        let recognizer = StuckGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        window.addGestureRecognizer(recognizer)
        injected = recognizer
        return "Armed. Dismiss this screen, then DRAG the web view once — the gesture wedges in .changed (taps stay alive). Test scrolling everywhere (web + menu), then 'Clear injection'."
    }

    private static func clearStuckGesture() -> String {
        guard let recognizer = injected else { return "Nothing injected." }
        recognizer.isEnabled = false
        recognizer.view?.removeGestureRecognizer(recognizer)
        injected = nil
        return "Cleared."
    }

    /// E2 — arm a passive recognizer that fires `effect` on the NEXT drag (truly mid-gesture), then disarms.
    /// Robust to navigation timing: dismiss this screen, then drag the web view whenever you're ready. The
    /// reparent yanks the touch's view mid-gesture — the prime way a touch never gets its `end`.
    private static func armOnNextDrag(_ effect: Action, label: String) -> String {
        if let armer { return "Already armed (\(armer.label)) — fires on your next drag." }
        guard let window = WebScrollFreezeProbe.keyWindow() else { return "No key window." }
        let recognizer = ProvocationArmingRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.label = label
        recognizer.onDragDetected = {
            perform(effect)
            Logger.interaction.error("PROVOKE \(label, privacy: .public) fired mid-drag")
            disarm()
        }
        window.addGestureRecognizer(recognizer)
        armer = recognizer
        return "Armed. Dismiss this screen and DRAG the web view — '\(label)' fires mid-drag, then disarms."
    }

    private static func disarm() {
        guard let recognizer = armer else { return }
        recognizer.isEnabled = false
        recognizer.view?.removeGestureRecognizer(recognizer)
        armer = nil
    }

    private static func perform(_ effect: Action) {
        guard let mainVC = WebScrollFreezeProbe.findMainViewController() else { return }
        switch effect {
        case .reparentWebView:
            guard let webView = mainVC.currentTab?.webView, let superview = webView.superview else { return }
            let frame = webView.frame
            webView.removeFromSuperview()
            superview.addSubview(webView)
            webView.frame = frame
        case .utiHide:
            mainVC.unifiedToggleInputCoordinator?.hide()
        case .newTab:
            mainVC.newTab()
        default:
            break
        }
    }

    /// E3 — force-cancel every gesture recognizer (toggle isEnabled) to flush a wedged recognizer / stuck
    /// touch. If scrolling recovers, a stuck touch/recognizer is confirmed AND this is a viable mitigation.
    private static func forceFlush() -> String {
        var count = 0
        for window in WebScrollFreezeProbe.allWindows() {
            flush(window, &count)
        }
        return "Toggled \(count) gesture recognizers (force-cancel). Try scrolling now — if it works, a stuck touch/recognizer was the cause."
    }

    private static func flush(_ view: UIView, _ count: inout Int) {
        view.gestureRecognizers?.forEach { recognizer in
            recognizer.isEnabled = false
            recognizer.isEnabled = true
            count += 1
        }
        view.subviews.forEach { flush($0, &count) }
    }
}

/// A deliberately wedged recognizer used only by E1. Models the bug: never cancels touches (taps stay
/// alive) and prevents only pans (scroll). Wedges once a DRAG starts (a tap never arms it), then stays in
/// `.changed` with no touches — the "scroll dead, taps alive" signature.
final class StuckGestureRecognizer: UIGestureRecognizer {
    private var disarmed = false
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !disarmed else { return }
        state = (state == .possible) ? .began : .changed
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        // Intentionally do NOT advance to a terminal state — this is the wedge under test.
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        // Intentionally ignored.
    }
    /// Once recovery resets us (via an isEnabled toggle, which forces this reset), stay inert so the
    /// recovery is verifiable on the next drag — the real bug fires once and does not re-arm. Tap
    /// "E1 · Inject stuck gesture" again to re-test.
    override func reset() {
        super.reset()
        disarmed = true
    }
    /// Prevent only pans (the scroll view's pan is a UIPanGestureRecognizer) so scrolling freezes while
    /// taps keep recognising.
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        preventedGestureRecognizer is UIPanGestureRecognizer
    }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// Passive arming recognizer for E2: detects the next drag (first `touchesMoved`) without interfering,
/// fires its callback once, then fails. Never cancels, delays, prevents, or is prevented.
final class ProvocationArmingRecognizer: UIGestureRecognizer {
    var label = ""
    var onDragDetected: (() -> Void)?
    private var fired = false
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !fired else { return }
        fired = true
        onDragDetected?()
        state = .failed
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
