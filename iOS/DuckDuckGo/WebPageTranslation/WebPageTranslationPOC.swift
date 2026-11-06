//
//  WebPageTranslationPOC.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

//  Throwaway spike. One menu entry toggles Translate Page ⇄ Show Original.
//  Translate: extract visible text via translation.js → translate on-device → write back (viewport first).
//  Show Original: cancels any in-flight translation and restores the stashed originals.
//  Two engines exist (Apple Translation NMT, iOS 18+; and Foundation Models LLM, iOS 26+); the LLM
//  entry is currently hidden. Translation only works on a physical device.
//  See docs/superpowers/plans/2026-06-18-web-page-translation.md for the real design.

import UIKit
import WebKit
import SwiftUI
import Translation
import FoundationModels
import NaturalLanguage
import ObjectiveC
import os.log
import TranslateKit
import UserScript
import BrowserServicesKit

private let pocLogger = Logger(subsystem: "com.duckduckgo.ios", category: "WebPageTranslationPOC")

// Apple flow: how many off-screen strings to translate + apply per batch (after the viewport pass).
private let pocRestBatchSize = 5

// Foundation Models tuning. The LLM makes one (chunked) request at a time, so a full large page
// would take minutes; we cap the sample so the comparison is tractable. Bump the limit for a full run.
private let pocFMChunkSize = 10
private let pocFMUniqueLimit = 120

private let pocFMInstructions = """
You are a professional localization engine. Translate user-interface and web text from English into Spanish (Spain).

Rules:
- Translate meaning naturally and fluently, not word-for-word.
- Return exactly one translation per input line, matched by its id. Never add, drop, merge, split, or reorder lines.
- Keep numbers, URLs, emails, code, and placeholder tokens (e.g. %@, %1$s, {0}, {{name}}) unchanged.
- Leave brand names and proper nouns untranslated when that is the convention.
- Do not output anything except the structured translations.
"""

// Per-tab POC state, attached to TabViewController via an associated object to keep all the POC code
// self-contained in this file (no stored properties added to TabViewController).
private final class WebPageTranslationPOCState {
    enum Mode { case idle, translating, translated }
    var mode: Mode = .idle
    var task: Task<Void, Never>?
    // Set while the C-S-S `pageTranslation` path is in use (nil → legacy translation.js).
    var pageTranslation: PageTranslationSubfeature?
    // The on-demand `pageTranslation` bundle and its subfeature, created on the tab's first translation.
    var pageTranslationScript: (script: ContentScopeUserScript, feature: PageTranslationSubfeature)?
    var sourceLanguage = ""
    var targetLanguage = ""
    var unitTexts: [Int: String] = [:]   // id → extracted text, to log rejected applies
}

private let pocStateKey = malloc(1)!

extension TabViewController {

    private enum POCApproach {
        case appleTranslation
        case foundationModel
        case bergamot

        var label: String {
            switch self {
            case .appleTranslation: return "Apple Translation (NMT)"
            case .foundationModel: return "Foundation Model (LLM)"
            case .bergamot: return "Bergamot"
            }
        }
    }

    private struct POCError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var pocState: WebPageTranslationPOCState {
        if let existing = objc_getAssociatedObject(self, pocStateKey) as? WebPageTranslationPOCState {
            return existing
        }
        let created = WebPageTranslationPOCState()
        objc_setAssociatedObject(self, pocStateKey, created, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return created
    }

    /// True while a translation is in-flight or applied — drives the menu's Translate ⇄ Show Original title.
    var webPageTranslationPOCIsActive: Bool { pocState.mode != .idle }

    /// Resets translation state on a full-page navigation/refresh so the menu shows "Translate Page" again.
    /// The reloaded DOM is already the original, so no JS revert is needed.
    func resetWebPageTranslationPOCStateForNavigation() {
        pocState.task?.cancel()
        pocState.task = nil
        pocState.mode = .idle
        pocState.pageTranslation = nil
    }

    // MARK: - Entry points (menu actions)

    func extractPageTextPOC() { togglePOC(approach: .appleTranslation) }
    func translateFoundationModelPOC() { togglePOC(approach: .foundationModel) }
    func translateBergamotPOC() { togglePOC(approach: .bergamot) }

    /// Serializes the current rendered DOM (including any applied translation) to a timestamped
    /// .html file under Documents/exports/ and logs the absolute path. Independent of the translate
    /// state machine — tap before translating to snapshot the original, or after to snapshot A/B.
    func exportPageHTMLPOC() {
        Task { @MainActor [weak self] in await self?.exportPageHTML() }
    }

    @MainActor
    private func exportPageHTML() async {
        do {
            let outerHTML = (try await evaluatePOCJavaScript("document.documentElement.outerHTML")) as? String ?? ""
            let baseHref = webView.url?.absoluteString ?? ""
            let html = "<!DOCTYPE html>\n<!-- POC export from \(baseHref) -->\n"
                + injectingBaseHref(into: outerHTML, baseHref: baseHref)

            let exports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("exports", isDirectory: true)
            try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let fileURL = exports.appendingPathComponent("page-\(formatter.string(from: Date())).html")
            try html.write(to: fileURL, atomically: true, encoding: .utf8)

            Swift.print("POC export → \(fileURL.path)")
            pocLogger.info("POC export → \(fileURL.path, privacy: .public)")

            // Share sheet so the .html can be AirDropped off a physical device (the app sandbox's
            // Documents/ isn't easily reachable there). // ponytail: spike affordance.
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            activityVC.popoverPresentationController?.sourceView = view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            present(activityVC, animated: true)
        } catch {
            pocLogger.error("POC export failed: \(error.localizedDescription, privacy: .public)")
            presentExtractionPOCAlert(title: "Export failed", message: error.localizedDescription)
        }
    }

    /// Inserts a `<base href>` right after the opening `<head>` so relative CSS/img/links resolve
    /// when the saved file is hosted/opened online. // ponytail: naive string insert, not a parser.
    private func injectingBaseHref(into html: String, baseHref: String) -> String {
        guard !baseHref.isEmpty,
              let head = html.range(of: "<head", options: .caseInsensitive),
              let close = html.range(of: ">", range: head.upperBound..<html.endIndex) else {
            return html
        }
        var out = html
        out.insert(contentsOf: "<base href=\"\(baseHref)\">", at: close.upperBound)
        return out
    }

    private func togglePOC(approach: POCApproach) {
        switch pocState.mode {
        case .idle:
            startPOC(approach: approach)
        case .translating, .translated:
            showOriginalPOC()
        }
    }

    private func startPOC(approach: POCApproach) {
        guard pocState.mode == .idle else { return }
        pocState.mode = .translating
        pocState.task = Task { @MainActor [weak self] in
            await self?.runPOCPipeline(approach: approach)
        }
    }

    /// Cancels any in-flight translation, waits for it to unwind (tearing down the translation host),
    /// then restores the page's original text.
    private func showOriginalPOC() {
        let inFlight = pocState.task
        pocState.task = nil
        pocState.mode = .idle
        inFlight?.cancel()
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await inFlight?.value
            try? await self.revertPagePOC()
        }
    }

    @MainActor
    private func revertPagePOC() async throws {
        if let feature = pocState.pageTranslation {
            pocState.pageTranslation = nil
            guard let result = await feature.revert() else {
                pocLogger.error("POC css revert: no reply")
                return
            }
            pocLogger.info("POC css revert: \(result.count, privacy: .public) units restored, exact=\(result.exact, privacy: .public)")
            if !result.exact {
                // Should never happen: every occurrence is a C-S-S bug to report.
                pocLogger.error("POC css revert NOT EXACT → reloading the page")
                webView.reload()
            }
            return
        }
        _ = try await evaluatePOCJavaScript("window.__ddgPOC && window.__ddgPOC.revert()")
    }

    // MARK: - Pipeline

    /// Loads translation.js (legacy) or injects the C-S-S bundle. Nil after showing the failure.
    @MainActor
    private func preparePOCScripts() async -> (legacyScript: String?, pageTranslation: PageTranslationSubfeature?)? {
        guard !TranslationDebugSettings().useLegacyScript else {
            guard let script = loadPOCScript() else {
                finishWithMessage(title: "POC failed", message: "Could not load translation.js")
                return nil
            }
            return (script, nil)
        }
        let start = Date()
        do {
            let pageTranslation = try await injectPageTranslationPOC()
            pocLogger.info("POC css inject: \(Date().timeIntervalSince(start), privacy: .public)s")
            return (nil, pageTranslation)
        } catch {
            finishWithMessage(title: "POC failed", message: "Could not inject pageTranslation.js: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private func runPOCPipeline(approach: POCApproach) async {
        guard let prepared = await preparePOCScripts() else { return }
        let (script, pageTranslation) = prepared
        let start = Date()

        // Vars hoisted above `do` so the `catch` block can read them for the diagnostic report.
        var settings = TranslationDebugSettings()
        var targetCode: String = ""
        var detectedSourceCode: String?
        var detectionSeconds: Double?
        var items: [[String: Any]] = []
        var uniqueTexts: [String] = []
        var viewportCount: Int = 0

        do {
            settings = TranslationDebugSettings()
            items = try await extractUnitsPOC(pageTranslation: pageTranslation, legacyScript: script, scope: settings.extractionScope)
            // Plain-text units (html: false) are translated with isHtml false; legacy units are all HTML.
            let plainTexts = Set(items.filter { ($0["html"] as? NSNumber)?.boolValue == false }.compactMap { $0["text"] as? String })
            // uniqueTexts is ordered viewport-visible-first; viewportCount is the size of that prefix.
            let (deduped, textToIDs, vpCount) = dedupePOC(items)
            uniqueTexts = deduped
            viewportCount = vpCount

            // DEBUG (temporary): log every extracted unit in full (one entry each, no truncation).
            let lengths = uniqueTexts.map { $0.count }.sorted()
            pocLogger.info("POC extract: \(items.count, privacy: .public) raw, \(uniqueTexts.count, privacy: .public) units, \(viewportCount, privacy: .public) viewport; median \(lengths.isEmpty ? 0 : lengths[lengths.count / 2], privacy: .public), longest \(lengths.last ?? 0, privacy: .public) chars")
            for (i, unit) in uniqueTexts.enumerated() {
                pocLogger.info("POC unit [\(i, privacy: .public)] vp=\(i < viewportCount, privacy: .public) len=\(unit.count, privacy: .public): \(unit, privacy: .public)")
            }

            // Detect language once here in the pipeline (available to both success tail and catch).
            let rawTarget = TranslationLanguageStore().targetLanguageCode
            targetCode = String(rawTarget.split(separator: "-", maxSplits: 1).first ?? Substring(rawTarget))
            if #available(iOS 16.0, *) {
                // C-S-S html units carry data-t tags; strip them so the detector only sees text.
                let detectionTexts = pageTranslation == nil ? uniqueTexts : uniqueTexts.map(Self.strippingTags)
                let d = settings.detectionInput == .nativeSample
                    ? try await detectFromNativeSamplePOC(detector: settings.detector)
                    : detectSource(from: detectionTexts, detector: settings.detector, input: settings.detectionInput)
                detectedSourceCode = d.language?.languageCode?.identifier
                detectionSeconds = d.seconds
            }
            pocState.sourceLanguage = detectedSourceCode ?? ""
            pocState.targetLanguage = targetCode

            var runResult: POCRunResult
            switch approach {
            case .appleTranslation:
                guard #available(iOS 18.0, *) else {
                    finishWithMessage(title: "Needs iOS 18", message: "Apple Translation requires iOS 18+.")
                    return
                }
                runResult = try await runAppleTranslation(uniqueTexts: uniqueTexts,
                                                          textToIDs: textToIDs,
                                                          viewportCount: viewportCount,
                                                          start: start,
                                                          sourceCode: detectedSourceCode,
                                                          targetCode: targetCode)
            case .foundationModel:
                guard #available(iOS 26.0, *) else {
                    finishWithMessage(title: "Needs iOS 26", message: "Foundation Models requires iOS 26 + Apple Intelligence.")
                    return
                }
                runResult = try await runFoundationModel(uniqueTexts: uniqueTexts, textToIDs: textToIDs)
            case .bergamot:
                // ponytail: no availability gating for Bergamot — deliberate finding vs Apple NMT's iOS 18 floor
                runResult = try await runBergamot(uniqueTexts: uniqueTexts,
                                                   plainTexts: plainTexts,
                                                   textToIDs: textToIDs,
                                                   viewportCount: viewportCount,
                                                   start: start,
                                                   sourceCode: detectedSourceCode,
                                                   targetCode: targetCode)
            }

            // User tapped Show Original mid-run: revert + state are handled there, so just bail.
            if Task.isCancelled { return }

            let elapsed = Date().timeIntervalSince(start)
            pocState.mode = .translated
            pocState.task = nil
            logPOCMetrics(approach: approach.label,
                          extracted: items.count,
                          unique: uniqueTexts.count,
                          translatedUnique: runResult.translated,
                          elapsed: elapsed,
                          viewportCount: viewportCount,
                          viewportSeconds: runResult.viewportSeconds)

            presentDiagnosticReport(engine: approach.label, targetCode: targetCode,
                                    detectedSourceCode: detectedSourceCode, detectionSeconds: detectionSeconds,
                                    itemsCount: items.count, uniqueCount: uniqueTexts.count, viewportCount: viewportCount,
                                    elapsed: elapsed, runResult: runResult, settings: settings, errorMessage: nil)
        } catch is CancellationError {
            return
        } catch {
            pocLogger.error("POC failed (\(approach.label, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            if settings.diagnosticReportEnabled {
                pocState.mode = .idle
                pocState.task = nil
                presentDiagnosticReport(engine: approach.label, targetCode: targetCode,
                                        detectedSourceCode: detectedSourceCode, detectionSeconds: detectionSeconds,
                                        itemsCount: items.count, uniqueCount: uniqueTexts.count, viewportCount: viewportCount,
                                        elapsed: Date().timeIntervalSince(start), runResult: nil, settings: settings,
                                        errorMessage: error.localizedDescription)
            } else {
                finishWithMessage(title: "POC failed · \(approach.label)", message: error.localizedDescription)
            }
        }
    }

    /// Injects the C-S-S `pageTranslation` bundle into the main frame's page world, on demand.
    /// The message handler is (re)added on every call: it costs nothing and survives handler resets.
    @MainActor
    private func injectPageTranslationPOC() async throws -> PageTranslationSubfeature {
        let (script, feature) = try pocState.pageTranslationScript ?? makePageTranslationScriptPOC()
        pocState.pageTranslationScript = (script, feature)
        feature.webView = webView

        let controller = webView.configuration.userContentController
        for name in script.messageNames {
            controller.removeScriptMessageHandler(forName: name, contentWorld: .page)
            controller.addScriptMessageHandler(script, contentWorld: .page, name: name)
        }

        // shortcut: a page-visible window flag stops a second copy on the same document; use a native per-document flag for real.
        let source = "(() => { if (window.__ddgPageTranslationLoaded) { return; } window.__ddgPageTranslationLoaded = true;\n\(script.source)\n})(); true"
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(source, in: nil, in: .page) { result in
                continuation.resume(with: result.map { _ in () })
            }
        }
        return feature
    }

    private func makePageTranslationScriptPOC() throws -> (script: ContentScopeUserScript, feature: PageTranslationSubfeature) {
        let feature = PageTranslationSubfeature()
        let properties = ContentScopeProperties(gpcEnabled: false,
                                                sessionKey: UUID().uuidString,
                                                messageSecret: UUID().uuidString,
                                                isInternalUser: AppDependencyProvider.shared.internalUserDecider.isInternalUser,
                                                featureToggles: .supportedFeaturesOniOS)
        let script = try ContentScopeUserScript(userScriptsDependencies.privacyConfigurationManager,
                                                properties: properties,
                                                scriptContext: .pageTranslation,
                                                allowedNonisolatedFeatures: [feature.featureName],
                                                privacyConfigurationJSONGenerator: nil)
        script.registerSubfeature(delegate: feature)
        return (script, feature)
    }

    /// Extracts units through the C-S-S `pageTranslation` feature, or the legacy translation.js when `pageTranslation` is nil.
    @MainActor
    private func extractUnitsPOC(pageTranslation: PageTranslationSubfeature?, legacyScript: String?,
                                 scope: TranslationExtractionScope) async throws -> [[String: Any]] {
        guard let pageTranslation else {
            _ = try await evaluatePOCJavaScript(legacyScript ?? "")
            // fullPageHTML bypasses block extraction and translates the whole body innerHTML as one unit.
            let extractFunction = scope == .fullPageHTML ? "extractFullPage" : "extract"
            return (try await evaluatePOCJavaScript("window.__ddgPOC.\(extractFunction)()") as? [[String: Any]]) ?? []
        }
        // C-S-S path: one `extract`, no full-page mode.
        let extractStart = Date()
        guard let units = await pageTranslation.extract() else {
            throw POCError(message: "pageTranslation: no extractResult (bundle not injected, or disabled in remote config?)")
        }
        pocLogger.info("POC css extract: \(units.count, privacy: .public) units in \(Date().timeIntervalSince(extractStart), privacy: .public)s")
        pocState.pageTranslation = pageTranslation
        pocState.unitTexts = Dictionary(units.compactMap { u in
            (u["id"] as? NSNumber).flatMap { id in (u["text"] as? String).map { (id.intValue, $0) } }
        }, uniquingKeysWith: { first, _ in first })
        return units
    }

    /// Builds and presents the diagnostic report sheet. On the failure path, the report REPLACES
    /// the `finishWithMessage` alert to avoid two simultaneous UIViewController presentations.
    @MainActor
    private func presentDiagnosticReport(engine: String, targetCode: String, detectedSourceCode: String?,
                                         detectionSeconds: Double?, itemsCount: Int, uniqueCount: Int,
                                         viewportCount: Int, elapsed: TimeInterval,
                                         runResult: POCRunResult?, settings: TranslationDebugSettings,
                                         errorMessage: String?) {
        guard settings.diagnosticReportEnabled else { return }
        let source = detectedSourceCode ?? "?"
        let throughput = elapsed > 0 ? Double(runResult?.translated ?? 0) / elapsed : 0
        let report = TranslationDiagnosticReport(
            engine: engine,
            languagePair: "\(source)\u{2192}\(targetCode)",
            extractionScope: settings.extractionScope.rawValue,
            detector: settings.detector.rawValue,
            detectionInput: settings.detectionInput.rawValue,
            detectedSourceLanguage: detectedSourceCode,
            detectionSeconds: detectionSeconds,
            nodesExtracted: itemsCount, uniqueUnits: uniqueCount, viewportCount: viewportCount,
            timeToViewportSeconds: runResult?.viewportSeconds,
            fullPageSeconds: elapsed, throughput: throughput,
            bergamot: runResult?.bergamot,
            errorMessage: errorMessage)
        present(UIHostingController(rootView: TranslationDiagnosticReportView(report: report)), animated: true)
    }

    /// Resets state to idle and surfaces a message (used for failures and unmet-availability paths).
    @MainActor
    private func finishWithMessage(title: String, message: String) {
        pocState.mode = .idle
        pocState.task = nil
        presentExtractionPOCAlert(title: title, message: message)
    }

    private func loadPOCScript() -> String? {
        guard let url = Bundle.main.url(forResource: "translation", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Dedupes identical strings and orders the result viewport-visible-first.
    /// Returns the ordered unique strings, a text→node-ids map, and the count of viewport-visible uniques (the prefix).
    private func dedupePOC(_ items: [[String: Any]]) -> (uniqueTexts: [String], textToIDs: [String: [Int]], viewportCount: Int) {
        var textToIDs: [String: [Int]] = [:]
        var order: [String] = []
        var inViewport: Set<String> = []
        for item in items {
            guard let id = (item["id"] as? NSNumber)?.intValue, let text = item["text"] as? String else { continue }
            if textToIDs[text] == nil { order.append(text) }
            textToIDs[text, default: []].append(id)
            if (item["vp"] as? NSNumber)?.intValue == 1 { inViewport.insert(text) }
        }
        let viewportTexts = order.filter { inViewport.contains($0) }
        let restTexts = order.filter { !inViewport.contains($0) }
        return (viewportTexts + restTexts, textToIDs, viewportTexts.count)
    }

    private static func strippingTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Builds the detection sample per the debug setting: HTML-or-stripped × first-50-or-full-page.
    private func detectionSample(from texts: [String], input: TranslationDetectionInput) -> String {
        let selected = input.usesFullPage ? texts : Array(texts.prefix(50))
        let joined = selected.joined(separator: "\n")
        guard input.stripsHTML else { return joined }
        // ponytail: crude regex tag-strip for the spike, not a real HTML parser
        let noTags = joined.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return noTags.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                     .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detects the source language with the selected detector + input mode; returns the result and the time it took.
    @available(iOS 16.0, *)
    private func detectSource(from texts: [String], detector: TranslationDetector, input: TranslationDetectionInput) -> (language: Locale.Language?, seconds: Double) {
        let sample = detectionSample(from: texts, input: input)
        let start = ProcessInfo.processInfo.systemUptime
        let language: Locale.Language?
        switch detector {
        case .naturalLanguage:
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(sample)
            if let dominant = recognizer.dominantLanguage, dominant != .undetermined {
                language = Locale.Language(identifier: dominant.rawValue)
            } else { language = nil }
        case .cld2:
            if let code = try? TranslateKit().detectLanguage(sample).language, !code.isEmpty {
                language = Locale.Language(identifier: code)
            } else { language = nil }
        }
        return (language, ProcessInfo.processInfo.systemUptime - start)
    }

    /// Detects from a sample native reads itself (innerText + <html lang>) in an isolated world the page can't tamper with.
    /// Falls back to the lang attribute when the detector is inconclusive. Seconds include the JS read.
    @available(iOS 16.0, *)
    @MainActor
    private func detectFromNativeSamplePOC(detector: TranslationDetector) async throws -> (language: Locale.Language?, seconds: Double) {
        let start = ProcessInfo.processInfo.systemUptime
        let result = try await webView.callAsyncJavaScript(
            "return [(document.body?.innerText ?? '').slice(0, 4096), document.documentElement.lang ?? '']",
            contentWorld: .defaultClient)
        let values = result as? [String] ?? []
        let text = values.first ?? "", lang = values.last ?? ""
        let readSeconds = ProcessInfo.processInfo.systemUptime - start
        let detected = detectSource(from: [text], detector: detector, input: .nativeSample).language
        let langAttribute = lang.isEmpty ? nil : Locale.Language(identifier: lang)
        pocLogger.info("POC native sample: \(text.count, privacy: .public) chars read in \(String(format: "%.3f", readSeconds), privacy: .public)s, lang=\(lang, privacy: .public), detector=\(detected?.languageCode?.identifier ?? "nil", privacy: .public)")
        return (detected ?? langAttribute, ProcessInfo.processInfo.systemUptime - start)
    }

    /// Lightweight struct carrying engine-run results needed by the diagnostic report.
    private struct POCRunResult {
        var translated: Int
        var viewportSeconds: Double?
        var bergamot: TranslationDiagnosticReport.Bergamot?   // nil for Apple/Foundation
    }

    /// Wraps the (unambiguous) completion-handler `evaluateJavaScript` as async.
    @MainActor
    private func evaluatePOCJavaScript(_ javaScript: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(javaScript) { result, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: result) }
            }
        }
    }

    /// Writes a batch of {id, text} updates back into the page.
    @MainActor
    private func applyTranslationsPOC(_ updates: [[String: Any]]) async throws {
        guard !updates.isEmpty else { return }
        if let feature = pocState.pageTranslation {
            try await applyViaPageTranslation(feature, updates: updates)
            return
        }
        let data = try JSONSerialization.data(withJSONObject: updates)
        guard let json = String(bytes: data, encoding: .utf8) else { return }
        _ = try await evaluatePOCJavaScript("window.__ddgPOC.apply(\(json))")
    }

    /// Pushes `apply` and logs `applyResult.count` against the number sent. When some were rejected,
    /// re-sends that batch one update at a time (apply is idempotent) to log each rejected IN/OUT pair.
    @MainActor
    private func applyViaPageTranslation(_ feature: PageTranslationSubfeature, updates: [[String: Any]]) async throws {
        let typed = updates.compactMap { u in
            (u["id"] as? Int).flatMap { id in (u["text"] as? String).map { PageTranslationSubfeature.Update(id: id, text: $0) } }
        }
        let source = pocState.sourceLanguage, target = pocState.targetLanguage
        let applyStart = Date()
        guard let count = await feature.apply(source: source, target: target, updates: typed) else {
            throw POCError(message: "pageTranslation: no applyResult")
        }
        try Task.checkCancellation()
        pocLogger.info("POC css apply: \(count, privacy: .public)/\(typed.count, privacy: .public) written in \(Date().timeIntervalSince(applyStart), privacy: .public)s")
        guard count < typed.count else { return }
        for update in typed {
            guard await feature.apply(source: source, target: target, updates: [update]) == 0 else { continue }
            pocLogger.error("""
            POC css REJECTED id=\(update.id, privacy: .public)
              IN : \(self.pocState.unitTexts[update.id] ?? "?", privacy: .public)
              OUT: \(update.text, privacy: .public)
            """)
        }
    }

    /// A dimming overlay + centered spinner shown while the viewport batch translates.
    @MainActor
    private func makePOCLoadingOverlay() -> UIView {
        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.center = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
        spinner.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
        spinner.startAnimating()
        overlay.addSubview(spinner)
        view.addSubview(overlay)
        return overlay
    }

    /// Logs run metrics only. No success alert — the demo shouldn't interrupt with a dialog.
    private func logPOCMetrics(
        approach: String,
        extracted: Int,
        unique: Int,
        translatedUnique: Int,
        elapsed: TimeInterval,
        viewportCount: Int,
        viewportSeconds: Double?
    ) {
        let throughput = elapsed > 0 ? Double(translatedUnique) / elapsed : 0
        let viewport = viewportSeconds.map { String(format: ", viewport %d in %.1fs", viewportCount, $0) } ?? ""
        pocLogger.info("Done · \(approach, privacy: .public): \(translatedUnique, privacy: .public)/\(unique, privacy: .public) unique, \(extracted, privacy: .public) nodes\(viewport, privacy: .public), full \(elapsed, privacy: .public)s, \(throughput, privacy: .public) str/s")
    }

    private func presentExtractionPOCAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Engine 1: Apple Translation (NMT, iOS 18+), viewport-first

    @available(iOS 18.0, *)
    @MainActor
    private func runAppleTranslation(uniqueTexts: [String],
                                     textToIDs: [String: [Int]],
                                     viewportCount: Int,
                                     start: Date,
                                     sourceCode: String?,
                                     targetCode: String) async throws -> POCRunResult {
        let target = Locale.Language(identifier: targetCode)
        let source = sourceCode.map { Locale.Language(identifier: $0) }

        // Page already in the target language → nothing to translate (avoids Apple's same-pair error).
        if let source, source.languageCode?.identifier == target.languageCode?.identifier {
            throw POCError(message: "This page already appears to be in \(translationLanguageDisplayName(forCode: targetCode)).")
        }

        // Build the work: viewport batch then the rest using the shared batch builder.
        let debugSettings = TranslationDebugSettings()
        let scope = debugSettings.extractionScope
        let indexBatches = buildIndexBatches(uniqueCount: uniqueTexts.count, viewportCount: viewportCount, scope: scope, restBatchSize: pocRestBatchSize)
        let requestBatches = indexBatches.map { group in
            group.map { TranslationSession.Request(sourceText: uniqueTexts[$0], clientIdentifier: String($0)) }
        }

        let translator = POCTranslator()
        let host = UIHostingController(rootView: POCTranslatorView(translator: translator))
        host.view.frame = view.bounds
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let overlay = makePOCLoadingOverlay()
        var overlayVisible = true
        defer {
            if overlayVisible { overlay.removeFromSuperview() }
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }

        var translated = 0
        var viewportSeconds = Date().timeIntervalSince(start)
        var isFirstBatch = true

        let stream = translator.run(batches: requestBatches,
                                    source: source,
                                    target: target)
        for try await responses in stream {
            if Task.isCancelled { break }   // Show Original tapped: stop applying; revert handles the rest.

            var updates: [[String: Any]] = []
            for response in responses {
                guard let index = Int(response.clientIdentifier ?? ""), index < uniqueTexts.count else { continue }
                // DEBUG (temporary): log every translation pair in full.
                pocLogger.info("""
                POC translate [\(index, privacy: .public)]
                  IN : \(uniqueTexts[index], privacy: .public)
                  OUT: \(response.targetText, privacy: .public)
                """)
                for nodeID in textToIDs[uniqueTexts[index]] ?? [] {
                    updates.append(["id": nodeID, "text": response.targetText])
                }
                translated += 1
            }
            try await applyTranslationsPOC(updates)

            // The first batch is the viewport: record its time and drop the spinner.
            if isFirstBatch {
                isFirstBatch = false
                viewportSeconds = Date().timeIntervalSince(start)
                overlay.removeFromSuperview()
                overlayVisible = false
            }
        }
        return POCRunResult(translated: translated, viewportSeconds: viewportSeconds, bergamot: nil)
    }

    // MARK: - Engine 2: Foundation Models (LLM, iOS 26 + Apple Intelligence)

    @available(iOS 26.0, *)
    @MainActor
    private func runFoundationModel(uniqueTexts: [String], textToIDs: [String: [Int]]) async throws -> POCRunResult {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            throw POCError(message: "Foundation Models: this device isn’t eligible for Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            throw POCError(message: "Foundation Models: turn on Apple Intelligence in Settings.")
        case .unavailable(.modelNotReady):
            throw POCError(message: "Foundation Models: model not ready (still downloading?). Try again shortly.")
        case .unavailable(let reason):
            throw POCError(message: "Foundation Models unavailable: \(reason)")
        @unknown default:
            throw POCError(message: "Foundation Models unavailable.")
        }

        // uniqueTexts is viewport-first, so the capped sample covers visible content first.
        let limit = min(uniqueTexts.count, pocFMUniqueLimit)
        var buffer: [[String: Any]] = []
        var translated = 0
        var start = 0
        while start < limit {
            if Task.isCancelled { break }

            let end = min(start + pocFMChunkSize, limit)
            let indices = Array(start..<end)
            let promptLines = indices.map { "[\($0)] \(uniqueTexts[$0])" }.joined(separator: "\n")
            let prompt = "Translate these lines to Spanish. Each line is prefixed with its id in brackets.\n\n\(promptLines)"

            // A fresh session per chunk keeps each request independent and avoids growing the context window.
            let session = LanguageModelSession(instructions: pocFMInstructions)
            let response = try await session.respond(to: prompt, generating: POCTranslationBatch.self)

            for item in response.content.items where item.id >= 0 && item.id < uniqueTexts.count {
                for nodeID in textToIDs[uniqueTexts[item.id]] ?? [] {
                    buffer.append(["id": nodeID, "text": item.translation])
                }
                translated += 1
            }
            if buffer.count >= 40 {
                try await applyTranslationsPOC(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            start = end
        }
        try await applyTranslationsPOC(buffer)
        return POCRunResult(translated: translated, viewportSeconds: nil, bergamot: nil)
    }

    // MARK: - Engine 3: Bergamot (NMT, all supported iOS versions)

    @MainActor
    private func runBergamot(uniqueTexts: [String],
                             plainTexts: Set<String>,
                             textToIDs: [String: [Int]],
                             viewportCount: Int,
                             start: Date,
                             sourceCode detectedSourceCode: String?,
                             targetCode: String) async throws -> POCRunResult {
        // --- Direction selection ---
        // Page already in the target language → nothing to translate.
        if let detected = detectedSourceCode, detected == targetCode {
            throw POCError(message: "This page already appears to be in \(translationLanguageDisplayName(forCode: targetCode)).")
        }

        // Direction: models are X⇄en only. Use the detected source; if detection is inconclusive,
        // infer it only when the target is a non-English language (⇒ the source must be English).
        let sourceCode: String
        if let detected = detectedSourceCode {
            sourceCode = detected
        } else if targetCode != "en" {
            // ponytail: translating INTO a non-en target ⇒ source is en; can't infer when target is en
            sourceCode = "en"
        } else {
            throw POCError(message: "Couldn't detect the page's source language (target is English, so the "
                + "source could be any supported language). Try a different Detection input in the debug screen.")
        }

        guard BergamotModelProvider.supports(source: sourceCode, target: targetCode) else {
            let langs = BergamotModelProvider.supportedNonEnglishLanguages.joined(separator: ", ")
            throw POCError(message: "Bergamot supports \(langs) ⇄ en only. "
                + "Got \(sourceCode)→\(targetCode) "
                + "(detected source: \(detectedSourceCode ?? "nil"), target setting: \(targetCode)).")
        }

        // --- Overlay ---
        let overlay = makePOCLoadingOverlay()
        var overlayVisible = true
        defer {
            if overlayVisible { overlay.removeFromSuperview() }
        }

        // --- Ensure model (overlay is up, covering any download) ---
        // download.seconds == 0 means cache hit; > 0 means a real download happened (used in diagnostic report).
        let download = try await BergamotModelProvider().modelForDirection(source: sourceCode, target: targetCode)
        let spec = download.model

        // --- Build index batches using shared builder + extraction scope setting ---
        let scope = TranslationDebugSettings().extractionScope
        let indexBatches = buildIndexBatches(uniqueCount: uniqueTexts.count, viewportCount: viewportCount, scope: scope, restBatchSize: pocRestBatchSize)

        // --- Run engine off the main thread ---
        // TranslateKit/TranslationModel are blocking and non-Sendable; BergamotEngine actor owns them
        // on a single background executor so all blocking calls stay off the main actor.
        let engine = BergamotEngine()
        let modelLoadStart = Date()
        try await engine.prepare(spec: spec)
        let modelLoadSeconds = Date().timeIntervalSince(modelLoadStart)

        var translated = 0
        var viewportSeconds = Date().timeIntervalSince(start)
        var isFirstBatch = true

        for batch in indexBatches {
            if Task.isCancelled { break }

            let strings = batch.map { uniqueTexts[$0] }

            // DEBUG (temporary): log every translated IN/OUT pair in full.
            for (batchOffset, globalIndex) in batch.enumerated() {
                pocLogger.info("""
                POC bergamot [\(globalIndex, privacy: .public)]
                  IN : \(uniqueTexts[globalIndex], privacy: .public)
                """)
                _ = batchOffset // suppress unused warning; OUT logged after translate
            }

            // Translate off-main — blocking C ABI call runs inside the actor. One call per html flag.
            let isPlain = strings.map(plainTexts.contains)
            let plainOut = try await engine.translate(strings.indices.filter { isPlain[$0] }.map { strings[$0] }, isHtml: false)
            let htmlOut = try await engine.translate(strings.indices.filter { !isPlain[$0] }.map { strings[$0] }, isHtml: true)
            var plainIterator = plainOut.makeIterator(), htmlIterator = htmlOut.makeIterator()
            let outputTexts = isPlain.compactMap { $0 ? plainIterator.next() : htmlIterator.next() }

            // Back on MainActor: build updates and apply to page.
            var updates: [[String: Any]] = []
            for (batchOffset, globalIndex) in batch.enumerated() {
                guard batchOffset < outputTexts.count else { continue }
                let out = outputTexts[batchOffset]
                pocLogger.info("""
                POC bergamot [\(globalIndex, privacy: .public)]
                  OUT: \(out, privacy: .public)
                """)
                for nodeID in textToIDs[uniqueTexts[globalIndex]] ?? [] {
                    updates.append(["id": nodeID, "text": out])
                }
                translated += 1
            }
            try await applyTranslationsPOC(updates)

            if isFirstBatch {
                isFirstBatch = false
                viewportSeconds = Date().timeIntervalSince(start)
                overlay.removeFromSuperview()
                overlayVisible = false
            }
        }

        // Build bergamot metadata for the diagnostic report.
        // downloadBytes/downloadSeconds are nil on cache hit (download.seconds == 0 means nothing was downloaded).
        let bergamotMeta = TranslationDiagnosticReport.Bergamot(
            modelTier: "base-memory",
            modelLoadSeconds: modelLoadSeconds,
            downloadBytes: download.seconds > 0 ? download.bytes : nil,
            downloadSeconds: download.seconds > 0 ? download.seconds : nil
        )
        return POCRunResult(translated: translated, viewportSeconds: viewportSeconds, bergamot: bergamotMeta)
    }

    // MARK: - HTML probe (temporary manual test)

    // ponytail: throwaway probe reusing the unused Foundation-Model menu slot. Delete with the POC.
    /// Feeds HTML snippets through Apple's NMT and logs input → output, to see whether inline tags,
    /// attributes, entities, and placeholders survive translation. Device-only (NMT doesn't run on sim).
    func runHTMLProbePOC() {
        guard #available(iOS 18.0, *) else { return }
        Task { @MainActor [weak self] in await self?.runHTMLProbe() }
    }

    @available(iOS 18.0, *)
    @MainActor
    private func runHTMLProbe() async {
        let cases = [
            "Hello <b>world</b>, how are you today?",                         // inline tag
            "Please <a href=\"https://example.com\">click here</a> to continue.", // link (href must NOT be translated)
            "<p>The <strong>quick</strong> brown <em>fox</em> jumps.</p>",   // nested inline tags
            "<img src=\"cat.png\" alt=\"A red car\"> is parked outside.",     // attribute holding translatable text
            "Salt '&amp;' pepper, with more '&lt;' and '&gt;' signs.",             // HTML entities
            "First line<br>Second line after the break.",                    // void tag
            "<span class=\"price\">Total: $20</span> is due now.",           // tag with class + currency
            "Welcome back, {username}! You have 3 new messages.",            // placeholder token
            // Alignment stress: en→es reorders adjective↔noun, so a tag must re-anchor to its WORD,
            // not its slot. If the tag stays positional, emphasis/links land on the wrong word.
            "The <b>red</b> car is very fast.",                              // expect bold on \"rojo\" (after \"coche\")
            "A <strong>quick</strong> brown <em>fox</em> jumps.",            // isolates the em-drift from case [2]
            "Read the <a href=\"https://example.com\">full report</a> now.", // link must wrap \"informe completo\"
            "Click <a href=\"https://example.com\">here</a> for the <b>latest news</b>." // tags at clause ends
        ]
        let requests = cases.enumerated().map {
            TranslationSession.Request(sourceText: $1, clientIdentifier: String($0))
        }

        let translator = POCTranslator()
        let host = UIHostingController(rootView: POCTranslatorView(translator: translator))
        host.view.frame = view.bounds
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        defer {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }

        pocLogger.info("HTML probe ▶︎ start (en→es), \(cases.count, privacy: .public) cases")
        do {
            let stream = translator.run(batches: [requests],
                                        source: Locale.Language(identifier: "en"),
                                        target: Locale.Language(identifier: "es"))
            for try await responses in stream {
                for response in responses {
                    let index = Int(response.clientIdentifier ?? "")
                    let input = index.flatMap { $0 < cases.count ? cases[$0] : nil } ?? "?"
                    pocLogger.info("""
                    HTML probe [\(response.clientIdentifier ?? "?", privacy: .public)]
                      IN : \(input, privacy: .public)
                      OUT: \(response.targetText, privacy: .public)
                    """)
                }
            }
            presentExtractionPOCAlert(title: "HTML probe done", message: "Check Console — subsystem com.duckduckgo.ios, category WebPageTranslationPOC.")
        } catch {
            pocLogger.error("HTML probe failed: \(error.localizedDescription, privacy: .public)")
            presentExtractionPOCAlert(title: "HTML probe failed", message: error.localizedDescription)
        }
    }
}

// MARK: - Shared batch builder (4.2)

/// viewportOnly → only the viewport prefix.
/// batches → viewport batch then the rest in restBatchSize chunks.
/// fullPageHTML / fullPageExtracted → everything in a single translate call (fullPageHTML has one unit anyway).
func buildIndexBatches(uniqueCount: Int, viewportCount: Int, scope: TranslationExtractionScope, restBatchSize: Int) -> [[Int]] {
    guard uniqueCount > 0 else { return [] }
    switch scope {
    case .viewportOnly:
        return viewportCount > 0 ? [Array(0..<min(viewportCount, uniqueCount))] : []
    case .fullPageHTML, .fullPageExtracted:
        return [Array(0..<uniqueCount)]
    case .batches:
        var batches: [[Int]] = []
        if viewportCount > 0 { batches.append(Array(0..<min(viewportCount, uniqueCount))) }
        var cursor = viewportCount
        while cursor < uniqueCount {
            let end = min(cursor + restBatchSize, uniqueCount)
            batches.append(Array(cursor..<end))
            cursor = end
        }
        return batches
    }
}

// MARK: - Bergamot engine actor (all supported iOS versions)

/// Owns a single `TranslateKit` context + loaded `TranslationModel` on a background executor.
/// All blocking C ABI calls stay on this actor; only `[String]` values cross the boundary.
private actor BergamotEngine {
    private var kit: TranslateKit?
    private var model: TranslationModel?

    func prepare(spec: ModelSpec) throws {
        let k = try TranslateKit()
        let m = try k.loadModel(spec)
        self.kit = k
        self.model = m
    }

    func translate(_ strings: [String], isHtml: Bool) throws -> [String] {
        guard !strings.isEmpty else { return [] }
        guard let model else { throw BergamotEngineError.notPrepared }
        let results = try model.translate(strings, isHtml: isHtml)
        return results.map(\.text)
    }
}

private enum BergamotEngineError: Error {
    case notPrepared
}

// MARK: - Apple Translation offscreen SwiftUI host (iOS 18+)

@available(iOS 18.0, *)
@MainActor
private final class POCTranslator: ObservableObject {

    @Published var configuration: TranslationSession.Configuration?
    private var pendingBatches: [[TranslationSession.Request]] = []
    private var streamContinuation: AsyncThrowingStream<[TranslationSession.Response], Error>.Continuation?

    /// Runs the given request batches sequentially in one session, yielding one response array per batch.
    func run(batches: [[TranslationSession.Request]],
             source: Locale.Language?,
             target: Locale.Language) -> AsyncThrowingStream<[TranslationSession.Response], Error> {
        pendingBatches = batches
        return AsyncThrowingStream { continuation in
            self.streamContinuation = continuation
            self.configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    /// Invoked by the SwiftUI `.translationTask` action with a live session.
    func run(with session: TranslationSession) async {
        guard let continuation = streamContinuation else { return }
        let batches = pendingBatches
        do {
            try await session.prepareTranslation()   // download model + show UI, awaited before translating
            for batch in batches where !batch.isEmpty {
                let responses = try await session.translations(from: batch)
                continuation.yield(responses)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
        streamContinuation = nil
        pendingBatches = []
    }
}

@available(iOS 18.0, *)
private struct POCTranslatorView: View {
    @ObservedObject var translator: POCTranslator

    var body: some View {
        Color.clear
            .translationTask(translator.configuration) { session in
                await translator.run(with: session)
            }
    }
}

// MARK: - Foundation Models guided-generation output (iOS 26+)

@available(iOS 26.0, *)
@Generable
private struct POCTranslationBatch {
    @Guide(description: "One item per input line, matched by id.")
    var items: [POCTranslationItem]
}

@available(iOS 26.0, *)
@Generable
private struct POCTranslationItem {
    @Guide(description: "The id number of the source line.")
    var id: Int
    @Guide(description: "The Spanish translation of the source line.")
    var translation: String
}

// MARK: - C-S-S pageTranslation subfeature (page world)

/// Talks to the content-scope-scripts `pageTranslation` feature. Native pushes `extract`/`apply`/`revert`;
/// the page replies with `extractResult`/`applyResult`/`revertResult` notifications, awaited here.
final class PageTranslationSubfeature: NSObject, Subfeature {

    static let featureNameValue = "pageTranslation"
    var featureName: String { Self.featureNameValue }
    let messageOriginPolicy: MessageOriginPolicy = .all
    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?

    struct Update: Encodable { let id: Int; let text: String }
    private struct ApplyParams: Encodable { let sourceLanguage: String; let targetLanguage: String; let updates: [Update] }

    // One pending request per reply name; a newer request or the timeout resumes the old one with nil.
    @MainActor private var pending: [String: (token: Int, continuation: CheckedContinuation<[String: Any]?, Never>)] = [:]
    @MainActor private var nextToken = 0

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    @MainActor func extract() async -> [[String: Any]]? {
        await request("extract", params: nil, reply: "extractResult")?["units"] as? [[String: Any]]
    }

    @MainActor func apply(source: String, target: String, updates: [Update]) async -> Int? {
        let params = ApplyParams(sourceLanguage: source, targetLanguage: target, updates: updates)
        return (await request("apply", params: params, reply: "applyResult")?["count"] as? NSNumber)?.intValue
    }

    @MainActor func revert() async -> (count: Int, exact: Bool)? {
        guard let reply = await request("revert", params: nil, reply: "revertResult") else { return nil }
        return ((reply["count"] as? NSNumber)?.intValue ?? 0, (reply["exact"] as? NSNumber)?.boolValue ?? false)
    }

    @MainActor private func request(_ method: String, params: Encodable?, reply: String) async -> [String: Any]? {
        guard let broker, let webView else { return nil }
        nextToken += 1
        let token = nextToken
        return await withCheckedContinuation { continuation in
            pending.removeValue(forKey: reply)?.continuation.resume(returning: nil)
            pending[reply] = (token, continuation)
            broker.push(method: method, params: params, for: self, into: webView)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, self.pending[reply]?.token == token else { return }
                pocLogger.error("POC css: no \(reply, privacy: .public) within 30s")
                self.pending.removeValue(forKey: reply)?.continuation.resume(returning: nil)
            }
        }
    }

    @MainActor private func resolve(_ reply: String, params: Any) {
        pending.removeValue(forKey: reply)?.continuation.resume(returning: params as? [String: Any] ?? [:])
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case "extractResult", "applyResult", "revertResult":
            return { [weak self] params, _ in
                await self?.resolve(methodName, params: params)
                return nil
            }
        default:
            return nil
        }
    }
}
