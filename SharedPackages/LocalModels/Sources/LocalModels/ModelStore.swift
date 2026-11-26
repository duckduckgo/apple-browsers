//
//  ModelStore.swift
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

/// Downloads, checks and stores model bundles under `root`, one folder per bundle id.
///
/// An install downloads into `root/.staging`, checks each file's size and sha256, runs the policy's `process`,
/// then moves the whole folder to `root/<id>` in one rename. A bundle is either fully installed or absent.
///
/// Use one store per `root`: a new store clears `root/.staging`, and running installs are tracked per store.
public final class ModelStore: @unchecked Sendable {

    private struct Record: Codable {
        let id: String
        let version: String
    }

    private static let recordName = "bundle.json"

    private let root: URL
    private let session: URLSession
    private let lock = NSLock()
    private var running: [String: Task<Void, Never>] = [:]

    private var staging: URL { root.appendingPathComponent(".staging") }

    public init(root: URL, session: URLSession) throws {
        self.root = root
        self.session = session
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Models don't belong in iCloud or computer backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var rootURL = root
        try rootURL.setResourceValues(values)

        // Anything left in staging is from an install the app was killed during.
        try? FileManager.default.removeItem(at: staging)
    }

    /// Installs `bundle`, reporting progress from 0 to 1. Finishes at once when it's already installed.
    public func install(_ bundle: ModelBundle, policy: DownloadPolicy = .init()) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            do {
                try Self.validateNames(of: bundle)
            } catch {
                continuation.finish(throwing: error)
                return
            }
            lock.lock()
            defer { lock.unlock() }
            // Checked under the lock, so an install of the same id can't finish between this check and the next.
            if isInstalled(bundle.id) {
                continuation.yield(1)
                continuation.finish()
                return
            }
            guard running[bundle.id] == nil else {
                continuation.finish(throwing: ModelStoreError.alreadyInstalling(bundle.id))
                return
            }
            let task = Task {
                var failure: Error?
                do {
                    try await self.performInstall(bundle, policy: policy) { continuation.yield($0) }
                } catch {
                    failure = Task.isCancelled ? CancellationError() : error
                }
                // Freed before the stream ends, so a caller that retries as soon as its loop ends isn't told it's still running.
                self.lock.withLock { _ = self.running.removeValue(forKey: bundle.id) }
                continuation.finish(throwing: failure)
            }
            running[bundle.id] = task
            continuation.onTermination = { termination in
                if case .cancelled = termination { task.cancel() }
            }
        }
    }

    public func cancel(_ id: String) {
        lock.withLock { running[id] }?.cancel()
    }

    /// Every complete bundle under `root`, sorted by id. Staging folders never hold a record, so they're skipped.
    public func installed() -> [InstalledBundle] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names
            .compactMap { name in
                let folder = folderURL(name)
                guard let data = try? Data(contentsOf: recordURL(in: folder)),
                      let record = try? JSONDecoder().decode(Record.self, from: data) else {
                    return nil
                }

                return InstalledBundle(id: record.id, version: record.version, folder: folder)
            }
            .sorted { $0.id < $1.id }
    }

    /// The folder of an installed bundle, or nil when it isn't installed.
    public func folder(for id: String) -> URL? {
        guard (try? Self.validateName(id)) != nil, isInstalled(id) else {
            return nil
        }

        return folderURL(id)
    }

    /// Cancels a running install of `id`, then deletes its folder. Does nothing when it isn't installed.
    public func delete(_ id: String) throws {
        try Self.validateName(id)
        cancel(id)
        // shortcut: an install already past its last cancellation check can still move its folder in after this; make delete wait for the install if callers ever delete one mid-install.
        guard FileManager.default.fileExists(atPath: folderURL(id).path) else {
            return
        }

        // Moved out of `root` in one rename first, so a delete cut off partway leaves only staging, which `init` clears.
        let trash = try makeStagingFolder(for: id)
        try FileManager.default.moveItem(at: folderURL(id), to: trash.appendingPathComponent(id))
        try? FileManager.default.removeItem(at: trash)
    }

    // MARK: - Paths

    private func folderURL(_ id: String) -> URL {
        root.appendingPathComponent(id)
    }

    private func recordURL(in folder: URL) -> URL {
        folder.appendingPathComponent(Self.recordName)
    }

    /// Only the final rename creates a bundle folder with a record in it, so a record means a complete install.
    private func isInstalled(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: recordURL(in: folderURL(id)).path)
    }

    /// A new, empty folder under `root/.staging`. It's on the same volume as `root`, so the final move is a rename.
    private func makeStagingFolder(for id: String) throws -> URL {
        let folder = staging.appendingPathComponent("\(id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Names become path components under `root`, so none may climb out of it or hide in a dot folder.
    private static func validateNames(of bundle: ModelBundle) throws {
        try validateName(bundle.id)
        var seen: Set<String> = []
        for name in bundle.files.map(\.name) {
            try validateName(name)
            // The store writes `bundle.json` and `<name>.download` next to the files, and each file needs its own name.
            if name == recordName || name.hasSuffix(".download") || !seen.insert(name).inserted {
                throw ModelStoreError.invalidName(name)
            }
        }
    }

    private static func validateName(_ name: String) throws {
        if name.isEmpty || name.hasPrefix(".") || name.contains("/") {
            throw ModelStoreError.invalidName(name)
        }
    }

    // MARK: - Install

    /// Installs every file into a staging folder, then moves the folder into place. On any failure the staging folder is deleted.
    private func performInstall(_ bundle: ModelBundle, policy: DownloadPolicy, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let folder = try makeStagingFolder(for: bundle.id)
        do {
            let total = bundle.totalBytes
            var completed: Int64 = 0
            for file in bundle.files {
                try Task.checkCancellation()
                let base = completed
                try await installFile(file, into: folder, policy: policy) { received in
                    onProgress(Self.fraction(base + min(received, file.size), of: total))
                }
                completed += file.size
                // The last byte count can arrive after the download ends, when DownloadBox drops it.
                onProgress(Self.fraction(completed, of: total))
            }
            try Task.checkCancellation()
            try writeRecord(for: bundle, in: folder)
            try FileManager.default.moveItem(at: folder, to: folderURL(bundle.id))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Downloads one file, checks its size and sha256, runs the policy's `process` and keeps the result as `file.name`.
    private func installFile(_ file: ModelFile,
                             into folder: URL,
                             policy: DownloadPolicy,
                             onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let downloadedFileURL = folder.appendingPathComponent(file.name + ".download")
        try await download(file, to: downloadedFileURL, onProgress: onProgress)
        try verify(downloadedFileURL, against: file)

        // `process` can turn the download into a new file (e.g. decompress it); only its result is kept.
        let processedFileURL = try policy.process(downloadedFileURL, file)
        try FileManager.default.moveItem(at: processedFileURL, to: folder.appendingPathComponent(file.name))
        if processedFileURL != downloadedFileURL {
            try? FileManager.default.removeItem(at: downloadedFileURL)
        }
    }

    /// Writes the bundle's id and version next to its files. It moves with them in the final rename,
    /// so it marks the install as complete and records which version is on disk.
    private func writeRecord(for bundle: ModelBundle, in folder: URL) throws {
        try JSONEncoder().encode(Record(id: bundle.id, version: bundle.version)).write(to: recordURL(in: folder))
    }

    private static func fraction(_ received: Int64, of total: Int64) -> Double {
        total > 0 ? Double(received) / Double(total) : 1
    }

    private func download(_ file: ModelFile, to destination: URL, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let box = DownloadBox()
        defer { box.finish() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.downloadTask(with: file.url) { location, response, error in
                    // The temporary file is deleted when this handler returns, so it's moved here.
                    continuation.resume(with: Result {
                        if let error {
                            throw error
                        }

                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        guard (200..<300).contains(status) else {
                            throw ModelStoreError.httpStatus(file: file.name, code: status)
                        }

                        guard let location else {
                            throw URLError(.cannotOpenFile)
                        }

                        try FileManager.default.moveItem(at: location, to: destination)
                    })
                }
                box.start(task, onProgress: onProgress)
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// Checks the size first: it's free, and a wrong size makes hashing the file pointless.
    private func verify(_ url: URL, against file: ModelFile) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard size == file.size else {
            throw ModelStoreError.sizeMismatch(file: file.name, expected: file.size, actual: size)
        }

        let sha256 = try FileHash.sha256Hex(of: url)
        guard sha256 == file.sha256.lowercased() else {
            throw ModelStoreError.hashMismatch(file: file.name)
        }
    }
}

/// The running download task of one file: lets cancellation reach it, and drops progress updates that arrive
/// after the download is done, so the next file's progress can't be followed by an older, lower value.
private final class DownloadBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var isCancelled = false
    private var isFinished = false

    func start(_ task: URLSessionDownloadTask, onProgress: @escaping @Sendable (Int64) -> Void) {
        lock.withLock {
            self.task = task
            observation = task.observe(\.countOfBytesReceived) { [self] task, _ in
                lock.withLock {
                    if !isFinished { onProgress(task.countOfBytesReceived) }
                }
            }
            if isCancelled { task.cancel() }
        }
        task.resume()
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            task?.cancel()
        }
    }

    func finish() {
        lock.withLock {
            isFinished = true
            observation?.invalidate()
            observation = nil
        }
    }
}
