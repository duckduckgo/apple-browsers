//
//  TranslationManifest.swift
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

import DDGError
import Foundation
import LocalModels
import TranslateKit

/// The list of translation models the server offers, one entry per language pair.
public struct TranslationManifest: Decodable, Equatable, Sendable {

    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let baseUrl: URL
    /// Keyed by "<source>-<target>", e.g. "fr-en".
    public let models: [String: Pair]

    public struct Pair: Decodable, Equatable, Sendable {
        public let sourceLanguage: String
        public let targetLanguage: String
        public let version: String
        public let totalBytes: Int64
        /// Keyed by role ("model", "vocab", ...). Roles aren't modelled, so new ones come along unchanged.
        public let files: [String: File]
    }

    public struct File: Decodable, Equatable, Sendable {
        public let path: String
        public let bytes: Int64
        public let sha256: String
        public let decompressedSize: Int64
        public let decompressedHash: String
    }

    public static func decode(_ data: Data) throws -> TranslationManifest {
        let manifest = try JSONDecoder().decode(TranslationManifest.self, from: data)
        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw TranslationManifestError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        return manifest
    }

    /// The pair's files as a ModelStore bundle. Each file is named after the last component of its path, without `.zst`.
    public func bundle(for pairID: String) -> ModelBundle? {
        guard let pair = models[pairID] else {
            return nil
        }

        let files = pair.files.values
            .map { file in
                ModelFile(name: Self.name(of: file.path),
                          url: baseUrl.appendingPathComponent(file.path),
                          size: file.bytes,
                          sha256: file.sha256)
            }
            .sorted { $0.name < $1.name }
        return ModelBundle(id: pairID, version: pair.version, files: files)
    }

    static func name(of path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.hasSuffix(".zst") ? String(name.dropLast(4)) : name
    }
}

extension TranslationManifest.Pair {

    /// Keys of `files`, named for how TranslateKit uses each file.
    enum FileRole {
        static let model = "model"
        /// One vocabulary for both languages; pairs without it have `sourceVocab` and `targetVocab`.
        static let vocab = "vocab"
        static let sourceVocab = "srcVocab"
        static let targetVocab = "trgVocab"
        static let lexicalShortlist = "lexicalShortlist"
    }

    /// The files of this pair installed in `folder`, as TranslateKit loads them.
    public func modelSpec(in folder: URL) throws -> ModelSpec {
        ModelSpec(sourceLang: sourceLanguage,
                  targetLang: targetLanguage,
                  modelPath: try installedPath(of: FileRole.model, in: folder),
                  vocabPaths: try vocabPaths(in: folder),
                  shortlistPath: try installedPath(of: FileRole.lexicalShortlist, in: folder))
    }

    /// The shared vocabulary, or the source's then the target's.
    private func vocabPaths(in folder: URL) throws -> [String] {
        if files[FileRole.vocab] != nil {
            return [try installedPath(of: FileRole.vocab, in: folder)]
        }
        return [try installedPath(of: FileRole.sourceVocab, in: folder),
                try installedPath(of: FileRole.targetVocab, in: folder)]
    }

    private func installedPath(of role: String, in folder: URL) throws -> String {
        guard let file = files[role] else { throw PageTranslatorError.missingFile(role) }
        return folder.appendingPathComponent(TranslationManifest.name(of: file.path)).path
    }
}

public enum TranslationManifestError: DDGError {
    case unsupportedSchemaVersion(Int)

    public static var errorDomain: String { "com.duckduckgo.webPageTranslation.TranslationManifestError" }

    public var errorCode: Int {
        switch self {
        case .unsupportedSchemaVersion: return 1
        }
    }

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let version): return "Manifest schema version \(version) isn't supported"
        }
    }
}
