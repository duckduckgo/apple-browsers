//
//  ReaderModeController.swift
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

import Combine
import FeatureFlags_iOS
import PrivacyConfig
import ReaderMode
import UIKit
import WebKit

@MainActor
final class ReaderModeController {
    enum State {
        case unavailable
        case offered(ReaderArticle)
        case active(ReaderArticle)

        var isAvailable: Bool {
            if case .unavailable = self { return false }
            return true
        }

        var isActive: Bool {
            if case .active = self { return true }
            return false
        }
    }

    struct Snapshot {
        let url: URL
        let html: String
    }

    private(set) var state: State = .unavailable {
        didSet { stateDidChange?() }
    }
    var stateDidChange: (() -> Void)?
    var isVisible = false {
        didSet { reconcileSampling() }
    }

    private let featureFlagger: FeatureFlagger
    private let capture: (WKWebView) async throws -> Snapshot?
    private let extract: (String, URL) async throws -> ReaderArticle?
    private weak var webView: WKWebView?
    private var generation = UUID()
    private var documentURL: URL?
    private var previousHTML: String?
    private var isNavigating = false
    private var isForeground: Bool
    private var isEnabled: Bool
    private var timer: Timer?
    private var samplingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         capture: @escaping (WKWebView) async throws -> Snapshot? = ReaderModeController.captureSnapshot,
         extract: @escaping (String, URL) async throws -> ReaderArticle? = { html, url in
             try await ReaderExtractor.shared.extract(html: html, sourceURL: url, theme: .designSystem)
         }) {
        self.featureFlagger = featureFlagger
        self.capture = capture
        self.extract = extract
        isForeground = UIApplication.shared.applicationState != .background
        isEnabled = featureFlagger.isFeatureOn(.readerMode)
        featureFlagger.updatesPublisher.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.featureFlagChanged()
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification).sink { [weak self] _ in
            self?.setForeground(false)
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification).sink { [weak self] _ in
            self?.setForeground(true)
        }.store(in: &cancellables)
    }

    deinit {
        timer?.invalidate()
        samplingTask?.cancel()
    }

    func attach(webView: WKWebView) {
        detach()
        self.webView = webView
        documentURL = webView.url
        isNavigating = webView.isLoading
        reconcileSampling()
    }

    func detach() {
        invalidateDocument()
        webView = nil
        documentURL = nil
        isNavigating = false
        reconcileSampling()
    }

    func navigationStarted() {
        isNavigating = true
        generation = UUID()
        reconcileSampling()
    }

    func processTerminated() {
        invalidateDocument()
        isNavigating = true
        reconcileSampling()
    }

    func navigationFinished() {
        isNavigating = false
        reconcileSampling()
    }

    func pageChanged() {
        invalidateDocument()
        documentURL = webView?.url
        isNavigating = false
        reconcileSampling()
    }

    func urlChanged() {
        guard !isNavigating, Self.withoutFragment(webView?.url) != Self.withoutFragment(documentURL) else { return }
        pageChanged()
    }

    func setActive(_ active: Bool) {
        switch (active, state) {
        case (true, .offered(let article)):
            guard isEnabled, featureFlagger.isFeatureOn(.readerMode), !isNavigating else { return }
            state = .active(article)
        case (false, .active(let article)): state = .offered(article)
        default: return
        }
        reconcileSampling()
    }

    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        reconcileSampling()
    }

    private func featureFlagChanged() {
        let enabled = featureFlagger.isFeatureOn(.readerMode)
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        invalidateDocument()
        reconcileSampling()
    }

    private func invalidateDocument() {
        generation = UUID()
        samplingTask?.cancel()
        previousHTML = nil
        state = .unavailable
    }

    private var canSample: Bool {
        isEnabled && featureFlagger.isFeatureOn(.readerMode) && isVisible && isForeground &&
        !isNavigating && !state.isAvailable && webView != nil
    }

    private func reconcileSampling() {
        guard canSample else {
            timer?.invalidate()
            timer = nil
            samplingTask?.cancel()
            return
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sampleIfNeeded() }
            }
        }
        sampleIfNeeded()
    }

    func sampleIfNeeded() {
        guard canSample, samplingTask == nil, let webView,
              ["http", "https"].contains(webView.url?.scheme?.lowercased() ?? "") else { return }
        let generation = generation
        samplingTask = Task { [weak self, weak webView] in
            guard let self else { return }
            defer { self.samplingTask = nil }
            guard let webView, isCurrent(generation, webView: webView) else { return }
            do {
                guard let snapshot = try await capture(webView),
                      isCurrent(generation, webView: webView),
                      Self.withoutFragment(snapshot.url) == Self.withoutFragment(webView.url),
                      snapshot.html.utf8.count <= 1_048_576,
                      snapshot.html != previousHTML else { return }
                let article = try await extract(snapshot.html, snapshot.url)
                guard isCurrent(generation, webView: webView),
                      Self.withoutFragment(snapshot.url) == Self.withoutFragment(webView.url) else { return }
                previousHTML = snapshot.html
                state = article.map(State.offered) ?? .unavailable
                reconcileSampling()
            } catch {
            }
        }
    }

    private func isCurrent(_ generation: UUID, webView: WKWebView) -> Bool {
        !Task.isCancelled && self.generation == generation && self.webView === webView && canSample
    }

    private static func withoutFragment(_ url: URL?) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        components.fragment = nil
        return components.url
    }

    private static func captureSnapshot(_ webView: WKWebView) async throws -> Snapshot? {
        let result = try await webView.callAsyncJavaScript("""
            if (!document.documentElement || document.getElementsByTagName('*').length > 50000) return null;
            const html = document.documentElement.outerHTML;
            if (html.length > 1048576) return null;
            return { url: location.href, html: html };
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        guard let result = result as? [String: String], let html = result["html"],
              let value = result["url"], let url = URL(string: value) else { return nil }
        return Snapshot(url: url, html: html)
    }
}
