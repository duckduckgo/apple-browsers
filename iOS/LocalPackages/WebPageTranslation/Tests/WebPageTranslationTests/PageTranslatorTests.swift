//
//  PageTranslatorTests.swift
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
import TranslateKit
@testable import WebPageTranslation

@Suite
struct PageTranslatorTests {

    /// Records each call and answers with `answer`, which defaults to "<input> (en)".
    final class StubEngine: TranslationEngine, @unchecked Sendable {
        var calls: [(inputs: [String], isHtml: Bool)] = []
        var answer: ([String], Bool) -> [String] = { inputs, _ in inputs.map { "\($0) (en)" } }

        func translate(_ inputs: [String], isHtml: Bool) throws -> [String] {
            calls.append((inputs, isHtml))
            return answer(inputs, isHtml)
        }
    }

    final class Loads: @unchecked Sendable {
        var specs: [ModelSpec] = []
    }

    struct FakeModelsProvider: TranslationModelsProviding {
        let installed: Set<String>
        var installs = StubInstalls()
        var downloading: Set<String> = []

        func installedPair(_ pairID: String) -> (pair: TranslationManifest.Pair, folder: URL)? {
            guard installed.contains(pairID) else { return nil }
            let languages = pairID.split(separator: "-").map(String.init)
            return (PageTranslatorTests.pair(from: languages[0], to: languages[1]), URL(fileURLWithPath: "/models/\(pairID)"))
        }

        func install(_ pairID: String) -> AsyncThrowingStream<Double, Error> {
            installs.start()
        }

        func isDownloading(_ pairID: String) async -> Bool {
            downloading.contains(pairID)
        }
    }


    private let engine = StubEngine()
    private let loads = Loads()

    private let installs = StubInstalls()

    private func makeTranslator(installed: Set<String> = ["fr-en", "de-en"]) -> PageTranslator {
        let engine = engine
        let loads = loads
        return PageTranslator(modelsProvider: FakeModelsProvider(installed: installed, installs: installs),
                              loadEngine: { spec in
                                  loads.specs.append(spec)
                                  return engine
                              })
    }

    static func pair(from source: String, to target: String) -> TranslationManifest.Pair {
        let file = { (path: String) in TranslationManifest.File(path: path, bytes: 0, sha256: "", decompressedSize: 0, decompressedHash: "") }
        return TranslationManifest.Pair(sourceLanguage: source, targetLanguage: target, version: "1.0", totalBytes: 0,
                                        files: ["model": file("model.bin"), "vocab": file("vocab.spm"), "lexicalShortlist": file("lex.bin")])
    }

    private static func unit(_ id: Int, _ text: String, html: Bool = false) -> PageTranslationUnit {
        PageTranslationUnit(id: id, text: text, html: html, vp: 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("plain and HTML units are translated in separate calls and come back as text and tree", .timeLimit(.minutes(1)))
    func translatesPlainAndHtmlSeparately() async throws {
        let updates = try await makeTranslator().translate([Self.unit(1, "Bonjour"), Self.unit(2, "<b>Salut</b>", html: true), Self.unit(3, "Merci")],
                                                           pairID: "fr-en")

        #expect(engine.calls.map(\.inputs) == [["Bonjour", "Merci"], ["<b>Salut</b>"]])
        #expect(engine.calls.map(\.isHtml) == [false, true])
        #expect(updates == [PageTranslationUpdate(id: 1, text: "Bonjour (en)"),
                            PageTranslationUpdate(id: 3, text: "Merci (en)"),
                            PageTranslationUpdate(id: 2, tree: "<b>Salut</b> (en)")])
        #expect(loads.specs.map(\.modelPath) == ["/models/fr-en/model.bin"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("an HTML unit whose tree comes back null (malformed HTML) is skipped", .timeLimit(.minutes(1)))
    func skipsNullTrees() async throws {
        engine.answer = { inputs, _ in inputs.map { $0 == "<b>broken" ? "null" : "tree" } }

        let updates = try await makeTranslator().translate([Self.unit(1, "<b>broken", html: true), Self.unit(2, "<i>ok</i>", html: true)],
                                                           pairID: "fr-en")

        #expect(updates == [PageTranslationUpdate(id: 2, tree: "tree")])
    }

    @available(iOS 16, macOS 13, *)
    @Test("a result count that doesn't match the inputs throws", .timeLimit(.minutes(1)))
    func countMismatchThrows() async throws {
        engine.answer = { _, _ in ["only one"] }

        await #expect(throws: PageTranslatorError.countMismatch) {
            try await makeTranslator().translate([Self.unit(1, "Un"), Self.unit(2, "Deux")], pairID: "fr-en")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("a pair that isn't installed throws and loads nothing", .timeLimit(.minutes(1)))
    func notInstalledThrows() async throws {
        await #expect(throws: PageTranslatorError.notInstalled("es-en")) {
            try await makeTranslator().translate([Self.unit(1, "Hola")], pairID: "es-en")
        }
        #expect(loads.specs.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("the loaded model is reused for the same pair and replaced for another", .timeLimit(.minutes(1)))
    func reusesLoadedEngineForSamePair() async throws {
        let translator = makeTranslator()

        _ = try await translator.translate([Self.unit(1, "Bonjour")], pairID: "fr-en")
        _ = try await translator.translate([Self.unit(2, "Merci")], pairID: "fr-en")
        #expect(loads.specs.count == 1)

        _ = try await translator.translate([Self.unit(3, "Danke")], pairID: "de-en")
        #expect(loads.specs.map(\.sourceLang) == ["fr", "de"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("an installed pair is ready at once, without a download", .timeLimit(.minutes(1)))
    func installedPairYieldsOneImmediately() async {
        let listener = ProgressListener()
        await listener.listen(to: makeTranslator().prepare("fr-en")).value

        #expect(listener.fractions == [1])
        #expect(installs.count == 0)
        #expect(makeTranslator().isInstalled("fr-en"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("only a pair that's neither installed nor downloading needs a download", .timeLimit(.minutes(1)))
    func needsDownloadOnlyWhenMissingAndNotDownloading() async {
        let translator = PageTranslator(modelsProvider: FakeModelsProvider(installed: ["fr-en"], downloading: ["es-en"]))

        #expect(await !translator.needsDownload("fr-en"))
        #expect(await !translator.needsDownload("es-en"))
        #expect(await translator.needsDownload("de-en"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("a missing pair is installed, with its download's progress", .timeLimit(.minutes(1)))
    func downloadsWhenMissing() async {
        let translator = makeTranslator(installed: [])
        let listener = ProgressListener()
        let listening = listener.listen(to: translator.prepare("es-en"))
        await waitUntil { installs.count == 1 }

        installs.send(0.5)
        installs.send(1)
        installs.finish()
        await listening.value

        #expect(listener.fractions == [0.5, 1])
        #expect(!translator.isInstalled("es-en"))
    }
}
