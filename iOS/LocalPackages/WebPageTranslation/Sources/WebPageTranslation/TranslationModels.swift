//
//  TranslationModels.swift
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
import LocalModels
import os.log
import Persistence
import TranslateKit

public enum TranslationModelsError: Error, Equatable {
    case unknownPair(String)
    case unknownFile(String)
    case decompressedSizeMismatch(file: String)
    case decompressedHashMismatch(file: String)
}

/// The translation models on this device: which pairs the server offers, and installing and removing them.
public final class TranslationModels: @unchecked Sendable {

    private let store: ModelStore
    private let manifestStore: TranslationManifestStore

    /// `directory` holds one folder per installed pair.
    public init(directory: URL,
                keyValueStore: ThrowingKeyValueStoring,
                session: URLSession = .localModels()) throws {
        store = try ModelStore(root: directory, session: session)
        manifestStore = TranslationManifestStore(keyValueStore: keyValueStore, session: session)
    }

    /// The last manifest saved on this device.
    public var manifest: TranslationManifest? {
        manifestStore.cached
    }

    /// Fetches the manifest, then deletes installed pairs it no longer lists. Without a manifest, nothing is deleted.
    public func refreshManifest() async -> TranslationManifest? {
        guard let manifest = await manifestStore.refresh() else {
            return nil
        }

        for bundle in store.installed() where manifest.models[bundle.id] == nil {
            do {
                try store.delete(bundle.id)
            } catch {
                Logger.webPageTranslation.error("Deleting translation pair \(bundle.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return manifest
    }

    /// Installs a pair the manifest lists, reporting progress from 0 to 1.
    public func install(_ pairID: String) -> AsyncThrowingStream<Double, Error> {
        guard let manifest, let pair = manifest.models[pairID], let bundle = manifest.bundle(for: pairID) else {
            return AsyncThrowingStream { $0.finish(throwing: TranslationModelsError.unknownPair(pairID)) }
        }

        return store.install(bundle, policy: Self.decompressingPolicy(for: pair))
    }

    public func installed() -> [InstalledBundle] {
        store.installed()
    }

    public func delete(_ pairID: String) throws {
        try store.delete(pairID)
    }

    /// Decompresses each downloaded `.zst` and checks the result's size and sha256 against the manifest.
    private static func decompressingPolicy(for pair: TranslationManifest.Pair) -> DownloadPolicy {
        DownloadPolicy { url, file in
            // Files are matched by the compressed hash ModelStore already checked; two files with the same hash have the same contents.
            guard let expected = pair.files.values.first(where: { $0.sha256 == file.sha256 }) else {
                throw TranslationModelsError.unknownFile(file.name)
            }

            let output = url.appendingPathExtension("out")
            try TranslateKit.decompressZstd(at: url.path, to: output.path)

            let size = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value
            guard size == expected.decompressedSize else {
                throw TranslationModelsError.decompressedSizeMismatch(file: file.name)
            }

            guard try FileHash.sha256Hex(of: output) == expected.decompressedHash.lowercased() else {
                throw TranslationModelsError.decompressedHashMismatch(file: file.name)
            }

            return output
        }
    }
}
