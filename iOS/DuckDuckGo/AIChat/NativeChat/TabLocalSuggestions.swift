//
//  TabLocalSuggestions.swift
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
import Common
import DuckAILocalTasks
import Foundation
import WebKit

@MainActor
final class TabLocalSuggestions {
    private let cache = CurrentDocumentSuggestions()
    private var document = UUID()
    private weak var webView: WKWebView?
    private var isAttachable: () -> Bool = { false }
    private var prefetch: Task<Void, Never>?
    private var settingsObserver: AnyCancellable?
    private var foregroundObserver: NSObjectProtocol?

    init() {
        settingsObserver = DuckAINativeSettings.shared.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.cancelGeneration()
                if let webView = self.webView { self.pageDidFinish(webView: webView, isAttachable: self.isAttachable) }
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(forName: .nativeChatWillStart, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelGeneration() }
        }
    }

    deinit {
        prefetch?.cancel()
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    }

    func invalidate() {
        document = UUID()
        cancelGeneration()
        webView = nil
    }

    func cancelGeneration() {
        prefetch?.cancel()
        prefetch = nil
        cache.invalidate()
    }

    func pageDidFinish(webView: WKWebView, isAttachable: @escaping () -> Bool) {
        self.webView = webView
        self.isAttachable = isAttachable
        guard DuckAINativeSettings.shared.generatesSuggestedPromptsLocally,
              DuckAINativeSettings.shared.suggestionsTrigger == .pageLoad else { return }
        prefetch?.cancel()
        prefetch = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, let webView = self.webView, webView.window != nil, !webView.isHidden else { return }
            await self.startIfNeeded(locale: Locale.current.identifier)
        }
    }

    func cachedPrompts(locale: String) -> (url: URL, prompts: [SuggestedPrompt])? {
        guard DuckAINativeSettings.shared.generatesSuggestedPromptsLocally,
              let url = webView?.url, isAttachable(),
              cache.key == SuggestionsKey(document: document, url: url,
                                          variant: DuckAINativeSettings.shared.suggestionsVariant(locale: locale)),
              let run = cache.run, case .generated(let prompts, _) = run.result, !prompts.isEmpty else { return nil }
        LocalSuggestionsDiagnostics.shared.record(run: run, variant: DuckAINativeSettings.shared.suggestionsVariant(locale: locale),
                                                   source: "Current-document cache before context collection")
        return (url, prompts)
    }

    func resolve(_ input: ResolvePageSuggestionsInput,
                 onUpdate: @escaping ([SuggestedPrompt]) -> Void) async -> SuggestedPromptsRun? {
        guard let url = webView?.url else {
            recordFallback("No current document is connected")
            return nil
        }
        guard input.url == url.absoluteString else {
            recordFallback(input.url == nil ? "Page context URL is unavailable" : "Page context belongs to another URL")
            return nil
        }
        let expected = SuggestionsKey(document: document, url: url,
                                      variant: DuckAINativeSettings.shared.suggestionsVariant(locale: input.uiLocale))
        await startIfNeeded(locale: input.uiLocale)
        guard !Task.isCancelled, document == expected.document, webView?.url == url,
              cache.key == expected else { return nil }
        let cached = cache.run != nil
        let started = ContinuousClock.now
        let result = await cache.resolve(onUpdate: onUpdate)
        guard !Task.isCancelled, cache.key == expected, document == expected.document, webView?.url == url else { return nil }
        if cached, let result {
            LocalSuggestionsDiagnostics.shared.record(run: result, variant: DuckAINativeSettings.shared.suggestionsVariant(locale: input.uiLocale),
                                                       source: "Current-document cache", sheetTime: started.duration(to: .now))
        }
        return result
    }

    private func recordFallback(_ reason: String) {
        LocalSuggestionsDiagnostics.shared.record(outcome: "Catalog fallback: \(reason)")
    }

    private func startIfNeeded(locale: String) async {
        guard DuckAINativeSettings.shared.generatesSuggestedPromptsLocally else { return }
        guard let webView, let url = webView.url, ["https", "http"].contains(url.scheme ?? "") else {
            recordFallback("No HTTP document is connected")
            return
        }
        guard !webView.isLoading, isAttachable() else {
            recordFallback(webView.isLoading ? "Page is still loading" : "Page is not attachable")
            return
        }
        let variant = DuckAINativeSettings.shared.suggestionsVariant(locale: locale)
        let key = SuggestionsKey(document: document, url: url, variant: variant)
        if cache.key == key { return }
        let body = variant.input == .body ? "(document.body?.innerText || '').slice(0, 1200)" : "''"
        let script = """
        (() => ({title: document.title.slice(0, 100),
          description: (document.querySelector('meta[name="description"]')?.content || '').slice(0, 120),
          headings: Array.from(document.querySelectorAll('h1,h2')).slice(0, 6).map(e => e.textContent.slice(0, 160)),
          content: \(body), language: document.documentElement.lang.slice(0, 30)}))()
        """
        let snapshot: [String: Any]?
        do {
            snapshot = try await webView.evaluateJavaScript(script)
        } catch {
            guard !Task.isCancelled, document == key.document, webView.url == key.url else { return }
            let failure = error as NSError
            recordFallback("Metadata extraction failed (\(failure.domain), code \(failure.code))")
            return
        }
        guard !Task.isCancelled, document == key.document, webView.url == key.url, isAttachable(),
              DuckAINativeSettings.shared.generatesSuggestedPromptsLocally,
              DuckAINativeSettings.shared.suggestionsVariant(locale: locale) == variant else { return }
        guard let data = snapshot else {
            recordFallback("Metadata extraction returned an unexpected value")
            return
        }
        let page = PageSnapshot(title: data["title"] as? String ?? "", url: url,
                                content: data["content"] as? String ?? "", language: data["language"] as? String,
                                description: data["description"] as? String ?? "", headings: data["headings"] as? [String] ?? [])
        let provider = NativeChatProviderFactory.makeProvider(for: .suggestedPrompts)
        cache.start(key: key) { update in
            let run = await SuggestionsEngine.run(page: page, variant: variant, provider: provider, onUpdate: update)
            if !Task.isCancelled {
                await LocalSuggestionsDiagnostics.shared.record(run: run, variant: variant, source: variant.trigger.rawValue)
            }
            return run
        }
    }
}

extension Notification.Name {
    static let nativeChatWillStart = Notification.Name("NativeDuckAIChatWillStart")
}
