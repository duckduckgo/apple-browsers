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


import DDGError
import Foundation
import LocalModels
import os.log
import Persistence
import TranslateKit

public enum TranslationModelsError: DDGError {
    case unknownPair(String)
    case unknownFile(String)
    case decompressedSizeMismatch(file: String)
    case decompressedHashMismatch(file: String)
    case manifestUnavailable

    public static var errorDomain: String { "com.duckduckgo.webPageTranslation.TranslationModelsError" }

    public var errorCode: Int {
        switch self {
        case .unknownPair: return 1
        case .unknownFile: return 2
        case .decompressedSizeMismatch: return 3
        case .decompressedHashMismatch: return 4
        case .manifestUnavailable: return 5
        }
    }

    public var description: String {
        switch self {
        case .unknownPair(let pairID): return "The manifest doesn't list \(pairID)"
        case .unknownFile(let name): return "The manifest has no entry for \(name)"
        case .decompressedSizeMismatch(let file): return "Decompressed \(file) has the wrong size"
        case .decompressedHashMismatch(let file): return "Decompressed \(file) doesn't match its sha256"
        case .manifestUnavailable: return "No translation manifest has been fetched yet"
        }
    }
}

/// The translation models on this device: which pairs the server offers, and installing and removing them.
public final class TranslationModels: TranslationModelsProviding, @unchecked Sendable {

    private let store: ModelStore
    private let manifestStore: TranslationManifestStore
    private let downloads = SharedDownloads()

    /// `directory` holds one folder per installed pair.
    public init(directory: URL,
                keyValueStore: ThrowingKeyValueStoring,
                session: URLSession = .localModels()) throws {
        store = try ModelStore(root: directory, session: session)
        manifestStore = TranslationManifestStore(keyValueStore: keyValueStore, session: session)
    }

    /// The newest manifest fetched since launch, else the saved one. When there's neither, fetches one in the background.
    public var manifest: TranslationManifest? {
        guard let manifest = manifestStore.cached else {
            Task { await refreshManifest() }
            return nil
        }

        return manifest
    }

    /// Fetches the manifest, then deletes installed pairs it no longer lists. Without a manifest, nothing is deleted.
    public func refreshManifest() async {
        guard let manifest = await manifestStore.refresh() else {
            return
        }

        for bundle in store.installed() where manifest.models[bundle.id] == nil {
            do {
                try store.delete(bundle.id)
            } catch {
                Logger.webPageTranslation.error("Deleting translation pair \(bundle.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Installs a pair the manifest lists, reporting progress from 0 to 1. Every caller, a tab or settings, shares one
    /// download per pair, and a caller that stops listening leaves it running.
    public func install(_ pairID: String) -> AsyncThrowingStream<Double, Error> {
        guard let manifest else {
            return AsyncThrowingStream { $0.finish(throwing: TranslationModelsError.manifestUnavailable) }
        }
        guard let pair = manifest.models[pairID], let bundle = manifest.bundle(for: pairID) else {
            return AsyncThrowingStream { $0.finish(throwing: TranslationModelsError.unknownPair(pairID)) }
        }

        let store = store
        return downloads.download(pairID) { store.install(bundle, policy: Self.decompressingPolicy(for: pair)) }
    }

    public func isDownloading(_ pairID: String) async -> Bool {
        await downloads.isRunning(pairID)
    }

    public func installed() -> [InstalledBundle] {
        store.installed()
    }

    public func delete(_ pairID: String) throws {
        try store.delete(pairID)
    }

    /// Looks the pair up in the cached manifest and the installed models.
    public func installedPair(_ pairID: String) -> (pair: TranslationManifest.Pair, folder: URL)? {
        guard let pair = manifest?.models[pairID],
              let installed = installed().first(where: { $0.id == pairID }) else {
            return nil
        }
        return (pair, installed.folder)
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
