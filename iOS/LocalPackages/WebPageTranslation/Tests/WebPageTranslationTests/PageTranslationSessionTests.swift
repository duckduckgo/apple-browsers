//
//  PageTranslationSessionTests.swift
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
import Testing
@testable import WebPageTranslation

@MainActor
@Suite
struct PageTranslationSessionTests {

    private final class FakeBridge: PageTranslationBridging {
        var units: [PageTranslationUnit] = []
        var extractError: Error?
        var applied: [(updates: [PageTranslationUpdate], source: String, target: String, documentID: UUID)] = []
        let documentID = UUID()
        /// With `suspendsApply`, each apply waits until `resumeApply()`.
        var suspendsApply = false
        private var applyContinuation: CheckedContinuation<Void, Never>?

        var isApplySuspended: Bool { applyContinuation != nil }

        func resumeApply() {
            applyContinuation?.resume()
            applyContinuation = nil
        }

        func extract() async throws -> (units: [PageTranslationUnit], documentID: UUID) {
            if let extractError { throw extractError }
            return (units, documentID)
        }

        func apply(_ updates: [PageTranslationUpdate], from source: String, to target: String, in documentID: UUID) async throws -> Int {
            applied.append((updates, source, target, documentID))
            if suspendsApply {
                await withCheckedContinuation { applyContinuation = $0 }
            }
            return updates.count
        }
    }

    /// Answers with each unit's text plus " (en)"; with `suspends`, waits until `resume()`.
    private final class FakeTranslator: PageTranslating, @unchecked Sendable {
        var suspends = false
        private(set) var calls: [(units: [PageTranslationUnit], pairID: String)] = []
        private var continuation: CheckedContinuation<Void, Never>?

        var isSuspended: Bool { continuation != nil }

        func translate(_ units: [PageTranslationUnit], pairID: String) async throws -> [PageTranslationUpdate] {
            calls.append((units, pairID))
            if suspends {
                await withCheckedContinuation { continuation = $0 }
            }
            return units.map { PageTranslationUpdate(id: $0.id, text: "\($0.text) (en)") }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }

        /// The pair is installed unless a test gives `prepare` a download to report: `downloadProgress`, then
        /// `downloadError` or the end, or a download held open with `holdsDownload` until the session stops listening.
        var downloadProgress: [Double] = []
        var downloadError: Error?
        var holdsDownload = false
        private(set) var stoppedListening = false
        private(set) var isDownloadHeld = false

        func isInstalled(_ pairID: String) -> Bool {
            downloadProgress.isEmpty && downloadError == nil && !holdsDownload
        }

        func prepare(_ pairID: String) -> AsyncThrowingStream<Double, Error> {
            AsyncThrowingStream { continuation in
                guard !downloadProgress.isEmpty || downloadError != nil || holdsDownload else {
                    continuation.yield(1)
                    continuation.finish()
                    return
                }
                downloadProgress.forEach { continuation.yield($0) }
                if holdsDownload {
                    continuation.onTermination = { [weak self] _ in self?.stoppedListening = true }
                    isDownloadHeld = true
                    return
                }
                continuation.finish(throwing: downloadError)
            }
        }
    }

    private final class ProgressSpy: PageTranslationProgress {
        var events: [String] = []

        func translationDidStart() { events.append("start") }
        func translationDidProgress(_ fraction: Double) { events.append("\(fraction)") }
        func translationDidFinish() { events.append("finish") }
    }

    private struct ExtractFailure: Error {}

    private let bridge = FakeBridge()
    private let translator = FakeTranslator()
    private let progress = ProgressSpy()
    private let offer = TranslationOffer(source: "fr", target: "en", pairID: "fr-en-base", downloadBytes: 0)

    private func makeSession(characterLimit: @escaping () -> Int = { 2000 }) -> PageTranslationSession {
        PageTranslationSession(bridge: bridge, translator: translator, batchCharacterLimit: characterLimit, progress: progress)
    }

    private func waitUntilDone(_ session: PageTranslationSession) async {
        while session.isTranslating {
            await Task.yield()
        }
    }

    /// Five one-character units, ids 1 to 5; `visible` lists the ones in the viewport.
    private func units(visible: Set<Int>) -> [PageTranslationUnit] {
        (1...5).map { PageTranslationUnit(id: $0, text: "\($0)", html: false, vp: visible.contains($0) ? 1 : 0) }
    }

    @available(iOS 16, macOS 13, *)
    @Test("start extracts, translates and applies to the extracted document", .timeLimit(.minutes(1)))
    func startExtractsTranslatesAndApplies() async {
        bridge.units = [PageTranslationUnit(id: 1, text: "Bonjour", html: false, vp: 1),
                        PageTranslationUnit(id: 2, text: "Merci", html: false, vp: 0)]
        let session = makeSession()

        session.start(offer)
        #expect(session.isTranslating)
        await waitUntilDone(session)

        #expect(translator.calls.map(\.pairID) == ["fr-en-base", "fr-en-base"])
        #expect(bridge.applied.flatMap(\.updates) == [PageTranslationUpdate(id: 1, text: "Bonjour (en)"),
                                                      PageTranslationUpdate(id: 2, text: "Merci (en)")])
        #expect(bridge.applied.allSatisfy { $0.source == "fr" && $0.target == "en" && $0.documentID == bridge.documentID })
    }

    @available(iOS 16, macOS 13, *)
    @Test("batches are translated and applied one at a time, visible units first", .timeLimit(.minutes(1)))
    func appliesOneBatchAtATimeVisibleFirst() async {
        bridge.units = units(visible: [5])
        let session = makeSession(characterLimit: { 2 })

        session.start(offer)
        await waitUntilDone(session)

        #expect(translator.calls.map { $0.units.map(\.id) } == [[5], [1, 2], [3, 4]])
        #expect(bridge.applied.map { $0.updates.map(\.id) } == [[5], [1, 2], [3, 4]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("progress moves after each applied batch, then finishes, with all units visible or none",
          .timeLimit(.minutes(1)), arguments: [Set(1...5), []])
    func reportsProgressPerBatch(visible: Set<Int>) async {
        bridge.units = units(visible: visible)
        let session = makeSession(characterLimit: { 2 })

        session.start(offer)
        await waitUntilDone(session)

        #expect(progress.events == ["start", "0.4", "0.8", "1.0", "finish"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("the bar finishes once the visible units are applied, and the rest of the page carries on", .timeLimit(.minutes(1)))
    func finishesProgressWhenTheVisibleUnitsAreApplied() async {
        bridge.units = units(visible: [5])
        let session = makeSession(characterLimit: { 2 })

        session.start(offer)
        await waitUntilDone(session)

        #expect(progress.events == ["start", "1.0", "finish"])
        #expect(bridge.applied.count == 3)
    }

    @available(iOS 16, macOS 13, *)
    @Test("the batch character limit is read when a translation starts", .timeLimit(.minutes(1)))
    func readsBatchCharacterLimitAtStart() async {
        bridge.units = units(visible: [])
        var limit = 2
        let session = makeSession(characterLimit: { limit })
        limit = 100

        session.start(offer)
        await waitUntilDone(session)

        #expect(bridge.applied.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("cancel stops before the next apply and leaves the progress bar to the navigation", .timeLimit(.minutes(1)))
    func cancelDoesNotFinishProgress() async {
        bridge.units = units(visible: [5])
        translator.suspends = true
        let session = makeSession(characterLimit: { 2 })

        session.start(offer)
        while !translator.isSuspended {
            await Task.yield()
        }
        session.cancel()
        translator.resume()
        await waitUntilDone(session)

        #expect(translator.calls.count == 1)
        #expect(bridge.applied.isEmpty)
        #expect(progress.events == ["start"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("an apply that returns after a cancel moves no bar", .timeLimit(.minutes(1)))
    func applyAfterCancelReportsNothing() async {
        bridge.units = units(visible: [5])
        bridge.suspendsApply = true
        let session = makeSession(characterLimit: { 2 })

        session.start(offer)
        while !bridge.isApplySuspended {
            await Task.yield()
        }
        session.cancel()
        bridge.resumeApply()
        await waitUntilDone(session)

        #expect(bridge.applied.count == 1)
        #expect(progress.events == ["start"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("a download fills the first 80% of the bar, then the visible part the rest", .timeLimit(.minutes(1)))
    func downloadThenTranslateProgress() async {
        bridge.units = units(visible: Set(1...5))
        translator.downloadProgress = [0.5, 1]
        let session = makeSession()

        session.start(offer)
        await waitUntilDone(session)

        #expect(progress.events == ["start", "0.4", "0.8", "1.0", "finish"])
        #expect(bridge.applied.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("cancelling during the download stops the session without finishing the bar", .timeLimit(.minutes(1)))
    func cancelDuringDownloadStopsTheSession() async {
        bridge.units = units(visible: [5])
        translator.downloadProgress = [0.5]
        translator.holdsDownload = true
        let session = makeSession()

        session.start(offer)
        // Stops when the time limit cancels the test, so a session that never downloads fails instead of hanging.
        while (!translator.isDownloadHeld || progress.events.count < 2) && !Task.isCancelled {
            await Task.yield()
        }
        session.cancel()
        await waitUntilDone(session)

        #expect(translator.stoppedListening)
        #expect(translator.calls.isEmpty)
        #expect(bridge.applied.isEmpty)
        #expect(progress.events == ["start", "0.4"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("a failed download ends the translation and finishes the bar", .timeLimit(.minutes(1)))
    func downloadFailureFinishesQuietly() async {
        bridge.units = units(visible: [5])
        translator.downloadProgress = [0.5]
        translator.downloadError = PageTranslatorError.notInstalled("fr-en-base")
        let session = makeSession()

        session.start(offer)
        await waitUntilDone(session)

        #expect(translator.calls.isEmpty)
        #expect(bridge.applied.isEmpty)
        #expect(progress.events == ["start", "0.4", "finish"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("a page with no units finishes at once", .timeLimit(.minutes(1)))
    func zeroUnitsFinishes() async {
        let session = makeSession()

        session.start(offer)
        await waitUntilDone(session)

        #expect(translator.calls.isEmpty)
        #expect(progress.events == ["start", "finish"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("an error ends the translation and finishes the progress bar", .timeLimit(.minutes(1)))
    func errorFinishesProgress() async {
        bridge.extractError = ExtractFailure()
        let session = makeSession()

        session.start(offer)
        await waitUntilDone(session)

        #expect(translator.calls.isEmpty)
        #expect(bridge.applied.isEmpty)
        #expect(progress.events == ["start", "finish"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("start while translating is ignored", .timeLimit(.minutes(1)))
    func startWhileTranslatingIsIgnored() async {
        bridge.units = [PageTranslationUnit(id: 1, text: "Bonjour", html: false, vp: 1)]
        translator.suspends = true
        let session = makeSession()

        session.start(offer)
        while !translator.isSuspended {
            await Task.yield()
        }
        session.start(offer)
        translator.resume()
        await waitUntilDone(session)

        #expect(translator.calls.count == 1)
        #expect(bridge.applied.count == 1)
    }
}
