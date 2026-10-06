//
//  DataStoreWarmup.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Core
import WebKit
import PixelKit

/// WKWebsiteDataStore is basically non-functional until a web view has been instanciated and a page is successfully loaded.
public class DataStoreWarmup {

    public enum ApplicationState: String {
        case active
        case inactive
        case background
        case handlingShortcut
        case unknown
    }

    private let pixelFiring: (any PixelKitFiring)?

    public init(pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    /// - Returns: `true` when the page reported back, `false` when it timed out. A timed-out
    /// warm-up leaves the data store in an unknown state, so the caller must not record it as done.
    @MainActor
    public func ensureReady(applicationState: ApplicationState, fireMode: Bool) async -> Bool {
        pixelFiring?.fire(Pixel.Event.webkitWarmupStart(appState: applicationState.rawValue))
        let completed = await BlockingNavigationDelegate(fireMode: fireMode,
                                                        pixelFiring: pixelFiring).loadInBackgroundWebView(url: URL(string: "about:blank")!)

        // Only a real completion fires the finished pixel.
        if completed {
            pixelFiring?.fire(Pixel.Event.webkitWarmupFinished(appState: applicationState.rawValue))
        }
        return completed
    }

}

public class BlockingNavigationDelegate: NSObject, WKNavigationDelegate {

    private let fireMode: Bool

    /// Upper bound on the warm-up load.
    private let timeout: TimeInterval

    /// Resumes the pending `loadInBackgroundWebView` wait.
    private var completion: ((_ completed: Bool) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?

    private let pixelFiring: (any PixelKitFiring)?

    public init(fireMode: Bool,
                timeout: TimeInterval = 10,
                pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.fireMode = fireMode
        self.timeout = timeout
        self.pixelFiring = pixelFiring
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        return .allow
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if completion == nil {
            pixelFiring?.fire(Pixel.Event.webKitWarmupUnexpectedDidFinish)
        }
        finish(completed: true)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pixelFiring?.fire(Pixel.Event.webKitDidTerminateDuringWarmup)

        if completion == nil {
            pixelFiring?.fire(Pixel.Event.webKitWarmupUnexpectedDidTerminate)
        }
        // Reported back, so the warm-up is not retried. Matches the behaviour before the timeout
        // existed, keeping the historical start/finished baseline comparable.
        finish(completed: true)
    }

    @MainActor
    public func prepareWebView() -> WKWebView {
        let config = WKWebViewConfiguration.persistent(fireMode: fireMode)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        return webView
    }

    @MainActor
    /// - Returns: `true` when the navigation reported back, `false` when the timeout fired.
    @discardableResult
    public func loadInBackgroundWebView(url: URL) async -> Bool {
        let webView = prepareWebView()

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // Registered before the load starts, so a `didFinish` delivered on a later run loop
            // turn always finds a completion to call.
            completion = { continuation.resume(returning: $0) }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.completion != nil else { return }

                Logger.general.error("Timed out warming up the website data store after \(self.timeout, privacy: .public)s")
                self.pixelFiring?.fire(DataClearingTimeoutPixels.warmupNavigationTimedOut, frequency: .dailyAndStandard)
                self.finish(completed: false)
            }
            timeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)

            webView.load(URLRequest(url: url))
        }
    }

    /// Resumes the pending wait, at most once.
    private func finish(completed: Bool) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        let completion = self.completion
        self.completion = nil
        completion?(completed)
    }

}
