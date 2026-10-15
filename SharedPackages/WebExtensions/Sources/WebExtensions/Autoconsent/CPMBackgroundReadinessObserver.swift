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
/// completion fires once the worker has run, so it tells a slow start from a lost message.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundReadinessObserver {

    typealias BackgroundLoader = @MainActor (WKWebExtensionContext, @escaping @MainActor (Error?) -> Void) -> Void

    /// Replaced in tests, where contexts are not loaded into a controller.
    var loadBackgroundContent: BackgroundLoader = { context, completion in
        context.loadBackgroundContent { error in
            DispatchQueue.main.asyncOrNow { completion(error) }
        }
    }

    /// Called once for each observed view when its load ends, with `.loaded` or `.failed`. Not called for a view that
    /// was replaced or no longer observed before its load ended.
    var onLoadFinished: (@MainActor (CPMBackgroundReadiness) -> Void)?

    private weak var webView: WKWebView?
    private var readiness: CPMBackgroundReadiness?
    private let now: () -> Date

    init(now: @escaping () -> Date) {
        self.now = now
    }

    /// Starts observing a background view WebKit has just created.
    ///
    /// The view exists, so the request joins the load in progress rather than waking a background. WebKit announces the
    /// view from inside that load, so the request waits for the next run loop turn.
    func observe(_ webView: WKWebView, in context: WKWebExtensionContext) {
        self.webView = webView
        readiness = .pending
        let createdAt = now()
        DispatchQueue.main.async { [weak self, weak webView, weak context] in
            guard let self, let webView, let context, self.webView === webView else { return }
            self.loadBackgroundContent(context) { [weak self, weak webView] error in
                guard let self, let webView, self.webView === webView else { return }
                let secondsAfterViewCreation = self.now().timeIntervalSince(createdAt)
                let readiness: CPMBackgroundReadiness = error == nil ? .loaded(secondsAfterViewCreation: secondsAfterViewCreation) : .failed
                self.readiness = readiness
                self.onLoadFinished?(readiness)
            }
        }
    }

    func stopObserving() {
        webView = nil
        readiness = nil
    }

    /// Readiness of `webView`, or `nil` when it is not the observed view.
    func readiness(of webView: WKWebView) -> CPMBackgroundReadiness? {
        self.webView === webView ? readiness : nil
    }
}
