//
//  BergamotModelProvider.swift
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

import CryptoKit
import Foundation
import os.log
import TranslateKit

// MARK: - Constants

private enum CDN {
    static let base = "https://firefox-settings-attachments.cdn.mozilla.net/"

    /// Mozilla Remote Settings "translations-models" production (base) models, keyed "<source>-<target>".
    /// Each direction is an independent model — per-direction registry versions differ, which doesn't
    /// matter at runtime. es⇄en are pinned to the versions verified on-device; ar/it/pl/pt added from
    /// the registry (X→en at v2.0/2.2, en→X at v2.1/2.2). All pairs are X⇄en only.
    static let files: [String: (model: String, vocab: String, lex: String)] = [
        "es-en": (base + "main-workspace/translations-models/d7256ea9-7731-4f15-866c-62998eef93b9.bin",
                  base + "main-workspace/translations-models/8695cc3d-7897-4c29-808b-bc983a93d1cd.spm",
                  base + "main-workspace/translations-models/a55a9cf2-8a8c-4942-a528-91e93d081746.bin"),
        "en-es": (base + "main-workspace/translations-models/2ec4ee9d-37e3-4dfc-abc9-5cd509926e88.bin",
                  base + "main-workspace/translations-models/5ac5c966-d9b3-4e89-a972-4c23e82e7157.spm",
                  base + "main-workspace/translations-models/93e99ce1-57ff-4a7f-a5db-43f106d44b7a.bin"),
        "ar-en": (base + "main-workspace/translations-models/d66f948a-452f-45d4-adc1-e9cb9acb8766.bin",
                  base + "main-workspace/translations-models/2dc6ab68-1f3e-4149-9c7c-d3dc1e6f70c3.spm",
                  base + "main-workspace/translations-models/856e509e-56c6-4b05-ab20-acd66650eaf0.bin"),
        "en-ar": (base + "main-workspace/translations-models/e282aa49-a77e-466e-b1b7-f98f34a9ea58.bin",
                  base + "main-workspace/translations-models/793d9667-7929-4375-855d-96bbed2f113d.spm",
                  base + "main-workspace/translations-models/d821aec4-485b-4747-b643-6e63cda5117d.bin"),
        "it-en": (base + "main-workspace/translations-models/a6e3de84-6612-4546-a4ef-b658ee23ca08.bin",
                  base + "main-workspace/translations-models/51b5a437-9daa-481e-a9bc-311f2b3f490c.spm",
                  base + "main-workspace/translations-models/122ac310-0f7b-40d5-b49d-bcee81077c85.bin"),
        "en-it": (base + "main-workspace/translations-models/29ae0d70-5e37-49e8-8da6-3e2c58da61d1.bin",
                  base + "main-workspace/translations-models/d9d5ffa9-b919-4491-9ab6-3dec34459768.spm",
                  base + "main-workspace/translations-models/3730ff60-2291-4c87-888d-2dc4593b20db.bin"),
        "pl-en": (base + "main-workspace/translations-models/dd8a7ab8-b12f-4ad4-8827-0922510df232.bin",
                  base + "main-workspace/translations-models/47b0f4cd-7d3c-4cf5-b7b4-0aecfbdc51f6.spm",
                  base + "main-workspace/translations-models/9a072be8-d900-4062-a2ab-c53c8eb8e619.bin"),
        "en-pl": (base + "main-workspace/translations-models/640bd7ef-a977-417f-903c-00b5217cb7de.bin",
                  base + "main-workspace/translations-models/dd8a3019-bd2f-405e-b95d-0cce7a29be2d.spm",
                  base + "main-workspace/translations-models/12451e17-4901-4327-b78d-903e9ff7529d.bin"),
        "pt-en": (base + "main-workspace/translations-models/6a2cb71f-cf08-431a-a4a2-22e450750408.bin",
                  base + "main-workspace/translations-models/9f79e7dc-18ca-4ee7-ad79-2935e46b7d9a.spm",
                  base + "main-workspace/translations-models/3a6531f9-2ab9-4164-852e-29d5242ceeaa.bin"),
        "en-pt": (base + "main-workspace/translations-models/357d1004-e004-4f93-bbb5-b6b90641e9b4.bin",
                  base + "main-workspace/translations-models/e5688e52-a5c1-458b-9dbb-459fdcec0b7d.spm",
                  base + "main-workspace/translations-models/c4192576-e76a-4edc-9346-1f90af10f6ae.bin"),
    ]
}

/// DuckDuckGo-hosted es→en model (zstd-compressed). Each file: URL, SHA-256 of the .zst, SHA-256 once decompressed.
// shortcut: one pair hardcoded from models.json (2026-11-02) to validate the hosted + zstd flow; read the manifest before shipping.
private enum Hosted {
    static let base = "https://translations.duck.com/translations/models/es-en/3.0/base-memory/"
    static let pair = "es-en"
    static let model = (url: base + "model.esen.intgemm.alphas.bin.zst",
                        sha256: "7d1a512f3d3c420a0d87e52dccf6c83bf7eba7f4c54608824d3f86b757993a3e",
                        decompressedSHA256: "4aed7734152ae0045d1a69ae49c86cfda18f53c61f90e95e1d1de1c7c7c3b033")
    static let vocab = (url: base + "vocab.esen.spm.zst",
                        sha256: "76b9ef220b22cec379f097852ca6312cabf065d5ddfb05149d5af31aa050ec22",
                        decompressedSHA256: "5ae254fa9b15aa182e70fd2a6186b1333c63a29a48043a9224c6aa4fcac058ad")
    static let lex = (url: base + "lex.50.50.esen.s2t.bin.zst",
                      sha256: "5c3aae52d8fddeb2e09098171cdecf059ea453474633edcebc77375b04cbcaee",
                      decompressedSHA256: "e2610211d3b9577d012638fe7e7e74ed7b4b708ce96b9e792e67c282a6492daa")
}

private let providerLogger = Logger(subsystem: "com.duckduckgo.ios", category: "WebPageTranslationPOC")

// MARK: - Error

enum BergamotModelProviderError: Error {
    case unsupportedLanguagePair(source: String, target: String)
    case httpError(statusCode: Int)
    case writeFailure(Error)
    case hashMismatch(file: String)
}

// MARK: - BergamotModelProvider

/// Downloads and caches the Bergamot translation model set for the supported X⇄en directions
/// (es/ar/it/pl/pt ⇄ en).
///
/// Spike-level: no resume, no checksum, no retry.
final class BergamotModelProvider {

    // MARK: - Supported directions

    /// True if we have a model for this exact direction (all supported pairs are X⇄en).
    static func supports(source: String, target: String) -> Bool {
        CDN.files["\(source)-\(target)"] != nil
    }

    /// The non-English languages we have models for (sorted; for user-facing messages).
    static var supportedNonEnglishLanguages: [String] {
        Array(Set(CDN.files.keys.flatMap { $0.split(separator: "-").map(String.init) }).subtracting(["en"])).sorted()
    }

    // MARK: - Types

    struct DownloadResult {
        let model: ModelSpec
        let bytes: Int64
        let seconds: Double
    }

    private struct RemoteFiles {
        let modelURL: URL
        let vocabURL: URL
        let lexURL: URL
    }

    // MARK: - Initialisation

    private let session: URLSession
    private let fileManager: FileManager
    private let rootDirectory: URL

    /// - Parameter rootDirectory: Overrides the default `Application Support/TranslateKit` cache
    ///   root. Pass a temp directory in tests for hermetic execution.
    init(session: URLSession = .shared,
         fileManager: FileManager = .default,
         rootDirectory: URL? = nil) {
        self.session = session
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? Self.defaultRoot()
    }

    // MARK: - Public API

    /// Returns a cached `ModelSpec` if all three files exist on disk; `nil` otherwise.
    ///
    /// // ponytail: existence-only cache check; add checksum if a model ships corrupt
    func cachedModel(source: String, target: String) -> ModelSpec? {
        let pair = source + target
        let dir = cacheDir(source: source, target: target)
        let paths = stableFilePaths(in: dir, pair: pair)
        guard fileManager.fileExists(atPath: paths.model),
              fileManager.fileExists(atPath: paths.vocab),
              fileManager.fileExists(atPath: paths.lex) else {
            return nil
        }
        return makeModelSpec(source: source, target: target, paths: paths)
    }

    /// Returns a cached model if available; otherwise downloads all three files, caches them,
    /// and returns the result. Times the full transfer with a monotonic clock and sums byte counts.
    func modelForDirection(source: String, target: String) async throws -> DownloadResult {
        if let cached = cachedModel(source: source, target: target) {
            let bytes = onDiskBytes(source: source, target: target)
            return DownloadResult(model: cached, bytes: bytes, seconds: 0)
        }

        let dir = cacheDir(source: source, target: target)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let pair = source + target
        let paths = stableFilePaths(in: dir, pair: pair)

        let start = ProcessInfo.processInfo.systemUptime
        var totalBytes: Int64 = 0

        if "\(source)-\(target)" == Hosted.pair {
            totalBytes = try await downloadHosted(to: paths)
        } else {
            let remote = try remoteFiles(source: source, target: target)
            totalBytes += try await download(url: remote.modelURL, to: paths.model)
            totalBytes += try await download(url: remote.vocabURL, to: paths.vocab)
            totalBytes += try await download(url: remote.lexURL, to: paths.lex)
        }

        let seconds = ProcessInfo.processInfo.systemUptime - start

        let spec = makeModelSpec(source: source, target: target, paths: paths)
        return DownloadResult(model: spec, bytes: totalBytes, seconds: seconds)
    }

    // MARK: - Private

    private func remoteFiles(source: String, target: String) throws -> RemoteFiles {
        guard let f = CDN.files["\(source)-\(target)"] else {
            throw BergamotModelProviderError.unsupportedLanguagePair(source: source, target: target)
        }
        return RemoteFiles(modelURL: URL(string: f.model)!, vocabURL: URL(string: f.vocab)!, lexURL: URL(string: f.lex)!)
    }

    /// Downloads `url` to a temp file via `URLSession.download(from:)` (streams to disk, avoids
    /// materialising the full ~37 MB payload in memory), then moves it to `localPath`.
    /// Returns the on-disk byte count of the saved file.
    private func download(url: URL, to localPath: String) async throws -> Int64 {
        let (tempURL, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw BergamotModelProviderError.httpError(statusCode: http.statusCode)
        }
        let destination = URL(fileURLWithPath: localPath)
        do {
            // Remove stale file if present so moveItem doesn't fail.
            if fileManager.fileExists(atPath: localPath) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: tempURL, to: destination)
        } catch {
            throw BergamotModelProviderError.writeFailure(error)
        }
        // Prefer actual on-disk size over response.expectedContentLength (can be -1).
        let size = (try? fileManager.attributesOfItem(atPath: localPath)[.size] as? Int64) ?? 0
        return size
    }

    /// Downloads each hosted `.zst`, checks its SHA-256, decompresses it with TranslateKit, checks the
    /// decompressed SHA-256, then deletes the `.zst`. Returns the compressed bytes transferred.
    private func downloadHosted(to paths: LocalPaths) async throws -> Int64 {
        var totalBytes: Int64 = 0
        for (file, localPath) in [(Hosted.model, paths.model), (Hosted.vocab, paths.vocab), (Hosted.lex, paths.lex)] {
            let zstPath = localPath + ".zst"
            totalBytes += try await download(url: URL(string: file.url)!, to: zstPath)
            try verifySHA256(atPath: zstPath, expected: file.sha256)
            let start = ProcessInfo.processInfo.systemUptime
            try await Task.detached { try TranslateKit.decompressZstd(at: zstPath, to: localPath) }.value
            let seconds = ProcessInfo.processInfo.systemUptime - start
            try verifySHA256(atPath: localPath, expected: file.decompressedSHA256)
            try? fileManager.removeItem(atPath: zstPath)
            providerLogger.info("POC hosted model: \((file.url as NSString).lastPathComponent, privacy: .public) decompressed in \(String(format: "%.3f", seconds), privacy: .public)s, both hashes OK")
        }
        return totalBytes
    }

    private func verifySHA256(atPath path: String, expected: String) throws {
        // shortcut: reads the whole file (~32 MB max) into memory; stream it if models grow.
        let digest = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe))
        guard digest.map({ String(format: "%02x", $0) }).joined() == expected else {
            try? fileManager.removeItem(atPath: path)
            throw BergamotModelProviderError.hashMismatch(file: (path as NSString).lastPathComponent)
        }
    }

    private func onDiskBytes(source: String, target: String) -> Int64 {
        let pair = source + target
        let dir = cacheDir(source: source, target: target)
        let paths = stableFilePaths(in: dir, pair: pair)
        return [paths.model, paths.vocab, paths.lex].reduce(0) { total, path in
            let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            return total + size
        }
    }

    // MARK: - Path helpers

    private func cacheDir(source: String, target: String) -> URL {
        // Hosted models live apart so a cached Mozilla CDN copy of the same pair isn't reused.
        let pair = "\(source)-\(target)"
        return rootDirectory.appendingPathComponent(pair == Hosted.pair ? "hosted/\(pair)" : pair)
    }

    private struct LocalPaths {
        let model: String
        let vocab: String
        let lex: String
    }

    private func stableFilePaths(in dir: URL, pair: String) -> LocalPaths {
        LocalPaths(
            model: dir.appendingPathComponent("model.\(pair).intgemm.alphas.bin").path,
            vocab: dir.appendingPathComponent("vocab.\(pair).spm").path,
            lex: dir.appendingPathComponent("lex.\(pair).s2t.bin").path
        )
    }

    private func makeModelSpec(source: String, target: String, paths: LocalPaths) -> ModelSpec {
        ModelSpec(
            sourceLang: source,
            targetLang: target,
            modelPath: paths.model,
            vocabPaths: [paths.vocab],
            shortlistPath: paths.lex,
            configYaml: nil,
            numWorkers: 1
        )
    }

    private static func defaultRoot() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("TranslateKit")
    }
}
