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
/// presentation/transition state, and a full window census. Captures auto-persist to a ring buffer so
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
    func runRecovery(_ rung: WebScrollFreezeRecovery.Rung) {
        actionResult = WebScrollFreezeRecovery.runRung(rung)
        savedCount = FreezeCaptureStore.count()
    }

    /// Safe diagnostic: drive the scroll view directly via `setContentOffset` (no recogniser or
    /// window-interaction changes, so it cannot make a freeze worse). Splits the field mystery in two:
    /// if the page MOVES, the scroll view is healthy and the block is in gesture/touch delivery; if it
    /// does NOT move, the scroll view / content itself is stuck.
    @MainActor
    func probeProgrammaticScroll() {
        guard let scrollView = WebScrollFreezeProbe.findMainViewController()?.currentTab?.webView?.scrollView else {
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
