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
}

private let pocStateKey = malloc(1)!

extension TabViewController {

    private enum POCApproach {
        case appleTranslation
        case foundationModel

        var label: String {
            switch self {
            case .appleTranslation: return "Apple Translation (NMT)"
            case .foundationModel: return "Foundation Model (LLM)"
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
    }

    // MARK: - Entry points (menu actions)

    func extractPageTextPOC() { togglePOC(approach: .appleTranslation) }
    func translateFoundationModelPOC() { togglePOC(approach: .foundationModel) }

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
        _ = try await evaluatePOCJavaScript("window.__ddgPOC && window.__ddgPOC.revert()")
    }

    // MARK: - Pipeline

    @MainActor
    private func runPOCPipeline(approach: POCApproach) async {
        guard let script = loadPOCScript() else {
            finishWithMessage(title: "POC failed", message: "Could not load translation.js")
            return
        }
        let start = Date()
        do {
            _ = try await evaluatePOCJavaScript(script)
            let extractResult = try await evaluatePOCJavaScript("window.__ddgPOC.extract()")
            let items = (extractResult as? [[String: Any]]) ?? []
            // uniqueTexts is ordered viewport-visible-first; viewportCount is the size of that prefix.
            let (uniqueTexts, textToIDs, viewportCount) = dedupePOC(items)

            // DEBUG (temporary): log every extracted unit in full (one entry each, no truncation).
            let lengths = uniqueTexts.map { $0.count }.sorted()
            pocLogger.info("POC extract: \(items.count, privacy: .public) raw, \(uniqueTexts.count, privacy: .public) units, \(viewportCount, privacy: .public) viewport; median \(lengths.isEmpty ? 0 : lengths[lengths.count / 2], privacy: .public), longest \(lengths.last ?? 0, privacy: .public) chars")
            for (i, unit) in uniqueTexts.enumerated() {
                pocLogger.info("POC unit [\(i, privacy: .public)] vp=\(i < viewportCount, privacy: .public) len=\(unit.count, privacy: .public): \(unit, privacy: .public)")
            }

            let translatedUnique: Int
            var viewportSeconds: Double?
            switch approach {
            case .appleTranslation:
                guard #available(iOS 18.0, *) else {
                    finishWithMessage(title: "Needs iOS 18", message: "Apple Translation requires iOS 18+.")
                    return
                }
                let result = try await runAppleTranslation(uniqueTexts: uniqueTexts,
                                                           textToIDs: textToIDs,
                                                           viewportCount: viewportCount,
                                                           start: start)
                translatedUnique = result.translated
                viewportSeconds = result.viewportSeconds
            case .foundationModel:
                guard #available(iOS 26.0, *) else {
                    finishWithMessage(title: "Needs iOS 26", message: "Foundation Models requires iOS 26 + Apple Intelligence.")
                    return
                }
                translatedUnique = try await runFoundationModel(uniqueTexts: uniqueTexts, textToIDs: textToIDs)
            }

            // User tapped Show Original mid-run: revert + state are handled there, so just bail.
            if Task.isCancelled { return }

            pocState.mode = .translated
            pocState.task = nil
            logPOCMetrics(approach: approach.label,
                          extracted: items.count,
                          unique: uniqueTexts.count,
                          translatedUnique: translatedUnique,
                          elapsed: Date().timeIntervalSince(start),
                          viewportCount: viewportCount,
                          viewportSeconds: viewportSeconds)
        } catch is CancellationError {
            return
        } catch {
            pocLogger.error("POC failed (\(approach.label, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            finishWithMessage(title: "POC failed · \(approach.label)", message: error.localizedDescription)
        }
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

    /// Detects the page's dominant language from a sample of the extracted text using the on-device
    /// NaturalLanguage recognizer (no model download). Returns nil when inconclusive, so the caller
    /// can fall back to the Translation framework's own per-batch auto-detect.
    @available(iOS 16.0, *)
    private func detectSourceLanguage(from texts: [String]) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(texts.prefix(50).joined(separator: "\n"))
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return Locale.Language(identifier: language.rawValue)
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
        let data = try JSONSerialization.data(withJSONObject: updates)
        guard let json = String(bytes: data, encoding: .utf8) else { return }
        _ = try await evaluatePOCJavaScript("window.__ddgPOC.apply(\(json))")
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
                                     start: Date) async throws -> (translated: Int, viewportSeconds: Double) {
        let targetCode = TranslationLanguageStore().targetLanguageCode
        let target = Locale.Language(identifier: targetCode)
        let source = detectSourceLanguage(from: uniqueTexts)

        // Page already in the target language → nothing to translate (avoids Apple's same-pair error).
        if let source, source.languageCode?.identifier == target.languageCode?.identifier {
            throw POCError(message: "This page already appears to be in \(translationLanguageDisplayName(forCode: targetCode)).")
        }

        // Build the work: the viewport as a single batch, then the rest in small batches.
        var indexBatches: [[Int]] = []
        if viewportCount > 0 { indexBatches.append(Array(0..<viewportCount)) }
        var cursor = viewportCount
        while cursor < uniqueTexts.count {
            let end = min(cursor + pocRestBatchSize, uniqueTexts.count)
            indexBatches.append(Array(cursor..<end))
            cursor = end
        }
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
        return (translated, viewportSeconds)
    }

    // MARK: - Engine 2: Foundation Models (LLM, iOS 26 + Apple Intelligence)

    @available(iOS 26.0, *)
    @MainActor
    private func runFoundationModel(uniqueTexts: [String], textToIDs: [String: [Int]]) async throws -> Int {
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
        return translated
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
