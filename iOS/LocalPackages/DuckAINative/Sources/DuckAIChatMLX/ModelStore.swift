//
//  ModelStore.swift
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

import DuckAIChatCore
import Foundation

public enum ModelState: Equatable, Sendable {
    case notDownloaded
    case downloading(fraction: Double, receivedBytes: Int64, totalBytes: Int64)
    case downloaded(bytes: Int64)
    case failed(String)
}

public final class ModelStore: @unchecked Sendable {
    private let rootDirectory: URL
    private let baseURL: URL
    private let session: URLSession
    private let lock = NSLock()
    private var storedStates: [String: ModelState] = [:]
    private var subscribers: [String: [UUID: AsyncStream<ProviderAvailability>.Continuation]] = [:]
    private var downloadTask: Task<Void, Error>?
    private var downloadingModelID: String?

    static let downloadedFileSuffixes = [".safetensors", ".json", ".jinja"]

    public init(rootDirectory: URL = ModelStore.defaultRootDirectory,
                baseURL: URL = URL(string: "https://huggingface.co")!, session: URLSession = .shared) {
        self.rootDirectory = rootDirectory
        self.baseURL = baseURL
        self.session = session
        for model in ModelCatalog.all {
            if let directory = directory(for: model) {
                storedStates[model.id] = .downloaded(bytes: Self.size(of: directory))
            }
        }
    }

    public static var defaultRootDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalAIModels", isDirectory: true)
    }

    public var states: [String: ModelState] { lock.withLock { storedStates } }
    public var isDownloading: Bool { lock.withLock { downloadTask != nil } }

    public func state(of model: Model) -> ModelState {
        lock.withLock { storedStates[model.id] ?? .notDownloaded }
    }

    public func availability(for model: Model) -> ProviderAvailability {
        Self.availability(for: state(of: model), model: model)
    }

    private static func availability(for state: ModelState, model: Model) -> ProviderAvailability {
        switch state {
        case .downloaded: return .ready
        case .downloading(let fraction, _, _): return .downloading(fraction: fraction)
        case .notDownloaded, .failed: return .needsDownload(bytes: model.approximateBytes)
        }
    }

    public func availabilityUpdates(for model: Model) -> AsyncStream<ProviderAvailability> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { subscribers[model.id, default: [:]][id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.subscribers[model.id]?[id] = nil }
            }
        }
    }

    public func directory(for model: Model) -> URL? {
        let directory = finalDirectory(for: model)
        return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
    }

    public func download(_ model: Model) async throws {
        while true {
            let (task, sameModel) = lock.withLock { () -> (Task<Void, Error>, Bool) in
                if let downloadTask { return (downloadTask, downloadingModelID == model.id) }
                let task = Task { try await self.runDownload(model) }
                downloadTask = task
                downloadingModelID = model.id
                return (task, true)
            }
            if sameModel {
                try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                }
                return
            }
            _ = try? await task.value
            try Task.checkCancellation()
        }
    }

    private func runDownload(_ model: Model) async throws {
        defer {
            lock.withLock {
                downloadTask = nil
                downloadingModelID = nil
            }
        }
        guard directory(for: model) == nil else { return }
        update(.downloading(fraction: 0, receivedBytes: 0, totalBytes: model.approximateBytes), for: model)
        do {
            try await performDownload(of: model)
            update(.downloaded(bytes: Self.size(of: finalDirectory(for: model))), for: model)
        } catch {
            try? FileManager.default.removeItem(at: partialDirectory(for: model))
            update(error is CancellationError ? .notDownloaded : .failed(error.localizedDescription), for: model)
            throw error
        }
    }

    public func cancelDownload() {
        lock.withLock { downloadTask?.cancel() }
    }

    public func delete(_ model: Model) async {
        let task = lock.withLock { downloadingModelID == model.id ? downloadTask : nil }
        task?.cancel()
        _ = try? await task?.value
        try? FileManager.default.removeItem(at: finalDirectory(for: model))
        try? FileManager.default.removeItem(at: partialDirectory(for: model))
        update(.notDownloaded, for: model)
    }

    private func update(_ state: ModelState, for model: Model) {
        lock.withLock { publish(state, for: model) }
    }

    private func updateProgress(_ state: ModelState, for model: Model) {
        lock.withLock {
            guard case .downloading = storedStates[model.id] else { return }
            publish(state, for: model)
        }
    }

    private func publish(_ state: ModelState, for model: Model) {
        storedStates[model.id] = state
        for subscriber in subscribers[model.id, default: [:]].values {
            subscriber.yield(Self.availability(for: state, model: model))
        }
    }

    private struct RepoFile: Decodable {
        let rfilename: String
        let size: Int64?
    }

    private struct RepoInfo: Decodable {
        let siblings: [RepoFile]
    }

    private func performDownload(of model: Model) async throws {
        let files = try await listFiles(of: model)
        guard !files.isEmpty else { throw URLError(.badServerResponse) }
        let total = files.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        let partial = partialDirectory(for: model)
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try excludeFromBackup(rootDirectory)

        var completedBytes: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let remote = baseURL.appendingPathComponent(model.id).appendingPathComponent("resolve/main").appendingPathComponent(file.rfilename)
            let alreadyReceived = completedBytes
            let destination = partial.appendingPathComponent(file.rfilename)
            try await FileDownload.run(from: remote, to: destination, configuration: session.configuration) { [weak self] written in
                let received = alreadyReceived + written
                self?.updateProgress(.downloading(fraction: total > 0 ? Double(received) / Double(total) : 0,
                                                  receivedBytes: received, totalBytes: total), for: model)
            }
            completedBytes += file.size ?? 0
        }

        try Task.checkCancellation()
        let final = finalDirectory(for: model)
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: partial, to: final)
    }

    private func listFiles(of model: Model) async throws -> [RepoFile] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/models").appendingPathComponent(model.id), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "blobs", value: "true")]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(RepoInfo.self, from: data).siblings
            .filter { file in Self.downloadedFileSuffixes.contains { file.rfilename.hasSuffix($0) } }
    }

    /// One file, with byte progress. The async `URLSession.download(from:delegate:)` never calls the
    /// delegate's `didWriteData`, so progress needs a delegate-backed session and a download task.
    private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let destination: URL
        private let onProgress: (Int64) -> Void
        private var continuation: CheckedContinuation<Void, Error>?
        private var moveError: Error?
        private var lastReportedBytes: Int64 = 0

        private init(destination: URL, onProgress: @escaping (Int64) -> Void) {
            self.destination = destination
            self.onProgress = onProgress
        }

        static func run(from url: URL, to destination: URL, configuration: URLSessionConfiguration,
                        onProgress: @escaping (Int64) -> Void) async throws {
            let download = FileDownload(destination: destination, onProgress: onProgress)
            let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            let task = session.downloadTask(with: url)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    download.continuation = continuation
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        }

        /// Called every few dozen KB; reporting each MB is plenty for a progress bar.
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesWritten - lastReportedBytes >= 1_000_000 || totalBytesWritten == totalBytesExpectedToWrite else { return }
            lastReportedBytes = totalBytesWritten
            onProgress(totalBytesWritten)
        }

        /// The temporary file is deleted when this returns, so it has to be moved here.
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            guard let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 else {
                moveError = URLError(.badServerResponse)
                return
            }
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                moveError = error
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error ?? moveError {
                continuation?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
            } else {
                continuation?.resume()
            }
            continuation = nil
        }
    }

    private func finalDirectory(for model: Model) -> URL {
        rootDirectory.appendingPathComponent(Self.folderName(for: model), isDirectory: true)
    }

    private func partialDirectory(for model: Model) -> URL {
        rootDirectory.appendingPathComponent(Self.folderName(for: model) + ".partial", isDirectory: true)
    }

    static func folderName(for model: Model) -> String {
        model.id.replacingOccurrences(of: "/", with: "--")
    }

    private func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    static func size(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return enumerator.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }
            .reduce(Int64(0)) { $0 + Int64($1) }
    }
}
