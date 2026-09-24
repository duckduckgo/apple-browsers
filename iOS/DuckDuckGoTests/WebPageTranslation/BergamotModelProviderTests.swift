//
//  BergamotModelProviderTests.swift
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

import XCTest
@testable import DuckDuckGo

final class BergamotModelProviderTests: XCTestCase {

    // MARK: - Helpers

    /// Create a unique empty temporary directory and return its URL.
    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("BergamotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Seed <root>/<source>-<target>/ with the three dummy model files under
    /// the stable names that BergamotModelProvider expects.
    private func seedCacheDir(root: URL, source: String, target: String) throws {
        let pair = source + target  // e.g. "esen"
        let dir = root.appendingPathComponent("\(source)-\(target)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let names = [
            "model.\(pair).intgemm.alphas.bin",
            "vocab.\(pair).spm",
            "lex.\(pair).s2t.bin",
        ]
        for name in names {
            try Data("dummy".utf8).write(to: dir.appendingPathComponent(name))
        }
    }

    // MARK: - Tests

    func test_cachedModel_returnsModelWhenFilesPresent() throws {
        let root = try makeTempDir()
        try seedCacheDir(root: root, source: "es", target: "en")

        let provider = BergamotModelProvider(rootDirectory: root)
        let model = try XCTUnwrap(provider.cachedModel(source: "es", target: "en"))

        XCTAssertEqual(model.sourceLang, "es")
        XCTAssertEqual(model.targetLang, "en")
        XCTAssertTrue(model.modelPath.hasPrefix(root.path),
                      "modelPath should be under root, got: \(model.modelPath)")
        XCTAssertEqual(model.vocabPaths.count, 1)
    }

    func test_cachedModel_nilWhenAbsent() throws {
        let root = try makeTempDir()
        // "fr-en" dir does not exist
        XCTAssertNil(BergamotModelProvider(rootDirectory: root).cachedModel(source: "fr", target: "en"))
    }

    func test_cachedModel_nilWhenOnlyPartialFilesPresent() throws {
        let root = try makeTempDir()
        // Create dir but only seed one file — should still return nil
        let dir = root.appendingPathComponent("es-en")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("dummy".utf8).write(to: dir.appendingPathComponent("model.esen.intgemm.alphas.bin"))

        XCTAssertNil(BergamotModelProvider(rootDirectory: root).cachedModel(source: "es", target: "en"))
    }

    func test_cachedModel_enEsReturnsModel() throws {
        let root = try makeTempDir()
        try seedCacheDir(root: root, source: "en", target: "es")

        let provider = BergamotModelProvider(rootDirectory: root)
        let model = try XCTUnwrap(provider.cachedModel(source: "en", target: "es"))

        XCTAssertEqual(model.sourceLang, "en")
        XCTAssertEqual(model.targetLang, "es")
        XCTAssertTrue(model.modelPath.hasPrefix(root.path))
        XCTAssertEqual(model.vocabPaths.count, 1)
    }

    func test_cachedModel_stableFilenamesUsePair() throws {
        let root = try makeTempDir()
        try seedCacheDir(root: root, source: "es", target: "en")

        let provider = BergamotModelProvider(rootDirectory: root)
        let model = try XCTUnwrap(provider.cachedModel(source: "es", target: "en"))

        XCTAssertTrue(model.modelPath.hasSuffix("model.esen.intgemm.alphas.bin"))
        XCTAssertTrue(model.vocabPaths.first?.hasSuffix("vocab.esen.spm") == true)
        XCTAssertTrue(model.shortlistPath.hasSuffix("lex.esen.s2t.bin"))
    }
}
