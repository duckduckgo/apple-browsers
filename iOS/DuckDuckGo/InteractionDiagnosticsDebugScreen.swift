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
import Core

/// Debug screen for the hard-to-reproduce "web view can't be scrolled but taps still work" freeze.
///
/// The freeze is PERSISTENT (it stays until the app is force-closed), so a capture taken minutes later
/// is still valid. Dumps the web scroll view's drag state, the WKWebView's internal gesture recognizers,
/// presentation/transition state, and a full window scan. Captures auto-persist to a ring buffer so
/// they can be diffed against a healthy baseline after the fact.
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
                NavigationLink { InteractionCaptureView(model: model) } label: { Text(verbatim: "Capture & snapshot") }
            } header: {
                Text(verbatim: "Interaction Diagnostics")
            } footer: {
                Text(verbatim: "Capture is the focus — diff a freeze capture against a healthy baseline. Recovery is not a "
                     + "shipping path (no reliable safe action found); the one safe scoped experiment lives under "
                     + "Capture → Diagnostics. Each submenu is short so it fits even if the screen can't scroll.")
            }
            Section {
                Button { model.injectStuckGesture() } label: { Text(verbatim: "Inject stuck gesture (freezes scroll)") }
                Button(role: .destructive) { model.clearStuckGesture() } label: { Text(verbatim: "Clear stuck gesture") }
            } header: {
                Text(verbatim: "Pixel test (provocation, debug-only)")
            } footer: {
                Text(verbatim: "Verifies the production freeze pixel end-to-end. Arm this, leave the screen, then drag a long "
                     + "web page a few times across the screen: scroll stays dead (taps stay alive) and "
                     + "m_debug_interaction_repeated_failed_scroll fires (mechanism wedged:*) — confirm it in the pixel log. "
                     + "It only CREATES the freeze and runs no recovery, so it can't brick taps. Clear (or force-quit) to recover.")
            }
        }
        .navigationTitle("Interaction Diagnostics")
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
                Button { model.probeProgrammaticScroll() } label: { Text(verbatim: "Scrollability probe (programmatic scroll ±400pt)") }
                Button { model.runRecovery(.resetDeferringGates) } label: { Text(verbatim: "Reset WebKit deferring gates (scoped, self-skips on live touch)") }
                Button { model.runRecovery(.resetScrollPan) } label: { Text(verbatim: "Reset web scroll pan only (scoped, self-skips on live touch)") }
                if !model.actionResult.isEmpty {
                    Text(verbatim: model.actionResult).font(.footnote)
                }
            } header: {
                Text(verbatim: "Diagnostics (safe)")
            } footer: {
                Text(verbatim: "All three are safe — no broad recogniser or window toggling. "
                     + "Scrollability probe: setContentOffset (MOVES → block is in gesture delivery; doesn't → scroll view itself is stuck). "
                     + "Both resets are scoped and self-skip if a touch is in flight. "
                     + "Each reset AUTO-SAVES a pre- and post-reset capture to the ring buffer — compare those captures to see what changed. "
                     + "If scrolling recovers after a reset, that supports (but does not prove) the corresponding hypothesis.")
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

final class InteractionDiagnosticsModel: ObservableObject {

    @Published var report = ""
    @Published var actionResult = ""
    @Published var savedCount = WebScrollFreezeDebugCaptureStore.count()

    @MainActor
    func capture() {
        report = WebScrollFreezeDebugProbe.captureNow()
        WebScrollFreezeDebugCaptureStore.save(report)
        savedCount = WebScrollFreezeDebugCaptureStore.count()
    }

    func copy() {
        UIPasteboard.general.string = report
    }

    func copySaved() {
        UIPasteboard.general.string = WebScrollFreezeDebugCaptureStore.exportAll()
    }

    func clearSaved() {
        WebScrollFreezeDebugCaptureStore.clear()
        savedCount = WebScrollFreezeDebugCaptureStore.count()
    }

    @MainActor
    func runRecovery(_ rung: WebScrollFreezeRecovery.Rung) {
        actionResult = WebScrollFreezeRecovery.runRung(rung)
        savedCount = WebScrollFreezeDebugCaptureStore.count()
    }

    @MainActor
    func injectStuckGesture() {
        actionResult = WebScrollFreezeDebugStuckGesture.inject()
    }

    @MainActor
    func clearStuckGesture() {
        actionResult = WebScrollFreezeDebugStuckGesture.clear()
    }

    /// Safe diagnostic: drive the scroll view directly via `setContentOffset` (no recogniser or
    /// window-interaction changes, so it cannot make a freeze worse). Splits the field mystery in two:
    /// if the page MOVES, the scroll view is healthy and the block is in gesture/touch delivery; if it
    /// does NOT move, the scroll view / content itself is stuck.
    @MainActor
    func probeProgrammaticScroll() {
        guard let scrollView = WebScrollFreezeDebugProbe.findMainViewController()?.currentTab?.webView?.scrollView else {
            actionResult = "Scroll probe: no web scroll view found"
            return
        }
        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        guard maxY - minY > 64 else {
            actionResult = "Scroll probe: page is not scrollable (vertical range ≤ 64pt) — nothing to test here."
            return
        }
        let before = scrollView.contentOffset.y
        let targetY = before < maxY - 1 ? min(before + 400, maxY) : max(minY, before - 400)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: targetY), animated: false)
        let after = scrollView.contentOffset.y
        let moved = abs(after - before) >= 1
        actionResult = moved
            ? "Scroll probe: offset \(Int(before)) → \(Int(after)) — MOVED ✅ scroll view is fine; block is in gesture/touch delivery."
            : "Scroll probe: offset \(Int(before)) → \(Int(after)) (target \(Int(targetY))) — DID NOT MOVE ❌ scroll view / content itself is stuck."
    }
}

// MARK: - Stuck-gesture provocation (debug-only — used to confirm the freeze pixel fires)

/// Debug-only tool to verify the production freeze pixel end-to-end. Installs a window-level recognizer
/// that wedges once a drag starts and then prevents pans (scroll) while leaving taps alive — the
/// "scroll dead, taps alive" signature. With it armed, dragging a long page repeatedly drives the real
/// detection path in `WebScrollObserver`, so `m_debug_interaction_repeated_failed_scroll` fires
/// (mechanism `wedged:*`) and can be confirmed in the pixel log.
///
/// NOT a shipping path: it only CREATES the freeze (recoverable by `clear()` or force-quit). It runs no
/// recovery, so it can't brick taps. Reachable only from the internal/debug-gated diagnostics screen.
@MainActor
enum WebScrollFreezeDebugStuckGesture {

    private static var injected: WebScrollFreezeDebugStuckGestureRecognizer?

    static func inject() -> String {
        guard injected == nil else { return "Already armed — clear it first." }
        guard let window = WebScrollFreezeDebugProbe.keyWindow() else { return "No key window." }
        let recognizer = WebScrollFreezeDebugStuckGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        window.addGestureRecognizer(recognizer)
        injected = recognizer
        return "Armed. Leave this screen, then DRAG a long web page a few times across the screen — scroll "
            + "stays dead (taps stay alive) and the freeze pixel fires after 3 drags across 2+ regions. Then tap Clear."
    }

    static func clear() -> String {
        guard let recognizer = injected else { return "Nothing armed." }
        recognizer.isEnabled = false
        recognizer.view?.removeGestureRecognizer(recognizer)
        injected = nil
        return "Cleared."
    }
}

/// Deliberately wedged recognizer for the stuck-gesture provocation. Never cancels touches (taps stay
/// alive) and prevents only pans (scroll). Wedges once a DRAG starts (a tap never arms it), then stays in
/// `.changed` with no touches.
final class WebScrollFreezeDebugStuckGestureRecognizer: UIGestureRecognizer {

    private var disarmed = false

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !disarmed else { return }
        state = (state == .possible) ? .began : .changed
    }

    /// Intentionally does not advance to a terminal state — that is the wedge under test.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {}

    /// Intentionally ignored — keeps the recognizer wedged.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {}

    /// Once an `isEnabled` toggle resets us, stay inert so a follow-up drag is unaffected — re-arm via the
    /// debug screen to test again.
    override func reset() {
        super.reset()
        disarmed = true
    }

    /// Prevent only pans (the scroll view's pan is a `UIPanGestureRecognizer`) so scrolling freezes while
    /// taps keep recognising.
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        preventedGestureRecognizer is UIPanGestureRecognizer
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
