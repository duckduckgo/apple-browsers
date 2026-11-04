//
//  CPMBackgroundReadinessObserver.swift
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

import Common
import Foundation
import WebKit

/// Records when WebKit finishes loading the CPM background, as `loadBackgroundContent` reports it.
///
/// A background view exists from the moment WebKit starts a load, but its service worker may run seconds later; the
/// completion is load-readiness evidence, not proof of initResp delivery.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundReadinessObserver {

    typealias BackgroundLoader = @MainActor (WKWebExtensionContext, @escaping @MainActor (Error?) -> Void) -> Void

    /// Replaced in tests, where contexts are not loaded into a controller.
    var backgroundLoader: BackgroundLoader = { context, completion in
        context.loadBackgroundContentCopyingErrors { error in
            DispatchQueue.main.asyncOrNow { completion(error) }
        }
    }

    private weak var webView: WKWebView?
    private var readiness: CPMBackgroundReadiness?
    private var generation: UInt = 0
    private let now: () -> Date
    private let isEnabled: @MainActor () -> Bool

    init(now: @escaping () -> Date, isEnabled: @escaping @MainActor () -> Bool = { true }) {
        self.now = now
        self.isEnabled = isEnabled
    }

    /// Starts observing a background view WebKit has just created.
    ///
    /// The view exists, so the request joins the load in progress rather than waking a background. WebKit announces the
    /// view from inside that load, so the request waits for the next run loop turn.
    func observe(_ webView: WKWebView, in context: WKWebExtensionContext) {
        guard isEnabled() else { return }
        generation &+= 1
        let generation = generation
        self.webView = webView
        readiness = .pending
        let createdAt = now()
        DispatchQueue.main.async { [weak self, weak webView, weak context] in
            guard let self, let webView, let context, self.webView === webView, self.generation == generation, self.isEnabled() else { return }
            self.backgroundLoader(context) { [weak self, weak webView] error in
                guard let self, let webView, self.webView === webView, self.generation == generation, self.isEnabled() else { return }
                let secondsAfterViewCreation = max(0, self.now().timeIntervalSince(createdAt))
                self.readiness = error == nil ? .loaded(secondsAfterViewCreation: secondsAfterViewCreation) : .failed
            }
        }
    }

    func stopObserving() {
        generation &+= 1
        webView = nil
        readiness = nil
    }

    /// Error 6 may be notified without completing loadBackgroundContent. Invalidate its callback so
    /// a stale success cannot overwrite the observed failure of this load attempt.
    func backgroundLoadFailed() {
        guard webView != nil, readiness != nil else { return }
        generation &+= 1
        readiness = .failed
    }

    /// Readiness of `webView`, or `nil` when it is not the observed view.
    func readiness(of webView: WKWebView) -> CPMBackgroundReadiness? {
        isEnabled() && self.webView === webView ? readiness : nil
    }
}
