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

        func extract() async throws -> (units: [PageTranslationUnit], documentID: UUID) {
            if let extractError { throw extractError }
            return (units, documentID)
        }

        func apply(_ updates: [PageTranslationUpdate], from source: String, to target: String, in documentID: UUID) async throws -> Int {
            applied.append((updates, source, target, documentID))
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
    }

    private struct ExtractFailure: Error {}

    private let bridge = FakeBridge()
    private let translator = FakeTranslator()
    private let offer = TranslationOffer(source: "fr", target: "en", pairID: "fr-en-base")

    private func makeSession() -> PageTranslationSession {
        PageTranslationSession(bridge: bridge, translator: translator)
    }

    private func waitUntilDone(_ session: PageTranslationSession) async {
        while session.isTranslating {
            await Task.yield()
        }
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

        #expect(translator.calls.map(\.pairID) == ["fr-en-base"])
        #expect(bridge.applied.count == 1)
        #expect(bridge.applied.first?.updates == [PageTranslationUpdate(id: 1, text: "Bonjour (en)"),
                                                 PageTranslationUpdate(id: 2, text: "Merci (en)")])
        #expect(bridge.applied.first?.source == "fr")
        #expect(bridge.applied.first?.target == "en")
        #expect(bridge.applied.first?.documentID == bridge.documentID)
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

    @available(iOS 16, macOS 13, *)
    @Test("errors end the translation quietly", .timeLimit(.minutes(1)))
    func errorsEndQuietly() async {
        bridge.extractError = ExtractFailure()
        let session = makeSession()

        session.start(offer)
        await waitUntilDone(session)

        #expect(!session.isTranslating)
        #expect(translator.calls.isEmpty)
        #expect(bridge.applied.isEmpty)
    }
}
