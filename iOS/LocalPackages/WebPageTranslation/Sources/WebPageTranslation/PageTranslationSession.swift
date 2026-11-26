//
//  PageTranslationSession.swift
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

import Foundation
import os.log

/// The page side of a translation: its text out, the translations back in.
@MainActor
public protocol PageTranslationBridging: AnyObject {
    func extract() async throws -> (units: [PageTranslationUnit], documentID: UUID)
    func apply(_ updates: [PageTranslationUpdate], from source: String, to target: String, in documentID: UUID) async throws -> Int
}

public protocol PageTranslating: Sendable {
    /// Makes the pair ready to translate, reporting download progress from 0 to 1; only 1 when it's installed.
    func prepare(_ pairID: String) -> AsyncThrowingStream<Double, Error>
    func translate(_ units: [PageTranslationUnit], pairID: String) async throws -> [PageTranslationUpdate]
}

extension PageTranslator: PageTranslating {}

/// Where a translation shows its progress, the tab's progress bar.
@MainActor
public protocol PageTranslationProgress: AnyObject {
    func translationDidStart()
    func translationDidProgress(_ fraction: Double)
    func translationDidFinish()
}

/// Translates one tab's page: extracts its text, then translates and writes it back one batch at a time,
/// visible text first. The bridge stops a translation when the page changes, by failing its requests with
/// `CancellationError`; `cancel()` stops it when the tab starts leaving the page.
@MainActor
public final class PageTranslationSession {

    private let bridge: PageTranslationBridging
    private let translator: PageTranslating
    private let batchCharacterLimit: () -> Int
    private weak var progress: PageTranslationProgress?
    private var task: Task<Void, Never>?

    var isTranslating: Bool { task != nil }

    /// - Parameter batchCharacterLimit: read when each translation starts, so a config update applies to the next one.
    public init(bridge: PageTranslationBridging,
                translator: PageTranslating,
                batchCharacterLimit: @escaping () -> Int,
                progress: PageTranslationProgress) {
        self.bridge = bridge
        self.translator = translator
        self.batchCharacterLimit = batchCharacterLimit
        self.progress = progress
    }

    /// Ignored while a translation is running.
    public func start(_ offer: TranslationOffer) {
        guard task == nil else { return }
        progress?.translationDidStart()
        task = Task {
            await translate(offer)
            task = nil
        }
    }

    /// Stops before the next batch and leaves the progress bar alone: the navigation that cancels owns it now.
    public func cancel() {
        task?.cancel()
    }

    private func translate(_ offer: TranslationOffer) async {
        var bar = BarProgress()
        do {
            let downloaded = try await prepare(offer.pairID)
            let (units, documentID) = try await bridge.extract()
            bar = BarProgress(tracking: units, startingAt: downloaded ? Constants.downloadShare : 0)
            let limit = batchCharacterLimit()
            // Measuring every HTML unit takes long enough on a big page to stall scrolling, so batching runs off the main actor.
            let batches = await Task.detached { PageTranslationBatches.make(units, characterLimit: limit) }.value
            var applied = 0
            for batch in batches {
                applied += try await translateAndApply(batch, offer: offer, in: documentID)
                advance(&bar, past: batch)
            }
            Logger.webPageTranslation.info("Page translation: applied \(applied, privacy: .public) of \(units.count, privacy: .public) units")
        } catch is CancellationError {
            Logger.webPageTranslation.info("Page translation cancelled")
            return
        } catch {
            logFailure(error)
        }
        if !bar.isFinished && !Task.isCancelled {
            progress?.translationDidFinish()
        }
    }

    /// Waits for the pair's model, showing its download on the first part of the bar.
    /// - Returns: whether it had to download; an installed pair reports only 1.
    private func prepare(_ pairID: String) async throws -> Bool {
        var downloaded = false
        for try await fraction in translator.prepare(pairID) {
            downloaded = downloaded || fraction < 1
            if downloaded {
                progress?.translationDidProgress(Constants.downloadShare * fraction)
            }
        }
        // A cancel ends the stream rather than throwing; the download carries on for whoever asks next.
        try Task.checkCancellation()
        return downloaded
    }

    /// - Returns: how many of the batch's translations the page wrote.
    private func translateAndApply(_ batch: [PageTranslationUnit], offer: TranslationOffer, in documentID: UUID) async throws -> Int {
        try Task.checkCancellation()
        let updates = try await translator.translate(batch, pairID: offer.pairID)
        try Task.checkCancellation()
        return try await bridge.apply(updates, from: offer.source, to: offer.target, in: documentID)
    }

    /// Moves the bar past the batch's tracked units, and finishes it with the last of them.
    private func advance(_ bar: inout BarProgress, past batch: [PageTranslationUnit]) {
        guard !bar.isFinished, !Task.isCancelled else { return }
        bar.add(batch)
        progress?.translationDidProgress(bar.fraction)
        if bar.isFinished {
            progress?.translationDidFinish()
        }
    }

    private func logFailure(_ error: Error) {
        // TranslateKit's errors aren't LocalizedError, so the reason is only in the description; it may quote the page.
        Logger.webPageTranslation.error("""
            Page translation failed: \(error.localizedDescription, privacy: .public) \
            \(String(describing: error), privacy: .private)
            """)
    }
}

private extension PageTranslationSession {
    enum Constants {
        /// How much of the bar a download fills before the translation takes the rest.
        static let downloadShare = 0.8
    }
}

/// The bar tracks the visible units: it finishes once the screen is translated, and the rest of the page
/// carries on without it. A page with nothing visible tracks all its units.
private struct BarProgress {

    private let isTracked: (PageTranslationUnit) -> Bool
    private let total: Int
    /// Where the translation's part of the bar begins, after a download's.
    private let start: Double
    private var done = 0

    init(tracking units: [PageTranslationUnit] = [], startingAt start: Double = 0) {
        let isTracked: (PageTranslationUnit) -> Bool = units.contains(where: \.isVisible) ? { $0.isVisible } : { _ in true }
        self.isTracked = isTracked
        self.total = units.filter(isTracked).count
        self.start = start
    }

    /// Never true for a page with no units: its bar finishes when the translation ends.
    var isFinished: Bool { total > 0 && done == total }

    /// The whole bar's fill: the translation's share of the visible units, placed after the download's part.
    var fraction: Double {
        let translated = Double(done) / Double(total)
        let translationShare = 1 - start
        return start + translationShare * translated
    }

    mutating func add(_ batch: [PageTranslationUnit]) {
        done += batch.filter(isTracked).count
    }
}
