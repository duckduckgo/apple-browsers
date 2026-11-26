//
//  AIChatLocalModelDownloader.swift
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
import CryptoKit
import DDGError
import Foundation
import Network
import os.log

/// Downloads the model file into `directory`, as `<sha256>.gguf`.
///
/// Received bytes go straight into `<sha256>.gguf.part`, so a download that stops, because the
/// app quit, the Mac slept or the network dropped, continues from there with an HTTP range
/// request. The file is renamed only once its size and SHA-256 match, so a `.gguf` file on disk
/// is always a verified one.
@MainActor
public final class AIChatLocalModelDownloader: AIChatLocalModelInstalling {

    /// Waits between attempts after a network error. Once they run out, setup fails with `network`.
    public static let defaultRetryDelays: [TimeInterval] = [5, 30, 120, 600, 1_800]

    /// Room to leave free beyond the model itself, so the download doesn't fill the disk.
    static let freeSpaceMargin: Int64 = 500_000_000

    static let installRequestKey = "aichat.localModel.installRequested"

    public let spec: AIChatLocalModelSpec
    public private(set) var state: AIChatLocalModelInstallState {
        didSet {
            if state != oldValue {
                stateSubject.send(state)
            }
        }
    }
    /// Sends after the state changes, unlike `@Published`, so a subscriber reading `state` sees the new one.
    private let stateSubject: CurrentValueSubject<AIChatLocalModelInstallState, Never>

    private let directory: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private let availableCapacity: (URL) -> Int64?
    private let retryDelays: [TimeInterval]
    private var download: ModelFileDownload?
    private var retry: Task<Void, Never>?
    /// Attempts in a row that added nothing. A connection that drops often but keeps adding bytes carries on.
    private var failedAttempts = 0
    private var receivedAtAttemptStart: Int64 = 0
    /// Hashing a finished download takes a second or two. Starting another download meanwhile would
    /// ask for bytes past the end, and the server's 416 would delete the file being checked.
    private var isVerifying = false
    private let networkAvailable: AnyPublisher<Void, Never>
    private var networkSubscription: AnyCancellable?

    /// - Parameters:
    ///   - networkAvailable: Fires when the network comes back, to retry without waiting.
    public init(spec: AIChatLocalModelSpec,
                directory: URL,
                session: URLSession = .makeLocalModelDownloads(),
                defaults: UserDefaults = .standard,
                availableCapacity: @escaping (URL) -> Int64? = AIChatLocalModelDownloader.availableCapacity(at:),
                retryDelays: [TimeInterval] = AIChatLocalModelDownloader.defaultRetryDelays,
                networkAvailable: AnyPublisher<Void, Never> = AIChatLocalModelDownloader.networkAvailablePublisher()) {
        self.spec = spec
        self.directory = directory
        self.session = session
        self.defaults = defaults
        self.availableCapacity = availableCapacity
        self.retryDelays = retryDelays
        self.networkAvailable = networkAvailable

        if let installed = Self.installedFileURL(in: directory, spec: spec) {
            state = .installed(installed)
        } else if defaults.string(forKey: Self.installRequestKey) == spec.sha256 {
            state = .downloading(receivedBytes: Self.fileSize(at: directory.appendingPathComponent(spec.fileName + ".part")) ?? 0,
                                 totalBytes: spec.bytes)
        } else {
            defaults.removeObject(forKey: Self.installRequestKey)
            state = .notInstalled
        }
        stateSubject = CurrentValueSubject(state)
        removeRetiredModelFiles()
    }

    /// Models the app used to offer by default. Their files stayed on disk after the switch until the
    /// user tapped Install or Uninstall.
    static let retiredSHA256s: Set<String> = [
        "227e78e2fb9a3e5699190be0ce0885fd2ea72a242ed1bf718c2148c45dd090b5" // Granite 4.0 1B, Q4_0
    ]

    /// Only files of retired models. Any other model may be one that remote config names again after a
    /// rollback, so it goes only when the user installs or uninstalls.
    private func removeRetiredModelFiles() {
        for sha256 in Self.retiredSHA256s where sha256 != spec.sha256 {
            for name in ["\(sha256).gguf", "\(sha256).gguf.part"] {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    public var statePublisher: AnyPublisher<AIChatLocalModelInstallState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// The verified model file, or nil when it isn't installed. Safe to call from any thread.
    public nonisolated static func installedFileURL(in directory: URL, spec: AIChatLocalModelSpec) -> URL? {
        let url = directory.appendingPathComponent(spec.fileName)
        return fileSize(at: url) == spec.bytes ? url : nil
    }

    private var partURL: URL { directory.appendingPathComponent(spec.fileName + ".part") }

    public var isActive: Bool { download != nil || isVerifying }
    private var isWaitingToRetry: Bool { retry != nil }
    private var isRequested: Bool { defaults.string(forKey: Self.installRequestKey) == spec.sha256 }

    // MARK: - AIChatLocalModelInstalling

    public func install() {
        guard !state.isInstalled, download == nil, !isWaitingToRetry, !isVerifying else { return }
        defaults.set(spec.sha256, forKey: Self.installRequestKey)
        failedAttempts = 0
        removeModelFiles(keeping: [spec.fileName, spec.fileName + ".part"])
        startDownload()
    }

    public func cancel() {
        guard !state.isInstalled else { return }
        stopDownload()
        defaults.removeObject(forKey: Self.installRequestKey)
        removeModelFiles()
        state = .notInstalled
    }

    public func uninstall() {
        stopDownload()
        defaults.removeObject(forKey: Self.installRequestKey)
        removeModelFiles()
        state = .notInstalled
    }

    public func pause() {
        stopDownload()
    }

    public func resumeIfNeeded() {
        guard isRequested, !state.isInstalled, download == nil, !isWaitingToRetry, !isVerifying else { return }
        failedAttempts = 0
        startDownload()
    }

    // MARK: - Downloading

    private func startDownload() {
        retry?.cancel()
        retry = nil
        do {
            try prepareDirectory()
        } catch {
            Logger.aiChat.error("[LocalModel] Can't create the model folder: \(error.localizedDescription, privacy: .public)")
            fail(.unknown)
            return
        }

        let received = Self.fileSize(at: partURL) ?? 0
        if received >= spec.bytes {
            // Every byte arrived, but the app quit or the move failed before the file was checked.
            // Asking for more would get a 416, which deletes the whole file.
            state = .downloading(receivedBytes: received, totalBytes: spec.bytes)
            verifyAndInstall()
            return
        }
        if let capacity = availableCapacity(directory), capacity < spec.bytes - received + Self.freeSpaceMargin {
            fail(.diskFull)
            return
        }

        state = .downloading(receivedBytes: received, totalBytes: spec.bytes)
        receivedAtAttemptStart = received
        let download = ModelFileDownload(url: spec.url, partURL: partURL, expectedBytes: spec.bytes)
        self.download = download
        download.start(in: session,
                       onProgress: { [weak self, weak download] received in
            Task { @MainActor in
                guard let self, let download, self.download === download else { return }
                self.state = .downloading(receivedBytes: received, totalBytes: self.spec.bytes)
            }
        },
                       onFinish: { [weak self, weak download] result in
            Task { @MainActor in
                guard let self, let download, self.download === download else { return }
                self.download = nil
                self.finish(result)
            }
        })
    }

    private func stopDownload() {
        retry?.cancel()
        retry = nil
        let download = self.download
        self.download = nil
        download?.cancel()
    }

    private func finish(_ result: Result<Void, ModelFileDownload.Failure>) {
        switch result {
        case .success:
            verifyAndInstall()
        case .failure(.cancelled):
            break
        case .failure(.diskFull):
            fail(.diskFull)
        case .failure(.tooLarge), .failure(.rangeNotSatisfiable):
            // The partial file can't be continued; the next attempt starts over.
            try? FileManager.default.removeItem(at: partURL)
            fail(.unknown)
        case .failure(.file):
            fail(.unknown)
        case .failure(.http(let status)) where !(500...599).contains(status):
            fail(.unknown)
        case .failure(.http), .failure(.network):
            if (Self.fileSize(at: partURL) ?? 0) > receivedAtAttemptStart {
                failedAttempts = 0
            }
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard failedAttempts < retryDelays.count else {
            fail(.network)
            return
        }
        let delay = retryDelays[failedAttempts]
        failedAttempts += 1
        // Watching the network only while a retry waits keeps the monitor off for everyone else.
        if networkSubscription == nil {
            networkSubscription = networkAvailable
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.retryNowIfWaiting() }
        }
        retry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.isWaitingToRetry else { return }
            self.retry = nil
            self.startDownload()
        }
    }

    private func retryNowIfWaiting() {
        guard isWaitingToRetry else { return }
        startDownload()
    }

    private func verifyAndInstall() {
        let partURL = partURL
        let destination = directory.appendingPathComponent(spec.fileName)
        let spec = spec
        isVerifying = true
        Task { [weak self] in
            let verified = await Task.detached(priority: .utility) {
                Self.fileSize(at: partURL) == spec.bytes && Self.sha256(of: partURL) == spec.sha256
            }.value
            guard let self else { return }
            self.isVerifying = false
            guard self.isRequested else { return }
            guard verified else {
                Logger.aiChat.error("[LocalModel] The downloaded model doesn't match its SHA-256")
                try? FileManager.default.removeItem(at: partURL)
                self.fail(.unknown)
                return
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: partURL, to: destination)
                self.defaults.removeObject(forKey: Self.installRequestKey)
                self.networkSubscription = nil
                self.state = .installed(destination)
            } catch {
                Logger.aiChat.error("[LocalModel] Can't move the model into place: \(error.localizedDescription, privacy: .public)")
                self.fail(.unknown)
            }
        }
    }

    /// Ends the attempt. What was downloaded stays, so Try Again continues from there, but the
    /// next launch doesn't retry on its own.
    private func fail(_ error: AIChatLocalModelSetupError) {
        stopDownload()
        networkSubscription = nil
        defaults.removeObject(forKey: Self.installRequestKey)
        state = .failed(error)
    }

    // MARK: - Files

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    /// Only one model is kept, and remote config can switch models, so files from an earlier one go too.
    private func removeModelFiles(keeping keep: Set<String> = []) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where (file.hasSuffix(".gguf") || file.hasSuffix(".gguf.part")) && !keep.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    nonisolated static func fileSize(at url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    nonisolated static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        // Each chunk is autoreleased. Without a pool per read, the whole file stays in memory until the end:
        // 2.7 GB for Gemma 4 E2B, which would get the app ended on iOS.
        while autoreleasepool(invoking: { () -> Bool in
            guard let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public nonisolated static func availableCapacity(at url: URL) -> Int64? {
        let existing = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        return (try? existing.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    /// Fires when the network comes back after being down. The monitor starts on subscription and
    /// stops when it's cancelled. Its first report is only the current state, so it doesn't fire.
    public nonisolated static func networkAvailablePublisher() -> AnyPublisher<Void, Never> {
        Deferred {
            let subject = PassthroughSubject<Void, Never>()
            let monitor = NWPathMonitor()
            let lastStatus = PathStatusBox()
            monitor.pathUpdateHandler = { path in
                let isSatisfied = path.status == .satisfied
                if isSatisfied, lastStatus.wasSatisfied == false {
                    subject.send()
                }
                lastStatus.wasSatisfied = isSatisfied
            }
            monitor.start(queue: DispatchQueue(label: "com.duckduckgo.aiChat.localModel.network"))
            return subject.handleEvents(receiveCancel: { monitor.cancel() })
        }
        .eraseToAnyPublisher()
    }
}

/// Only touched on the monitor's queue.
private final class PathStatusBox: @unchecked Sendable {
    var wasSatisfied: Bool?
}

public extension URLSession {
    /// No cookies or cache, and a user agent without the app or OS version, so the request says no
    /// more than that someone downloads the model. The same rules as on-device translations.
    static func makeLocalModelDownloads(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // URLSession always sends Accept-Language, which would name the user's languages. An empty
        // value is the closest to dropping it.
        configuration.httpAdditionalHeaders = ["User-Agent": "DuckDuckGo", "Accept-Language": ""]
        configuration.timeoutIntervalForRequest = 60
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return URLSession(configuration: configuration)
    }
}

/// One attempt to fetch the rest of the file. Its delegate methods run on the session's queue.
final class ModelFileDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    enum Failure: DDGError {
        case cancelled
        case network
        /// The HTTP status code.
        case http(Int)
        case rangeNotSatisfiable
        case tooLarge
        case diskFull
        case file

        static let errorDomain = "com.duckduckgo.aiChat.localModel.download"

        var errorCode: Int {
            switch self {
            case .cancelled: return 1
            case .network: return 2
            case .http: return 3
            case .rangeNotSatisfiable: return 4
            case .tooLarge: return 5
            case .diskFull: return 6
            case .file: return 7
            }
        }

        var description: String {
            switch self {
            case .cancelled: return "ModelFileDownload.Failure.cancelled"
            case .network: return "ModelFileDownload.Failure.network"
            case .http(let status): return "ModelFileDownload.Failure.http(\(status))"
            case .rangeNotSatisfiable: return "ModelFileDownload.Failure.rangeNotSatisfiable"
            case .tooLarge: return "ModelFileDownload.Failure.tooLarge"
            case .diskFull: return "ModelFileDownload.Failure.diskFull"
            case .file: return "ModelFileDownload.Failure.file"
            }
        }
    }

    /// Progress is reported at most once per this many bytes.
    static let progressStep: Int64 = 1_048_576

    private let url: URL
    private let partURL: URL
    private let expectedBytes: Int64
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var lastReported: Int64 = 0
    private var failure: Failure?
    private var isCancelled = false
    private var onProgress: ((Int64) -> Void)?
    private var onFinish: ((Result<Void, Failure>) -> Void)?

    init(url: URL, partURL: URL, expectedBytes: Int64) {
        self.url = url
        self.partURL = partURL
        self.expectedBytes = expectedBytes
    }

    func start(in session: URLSession, onProgress: @escaping (Int64) -> Void, onFinish: @escaping (Result<Void, Failure>) -> Void) {
        self.onProgress = onProgress
        self.onFinish = onFinish
        if !FileManager.default.fileExists(atPath: partURL.path) {
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
        }
        received = AIChatLocalModelDownloader.fileSize(at: partURL) ?? 0
        lastReported = received

        var request = URLRequest(url: url)
        if received > 0 {
            request.setValue("bytes=\(received)-", forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request)
        task.delegate = self
        lock.lock()
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            switch status {
            case 206:
                handle = try FileHandle(forWritingTo: partURL)
                try handle?.seekToEnd()
            case 200:
                // The server sent the whole file, so what was saved before doesn't apply.
                handle = try FileHandle(forWritingTo: partURL)
                try handle?.truncate(atOffset: 0)
                received = 0
                // Without this, progress would stay at the old size until the new bytes passed it.
                lastReported = 0
                onProgress?(0)
            case 416:
                failure = .rangeNotSatisfiable
            default:
                failure = .http(status)
            }
        } catch {
            failure = .file
        }
        completionHandler(failure == nil ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, let handle else { return }
        guard received + Int64(data.count) <= expectedBytes else {
            failure = .tooLarge
            dataTask.cancel()
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            failure = Self.isOutOfSpace(error) ? .diskFull : .file
            dataTask.cancel()
            return
        }
        received += Int64(data.count)
        if received - lastReported >= Self.progressStep || received == expectedBytes {
            lastReported = received
            onProgress?(received)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        lock.lock()
        let isCancelled = self.isCancelled
        lock.unlock()

        let result: Result<Void, Failure>
        if let failure {
            result = .failure(failure)
        } else if isCancelled {
            result = .failure(.cancelled)
        } else if error != nil {
            result = .failure(.network)
        } else if received == expectedBytes {
            result = .success(())
        } else {
            // The server closed the response early; continue from what arrived.
            result = .failure(.network)
        }
        onFinish?(result)
        onProgress = nil
        onFinish = nil
    }

    private static func isOutOfSpace(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError)
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC))
    }
}
