//
//  TranslationManifestTests.swift
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
import LocalModels
@testable import WebPageTranslation

@Suite
struct TranslationManifestTests {

    private let fixture: Data

    init() throws {
        let url = try #require(Bundle.module.url(forResource: "models", withExtension: "json", subdirectory: "Resources"))
        fixture = try Data(contentsOf: url)
    }

    @available(iOS 16, macOS 13, *)
    @Test("decodes the manifest and ignores keys it doesn't know", .timeLimit(.minutes(1)))
    func decodesFixtureAndIgnoresUnknownKeys() throws {
        let manifest = try TranslationManifest.decode(fixture)

        #expect(manifest.models.keys.sorted() == ["en-de", "fr-en"])
        #expect(manifest.models["fr-en"]?.files.count == 3)
        #expect(manifest.models["en-de"]?.files.count == 4)
    }

    @available(iOS 16, macOS 13, *)
    @Test("a newer schema version is rejected", .timeLimit(.minutes(1)))
    func rejectsNewerSchema() throws {
        let newer = Data(#"{"schemaVersion": 2, "baseUrl": "https://models.test/", "models": {}}"#.utf8)

        #expect(throws: TranslationManifestError.unsupportedSchemaVersion(2)) { try TranslationManifest.decode(newer) }
    }

    @available(iOS 16, macOS 13, *)
    @Test("a bundle's files come from baseUrl and are named without .zst", .timeLimit(.minutes(1)))
    func bundleUsesBaseURLAndStripsZst() throws {
        let bundle = try #require(try TranslationManifest.decode(fixture).bundle(for: "fr-en"))
        let model = try #require(bundle.files.first { $0.name == "model.fren.intgemm.alphas.bin" })

        #expect(bundle.id == "fr-en")
        #expect(bundle.version == "3.0")
        #expect(bundle.files.map(\.name) == bundle.files.map(\.name).sorted())
        #expect(model.url == URL(string: "https://models.test/translations/models/fr-en/3.0/base-memory/model.fren.intgemm.alphas.bin.zst"))
        #expect(model.size == 300)
        #expect(model.sha256 == "aa")
    }

    @available(iOS 16, macOS 13, *)
    @Test("a file's name is its last path component, so it can't leave the bundle folder", .timeLimit(.minutes(1)))
    func bundleNameNeverEscapesFolder() throws {
        let json = #"""
        {"schemaVersion": 1, "baseUrl": "https://models.test/", "models": {"fr-en": {
          "sourceLanguage": "fr", "targetLanguage": "en", "version": "1", "totalBytes": 1,
          "files": {"model": {"path": "a/../../evil.bin.zst", "bytes": 1, "sha256": "aa", "decompressedSize": 1, "decompressedHash": "bb"}}}}}
        """#

        let bundle = try #require(try TranslationManifest.decode(Data(json.utf8)).bundle(for: "fr-en"))

        #expect(bundle.files.map(\.name) == ["evil.bin"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("a pair the manifest doesn't list has no bundle", .timeLimit(.minutes(1)))
    func unknownPairHasNoBundle() throws {
        #expect(try TranslationManifest.decode(fixture).bundle(for: "xx-en") == nil)
    }
}
