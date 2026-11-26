//
//  AIChatLocalModelDownloaderTests.swift
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
import Foundation
import Testing
@testable import AIChat

/// Serialized because the stub server is shared by every session in the process.
@MainActor
@Suite("Local model downloader", .serialized)
final class AIChatLocalModelDownloaderTests {

    private let model = Data((0..<1_000).map { UInt8($0 % 251) })
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LocalModels-\(UUID().uuidString)")
    private let defaults = UserDefaults(suiteName: "AIChatLocalModelDownloaderTests-\(UUID().uuidString)")!
    private let networkAvailable = PassthroughSubject<Void, Never>()
    private var capacity: Int64? = 10_000_000_000

    private var spec: AIChatLocalModelSpec {
        AIChatLocalModelSpec(id: "test-model",
                             name: "Test Model",
                             bytes: Int64(model.count),
                             url: URL(string: "https://models.example/test.gguf")!,
                             sha256: SHA256.hash(data: model).map { String(format: "%02x", $0) }.joined())
    }

    private var installedURL: URL { directory.appendingPathComponent("\(spec.sha256).gguf") }
    private var partURL: URL { directory.appendingPathComponent("\(spec.sha256).gguf.part") }

    init() {
        StubModelServer.reset()
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeDownloader(retryDelays: [TimeInterval] = [0.01, 0.01]) -> AIChatLocalModelDownloader {
        AIChatLocalModelDownloader(spec: spec,
                                   directory: directory,
                                   session: .makeLocalModelDownloads(protocolClasses: [StubModelServer.self]),
                                   defaults: defaults,
                                   availableCapacity: { [capacity] _ in capacity },
                                   retryDelays: retryDelays,
                                   networkAvailable: networkAvailable.eraseToAnyPublisher())
    }

    private func writePart(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: partURL)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Installing

    @available(iOS 16, macOS 13, *)
    @Test("Install downloads, checks and moves the file into place", .timeLimit(.minutes(1)))
    func installDownloadsAndVerifies() async throws {
        StubModelServer.respond { _ in .init(status: 200, body: self.model) }
        let downloader = makeDownloader()

        downloader.install()
        await waitUntil { downloader.state.isInstalled }

        #expect(downloader.state == .installed(installedURL))
        #expect(try Data(contentsOf: installedURL) == model)
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
        #expect(defaults.string(forKey: AIChatLocalModelDownloader.installRequestKey) == nil)
        #expect(AIChatLocalModelDownloader.installedFileURL(in: directory, spec: spec) == installedURL)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Requests carry no cookies or languages, no range on a fresh start and a generic user agent", .timeLimit(.minutes(1)))
    func requestsAreAnonymous() async throws {
        StubModelServer.respond { _ in .init(status: 200, body: self.model) }
        let downloader = makeDownloader()

        downloader.install()
        await waitUntil { downloader.state.isInstalled }

        let request = try #require(StubModelServer.requests.first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "DuckDuckGo")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "")
        #expect(request.value(forHTTPHeaderField: "Range") == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An installed model is found on the next launch", .timeLimit(.minutes(1)))
    func installedModelIsFoundAtLaunch() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try model.write(to: installedURL)

        #expect(makeDownloader().state == .installed(installedURL))
    }

    // MARK: - Continuing

    @available(iOS 16, macOS 13, *)
    @Test("A download asked for before a relaunch continues from the partial file", .timeLimit(.minutes(1)))
    func requestedDownloadContinuesAfterRelaunch() async throws {
        try writePart(model.prefix(400))
        defaults.set(spec.sha256, forKey: AIChatLocalModelDownloader.installRequestKey)
        StubModelServer.respond { _ in .init(status: 206, body: self.model.suffix(from: 400)) }

        let downloader = makeDownloader()
        #expect(downloader.state == .downloading(receivedBytes: 400, totalBytes: 1_000))

        downloader.resumeIfNeeded()
        await waitUntil { downloader.state.isInstalled }

        #expect(StubModelServer.requests.first?.value(forHTTPHeaderField: "Range") == "bytes=400-")
        #expect(try Data(contentsOf: installedURL) == model)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nothing continues on its own unless the user asked", .timeLimit(.minutes(1)))
    func nothingContinuesWithoutRequest() async throws {
        try writePart(model.prefix(400))
        let downloader = makeDownloader()

        downloader.resumeIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(downloader.state == .notInstalled)
        #expect(StubModelServer.requests.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A file that finished downloading before a relaunch is checked and installed, not asked for again", .timeLimit(.minutes(1)))
    func completeFileIsInstalledAfterRelaunch() async throws {
        try writePart(model)
        defaults.set(spec.sha256, forKey: AIChatLocalModelDownloader.installRequestKey)
        StubModelServer.respond { _ in .init(status: 416, body: Data()) }
        let downloader = makeDownloader()

        downloader.resumeIfNeeded()
        await waitUntil { downloader.state.isInstalled }

        #expect(downloader.state == .installed(installedURL))
        #expect(try Data(contentsOf: installedURL) == model)
        #expect(StubModelServer.requests.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A finished file that doesn't match its SHA-256 is deleted without asking the server", .timeLimit(.minutes(1)))
    func completeButCorruptFileIsDeleted() async throws {
        try writePart(Data(repeating: 0xFF, count: model.count))
        defaults.set(spec.sha256, forKey: AIChatLocalModelDownloader.installRequestKey)
        let downloader = makeDownloader()

        downloader.resumeIfNeeded()
        await waitUntil { downloader.state == .failed(.unknown) }

        #expect(downloader.state == .failed(.unknown))
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
        #expect(StubModelServer.requests.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A server that ignores the range sends the whole file, which replaces the partial one", .timeLimit(.minutes(1)))
    func fullResponseReplacesPartialFile() async throws {
        try writePart(Data(repeating: 0xFF, count: 400))
        StubModelServer.respond { _ in .init(status: 200, body: self.model) }
        let downloader = makeDownloader()
        var states: [AIChatLocalModelInstallState] = []
        let subscription = downloader.statePublisher.sink { states.append($0) }

        downloader.install()
        await waitUntil { downloader.state.isInstalled }
        subscription.cancel()

        #expect(try Data(contentsOf: installedURL) == model)
        let restart = try #require(states.firstIndex(of: .downloading(receivedBytes: 400, totalBytes: 1_000)))
        #expect(states[restart...].contains(.downloading(receivedBytes: 0, totalBytes: 1_000)))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Pause keeps the partial file and resumeIfNeeded continues it", .timeLimit(.minutes(1)))
    func pauseKeepsPartialFile() async throws {
        try writePart(model.prefix(300))
        StubModelServer.respond { _ in .init(status: 200, body: Data(), error: URLError(.networkConnectionLost)) }
        let downloader = makeDownloader(retryDelays: [100])
        downloader.install()
        await waitUntil { StubModelServer.requests.count == 1 }

        downloader.pause()
        StubModelServer.respond { _ in .init(status: 206, body: self.model.suffix(from: 300)) }
        downloader.resumeIfNeeded()
        await waitUntil { downloader.state.isInstalled }

        #expect(StubModelServer.requests.map { $0.value(forHTTPHeaderField: "Range") } == ["bytes=300-", "bytes=300-"])
        #expect(try Data(contentsOf: installedURL) == model)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only a running request counts as active, not a pause or a wait to retry", .timeLimit(.minutes(1)))
    func activeOnlyWhileARequestRuns() async {
        StubModelServer.respond { _ in .init(status: 200, body: Data(), error: URLError(.networkConnectionLost)) }
        let downloader = makeDownloader(retryDelays: [100])
        #expect(!downloader.isActive)

        downloader.install()
        #expect(downloader.isActive)

        await waitUntil { !downloader.isActive }
        #expect(downloader.state.isDownloading)
        #expect(!downloader.isActive)

        downloader.pause()
        #expect(downloader.state.isDownloading)
        #expect(!downloader.isActive)
    }

    // MARK: - Failing

    @available(iOS 16, macOS 13, *)
    @Test("Network errors retry, then fail with network and keep the partial file", .timeLimit(.minutes(1)))
    func networkErrorsRetryThenFail() async throws {
        StubModelServer.respond { _ in .init(status: 200, body: Data(), error: URLError(.notConnectedToInternet)) }
        let downloader = makeDownloader(retryDelays: [0.01, 0.01])

        downloader.install()
        await waitUntil { downloader.state == .failed(.network) }

        #expect(downloader.state == .failed(.network))
        #expect(StubModelServer.requests.count == 3)
        #expect(FileManager.default.fileExists(atPath: partURL.path))
        #expect(defaults.string(forKey: AIChatLocalModelDownloader.installRequestKey) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A connection that keeps dropping but adds bytes each time isn't stopped by the retry limit", .timeLimit(.minutes(1)))
    func progressKeepsTheDownloadGoing() async {
        // Each response ends after 100 bytes, which the download treats like a dropped connection.
        StubModelServer.respond { request in
            let start = request.value(forHTTPHeaderField: "Range")
                .flatMap { Int($0.dropFirst("bytes=".count).dropLast()) } ?? 0
            let end = min(start + 100, self.model.count)
            return .init(status: start == 0 ? 200 : 206, body: self.model.subdata(in: start..<end))
        }
        let downloader = makeDownloader(retryDelays: [0.01])

        downloader.install()
        await waitUntil { downloader.state.isInstalled }

        #expect(downloader.state.isInstalled)
        #expect(StubModelServer.requests.count == 10)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The network coming back retries without waiting", .timeLimit(.minutes(1)))
    func networkComingBackRetriesNow() async throws {
        StubModelServer.respond { _ in .init(status: 200, body: Data(), error: URLError(.notConnectedToInternet)) }
        let downloader = makeDownloader(retryDelays: [100])
        downloader.install()
        await waitUntil { StubModelServer.requests.count == 1 }
        try await Task.sleep(nanoseconds: 50_000_000)

        StubModelServer.respond { _ in .init(status: 200, body: self.model) }
        networkAvailable.send()
        await waitUntil { downloader.state.isInstalled }

        #expect(downloader.state.isInstalled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A client error fails at once, with no retry", .timeLimit(.minutes(1)))
    func clientErrorFailsAtOnce() async {
        StubModelServer.respond { _ in .init(status: 404, body: Data()) }
        let downloader = makeDownloader()

        downloader.install()
        await waitUntil { downloader.state == .failed(.unknown) }

        #expect(downloader.state == .failed(.unknown))
        #expect(StubModelServer.requests.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A file that doesn't match its SHA-256 is deleted", .timeLimit(.minutes(1)))
    func mismatchedFileIsDeleted() async {
        StubModelServer.respond { _ in .init(status: 200, body: Data(repeating: 7, count: 1_000)) }
        let downloader = makeDownloader()

        downloader.install()
        await waitUntil { downloader.state == .failed(.unknown) }

        #expect(downloader.state == .failed(.unknown))
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
        #expect(!FileManager.default.fileExists(atPath: installedURL.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A download larger than the model is stopped", .timeLimit(.minutes(1)))
    func oversizedDownloadIsStopped() async {
        StubModelServer.respond { _ in .init(status: 200, body: self.model + Data(repeating: 1, count: 500)) }
        let downloader = makeDownloader()

        downloader.install()
        await waitUntil { downloader.state == .failed(.unknown) }

        #expect(downloader.state == .failed(.unknown))
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Too little free space fails with disk_full before downloading", .timeLimit(.minutes(1)))
    func lowDiskSpaceFailsBeforeDownloading() {
        capacity = 1_000
        let downloader = makeDownloader()

        downloader.install()

        #expect(downloader.state == .failed(.diskFull))
        #expect(StubModelServer.requests.isEmpty)
    }

    // MARK: - Removing

    @available(iOS 16, macOS 13, *)
    @Test("Cancel stops the download and deletes the partial file", .timeLimit(.minutes(1)))
    func cancelDeletesPartialFile() async throws {
        try writePart(model.prefix(300))
        StubModelServer.respond { _ in .init(status: 200, body: Data(), error: URLError(.networkConnectionLost)) }
        let downloader = makeDownloader(retryDelays: [100])
        downloader.install()
        await waitUntil { StubModelServer.requests.count == 1 }

        downloader.cancel()

        #expect(downloader.state == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
        #expect(defaults.string(forKey: AIChatLocalModelDownloader.installRequestKey) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Uninstall deletes the model", .timeLimit(.minutes(1)))
    func uninstallDeletesModel() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try model.write(to: installedURL)
        let downloader = makeDownloader()

        downloader.uninstall()

        #expect(downloader.state == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: installedURL.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Installing removes another model's files", .timeLimit(.minutes(1)))
    func installRemovesOtherModels() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let otherModel = directory.appendingPathComponent("\(String(repeating: "a", count: 64)).gguf")
        StubModelServer.respond { _ in .init(status: 200, body: self.model) }
        let downloader = makeDownloader()
        try Data([1, 2, 3]).write(to: otherModel)

        downloader.install()
        await waitUntil { downloader.state.isInstalled }

        #expect(!FileManager.default.fileExists(atPath: otherModel.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An earlier model's files are deleted at launch, and this model's partial download is kept", .timeLimit(.minutes(1)))
    func launchDeletesEarlierModels() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let earlierModel = directory.appendingPathComponent("\(String(repeating: "a", count: 64)).gguf")
        let earlierPart = directory.appendingPathComponent("\(String(repeating: "b", count: 64)).gguf.part")
        try Data([1, 2, 3]).write(to: earlierModel)
        try Data([1]).write(to: earlierPart)
        try writePart(model.prefix(300))
        defaults.set(spec.sha256, forKey: AIChatLocalModelDownloader.installRequestKey)

        let downloader = makeDownloader()

        #expect(!FileManager.default.fileExists(atPath: earlierModel.path))
        #expect(!FileManager.default.fileExists(atPath: earlierPart.path))
        #expect(FileManager.default.fileExists(atPath: partURL.path))
        #expect(downloader.state == .downloading(receivedBytes: 300, totalBytes: Int64(model.count)))
    }

    /// Remote config can switch models, which leaves the earlier model's files behind.
    @available(iOS 16, macOS 13, *)
    @Test("Uninstall and Cancel also delete an earlier model's files", .timeLimit(.minutes(1)))
    func removingDeletesEarlierModels() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let earlierModel = directory.appendingPathComponent("\(String(repeating: "a", count: 64)).gguf")
        let earlierPart = directory.appendingPathComponent("\(String(repeating: "b", count: 64)).gguf.part")
        let downloader = makeDownloader()

        try Data([1, 2, 3]).write(to: earlierModel)
        try Data([1]).write(to: earlierPart)
        downloader.uninstall()
        #expect(!FileManager.default.fileExists(atPath: earlierModel.path))
        #expect(!FileManager.default.fileExists(atPath: earlierPart.path))

        try Data([1, 2, 3]).write(to: earlierModel)
        try Data([1]).write(to: earlierPart)
        downloader.cancel()
        #expect(!FileManager.default.fileExists(atPath: earlierModel.path))
        #expect(!FileManager.default.fileExists(atPath: earlierPart.path))
    }
}

// MARK: - Remote config

@Suite("Local model spec")
struct AIChatLocalModelSpecTests {

    private func settings(url: String = "https://models.example/m.gguf",
                          sha256: String = String(repeating: "A", count: 64),
                          bytes: Int = 10) -> String {
        """
        {"models": {"llamaCpp": {"id": "m", "name": "M", "bytes": \(bytes), "url": "\(url)", "sha256": "\(sha256)"},
                    "otherRuntime": {"id": "w", "name": "W"}}}
        """
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reads llama.cpp's model from remote config and lowercases the SHA-256", .timeLimit(.minutes(1)))
    func readsLlamaCppModel() throws {
        let spec = try #require(AIChatLocalModelSpec.fromRemoteSettings(settings()))
        #expect(spec.id == "m")
        #expect(spec.name == "M")
        #expect(spec.bytes == 10)
        #expect(spec.sha256 == String(repeating: "a", count: 64))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Rejects a model llama.cpp can't safely download", .timeLimit(.minutes(1)))
    func rejectsUnusableModels() {
        #expect(AIChatLocalModelSpec.fromRemoteSettings(settings(url: "http://models.example/m.gguf")) == nil)
        #expect(AIChatLocalModelSpec.fromRemoteSettings(settings(sha256: "abc")) == nil)
        #expect(AIChatLocalModelSpec.fromRemoteSettings(settings(sha256: String(repeating: "z", count: 64))) == nil)
        #expect(AIChatLocalModelSpec.fromRemoteSettings(settings(bytes: 0)) == nil)
        #expect(AIChatLocalModelSpec.fromRemoteSettings("{}") == nil)
        #expect(AIChatLocalModelSpec.fromRemoteSettings(nil) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The built-in model is Gemma 4 E2B", .timeLimit(.minutes(1)))
    func builtInModelIsGemma4E2B() {
        #expect(AIChatLocalModelSpec.gemma4E2B.info == AIChatLocalModelInfo(id: "gemma-4-e2b", name: "Gemma 4 E2B"))
        #expect(AIChatLocalModelSpec.gemma4E2B.url.scheme == "https")
    }
}

// MARK: - Stub server

private final class StubModelServer: URLProtocol {

    struct Response {
        let status: Int
        let body: Data
        var error: Error?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (URLRequest) -> Response = { _ in Response(status: 500, body: Data()) }
    nonisolated(unsafe) private static var receivedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return receivedRequests
    }

    static func respond(with handler: @escaping (URLRequest) -> Response) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = { _ in Response(status: 500, body: Data()) }
        receivedRequests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.receivedRequests.append(request)
        let response = Self.handler(request)
        Self.lock.unlock()

        guard let url = request.url,
              let httpResponse = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        if !response.body.isEmpty {
            client?.urlProtocol(self, didLoad: response.body)
        }
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
