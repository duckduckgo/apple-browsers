//
//  CPMBackgroundWebViewGraveyard.swift
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

import Foundation
import WebKit

/// Applies and measures the bounded "graveyard" mitigation after the CPM background WebContent process terminates.
///
/// A Web Extension background context is backed by a hidden `WKWebView`. When its WebContent process terminates,
/// WebKit reports the termination and creates a replacement background context. The failing sequence observed for CPM is:
///
/// 1. The old background view reports process termination.
/// 2. Native code releases its last strong reference to that view.
/// 3. WebKit is still establishing the replacement service-worker context connection through objects associated with
///    the old page/process proxy.
/// 4. Releasing that object graph too early can leave the replacement CPM context unable to complete native messaging,
///    so subsequent CPM initialization times out even though a new background view exists.
///
/// The treatment keeps one terminated view in this "graveyard" for a short grace period. This does not revive the dead
/// process or reuse the old page. It only extends the lifetime of the native WebKit objects long enough for the replacement
/// connection to settle. Retention is deliberately bounded: at most one view is held, a newer termination replaces the
/// previous entry immediately, context transitions release it, and a generation token prevents an obsolete timeout from
/// releasing a newer entry.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundWebViewGraveyard {

    enum LifecycleEvent: Equatable {
        case held
        case released
    }

    typealias ReleaseScheduler = @MainActor (_ delay: TimeInterval, _ workItem: DispatchWorkItem) -> Void

    /// Long enough for WebKit's Network process to request a replacement service-worker context connection while the
    /// terminated page's native proxy objects are still available.
    static let holdDuration: TimeInterval = 3

    private let featureFlags: (any CPMDiagnosticsFeatureFlagsProviding)?

    private var retainedWebView: WKWebView?
    private var releaseWorkItem: DispatchWorkItem?
    private var retentionGeneration = UUID()
    private var pendingTerminationTreatmentEnabled: Bool?

    var lifecycleEventHandler: (@MainActor (LifecycleEvent) -> Void)?

    /// Test seam for executing delayed releases deterministically without weakening the production hold duration.
    var releaseScheduler: ReleaseScheduler = { delay, workItem in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    init(featureFlags: (any CPMDiagnosticsFeatureFlagsProviding)?) {
        self.featureFlags = featureFlags
    }

    /// Captures treatment state for attribution and retains the terminated view when treatment is enabled.
    func handleProcessTermination(of webView: WKWebView, reason: CPMBackgroundProcessTerminationReason?) {
        guard let featureFlags else { return }
        let treatmentEnabled = featureFlags.isBackgroundGraveyardTreatmentEnabled
        if pendingTerminationTreatmentEnabled == nil {
            pendingTerminationTreatmentEnabled = treatmentEnabled
        }
        guard treatmentEnabled else { return }
        retainTerminatedWebView(webView)
    }

    /// Returns the treatment state for the termination associated with this CPM health result.
    func consumeTerminationTreatmentState() -> Bool? {
        let treatmentEnabled = pendingTerminationTreatmentEnabled
        pendingTerminationTreatmentEnabled = nil
        return treatmentEnabled
    }

    /// Clears state owned by the previous context before diagnostics starts a new context timeline.
    func resetForNewContext() {
        releaseRetainedWebView(recordEvent: false)
        pendingTerminationTreatmentEnabled = nil
    }

    /// Ends retention and marks unresolved terminations when their context unloads.
    func handleContextUnload() {
        releaseRetainedWebView()
        pendingTerminationTreatmentEnabled = nil
    }

    private func retainTerminatedWebView(_ webView: WKWebView) {
        releaseRetainedWebView(recordEvent: false)
        retainedWebView = webView
        lifecycleEventHandler?(.held)

        let generation = UUID()
        retentionGeneration = generation
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeMainThread {
                guard let self, self.retentionGeneration == generation else { return }
                self.releaseRetainedWebView()
            }
        }
        releaseWorkItem = workItem
        releaseScheduler(Self.holdDuration, workItem)
    }

    private func releaseRetainedWebView(recordEvent: Bool = true) {
        retentionGeneration = UUID()
        releaseWorkItem?.cancel()
        releaseWorkItem = nil
        guard retainedWebView != nil else { return }
        retainedWebView = nil
        if recordEvent {
            lifecycleEventHandler?(.released)
        }
    }

    var retainedWebViewCount: Int { retainedWebView == nil ? 0 : 1 }
}
