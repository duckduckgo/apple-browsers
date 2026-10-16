//
//  LocalAIModelStore.swift
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

import Combine
import Foundation

public enum LocalModelState: Equatable {
    case notDownloaded
    case downloading(fraction: Double, receivedBytes: Int64, totalBytes: Int64)
    case downloaded(bytes: Int64)
    case failed(String)
}

/// Downloads models from Hugging Face into Application Support (excluded from backup), one at a time.
///
/// Files land in `<id>.partial/` and the folder is renamed once every file is in, so a model folder
/// that exists is complete. The same code would fetch from a DDG-hosted mirror by changing `baseURL`.
@MainActor
public final class LocalAIModelStore: ObservableObject {

    @Published public private(set) var states: [String: LocalModelState] = [:]
    @Published public var selectedModelID: String {
        didSet { defaults.set(selectedModelID, forKey: Self.selectedModelKey) }
    }

    public var selectedModel: LocalAIModel {
        LocalAIModelCatalog.model(withID: selectedModelID) ?? LocalAIModelCatalog.qwen35
    }

    private let rootDirectory: URL
    private let baseURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private var downloadTask: Task<Void, Never>?

    static let selectedModelKey = "localAI.selectedModelID"
    /// Only what `MLXLLM` loads: weights, configs, tokenizer and chat template.
    static let downloadedFileSuffixes = [".safetensors", ".json", ".jinja"]

    public init(rootDirectory: URL = LocalAIModelStore.defaultRootDirectory,
                baseURL: URL = URL(string: "https://huggingface.co")!,
                session: URLSession = .shared,
                defaults: UserDefaults = .standard,
                physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        self.rootDirectory = rootDirectory
        self.baseURL = baseURL
        self.session = session
        self.defaults = defaults
        self.selectedModelID = defaults.string(forKey: Self.selectedModelKey)
            ?? LocalAIModelCatalog.recommended(physicalMemory: physicalMemory).id
        refreshStates()
    }

    public nonisolated static var defaultRootDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalAIModels", isDirectory: true)
    }

    public func state(of model: LocalAIModel) -> LocalModelState {
        states[model.id] ?? .notDownloaded
    }

    /// The folder of a fully downloaded model, or `nil`.
    public func directory(for model: LocalAIModel) -> URL? {
        let directory = finalDirectory(for: model)
        return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
    }

    public var isDownloading: Bool { downloadTask != nil }

    public func download(_ model: LocalAIModel) {
        guard downloadTask == nil else { return }
        states[model.id] = .downloading(fraction: 0, receivedBytes: 0, totalBytes: model.approximateBytes)
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performDownload(of: model)
                self.states[model.id] = .downloaded(bytes: Self.size(of: self.finalDirectory(for: model)))
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: self.partialDirectory(for: model))
                self.states[model.id] = .notDownloaded
            } catch {
                try? FileManager.default.removeItem(at: self.partialDirectory(for: model))
                self.states[model.id] = .failed(error.localizedDescription)
            }
            self.downloadTask = nil
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
    }

    public func delete(_ model: LocalAIModel) {
        try? FileManager.default.removeItem(at: finalDirectory(for: model))
        try? FileManager.default.removeItem(at: partialDirectory(for: model))
        states[model.id] = .notDownloaded
    }

    // MARK: - Download

    private struct RepoFile: Decodable {
        let rfilename: String
        let size: Int64?
    }

    private struct RepoInfo: Decodable {
        let siblings: [RepoFile]
    }

    private func performDownload(of model: LocalAIModel) async throws {
        let files = try await listFiles(of: model)
        let total = files.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        let partial = partialDirectory(for: model)
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)

        var completedBytes: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let remote = baseURL.appendingPathComponent(model.id).appendingPathComponent("resolve/main").appendingPathComponent(file.rfilename)
            let alreadyReceived = completedBytes
            let destination = partial.appendingPathComponent(file.rfilename)
            try await FileDownload.run(from: remote, to: destination, configuration: session.configuration) { [weak self] written in
                Task { @MainActor in
                    let received = alreadyReceived + written
                    self?.states[model.id] = .downloading(fraction: total > 0 ? Double(received) / Double(total) : 0,
                                                          receivedBytes: received, totalBytes: total)
                }
            }
            completedBytes += file.size ?? 0
        }

        try Task.checkCancellation()
        let final = finalDirectory(for: model)
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: partial, to: final)
        try excludeFromBackup(rootDirectory)
    }

    private func listFiles(of model: LocalAIModel) async throws -> [RepoFile] {
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
    private final class FileDownload: NSObject, URLSessionDownloadDelegate {
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

    // MARK: - Disk

    private func refreshStates() {
        for model in LocalAIModelCatalog.all {
            if let directory = directory(for: model) {
                states[model.id] = .downloaded(bytes: Self.size(of: directory))
            } else {
                states[model.id] = .notDownloaded
            }
        }
    }

    private func finalDirectory(for model: LocalAIModel) -> URL {
        rootDirectory.appendingPathComponent(Self.folderName(for: model), isDirectory: true)
    }

    private func partialDirectory(for model: LocalAIModel) -> URL {
        rootDirectory.appendingPathComponent(Self.folderName(for: model) + ".partial", isDirectory: true)
    }

    static func folderName(for model: LocalAIModel) -> String {
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
