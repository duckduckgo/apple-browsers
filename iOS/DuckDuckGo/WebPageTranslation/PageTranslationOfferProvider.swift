//
//  PageTranslationOfferProvider.swift
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

import AIChat
import Core
import Foundation
import os.log
import WebKit
import WebPageTranslation

/// Decides what translation to offer for a loaded page: reads a text sample, detects its language
/// and applies the offer rules. One instance is shared by all tabs.
@MainActor
final class PageTranslationOfferProvider {

    private let detector: PageLanguageDetector
    private let manifest: () -> TranslationManifest?
    private let capability: WebPageTranslationCapable
    private let settings: WebPageTranslationSettings
    private let deviceLanguages: () -> [String]

    init(detector: PageLanguageDetector,
         manifest: @escaping () -> TranslationManifest?,
         capability: WebPageTranslationCapable,
         settings: WebPageTranslationSettings,
         deviceLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.detector = detector
        self.manifest = manifest
        self.capability = capability
        self.settings = settings
        self.deviceLanguages = deviceLanguages
    }

    /// Read live, so turning the flag off remotely stops detection on the next page load.
    var isEnabled: Bool {
        capability.isWebPageTranslationEnabled
    }

    /// Web pages only: not DuckDuckGo search results, Duck.ai or internal pages.
    static func isEligible(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return !url.isDuckDuckGoSearch && !url.isDuckAIURL
    }

    /// Reads the page's text sample in an isolated content world, so the page can't see or tamper with it.
    func decision(in webView: WKWebView) async -> TranslationOfferDecision? {
        guard isEnabled, settings.isEnabled(forDomain: webView.url?.host) else {
            return nil
        }

        let script = "(() => (document.body?.innerText ?? '').slice(0, \(settings.sampleLength)))()"
        do {
            let sample = try await webView.evaluateJavaScript(script, contentWorld: .defaultClient) as? String
            return await decision(forSample: sample ?? "")
        } catch {
            Logger.webPageTranslation.error("Reading the page sample failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The offer to show as a banner; nil when there's none, or when the tab left the page while detecting.
    /// - Parameter isSamePage: whether the tab is still on the page detection started on. A URL change within the
    ///   page, such as `replaceState`, doesn't leave it.
    func bannerOffer(in webView: WKWebView, isSamePage: () -> Bool) async -> TranslationOffer? {
        guard case .banner(let offer) = await decision(in: webView), isSamePage() else {
            return nil
        }
        return offer
    }

    /// nil when translation is off or there's no manifest yet; otherwise the offer rules' decision.
    func decision(forSample sample: String) async -> TranslationOfferDecision? {
        guard isEnabled else {
            return nil
        }

        guard let manifest = manifest() else {
            Logger.webPageTranslation.info("Translation offer: no manifest")
            return nil
        }

        let language = await detector.detectLanguage(of: sample)
        let decision = manifest.offerDecision(detectedLanguage: language, deviceLanguages: deviceLanguages())
        Logger.webPageTranslation.info("Translation offer: \(String(describing: decision), privacy: .public)")
        return decision
    }
}
