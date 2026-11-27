//
//  ChromeWebStoreUpdateDownloaderTests.swift
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

import CryptoKit
import Foundation
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class ChromeWebStoreUpdateDownloaderTests: XCTestCase {
    private let package = Data("downloaded package".utf8)

    private func offer(data: Data? = nil, url: String = "https://clients2.googleusercontent.com/offered.crx?version=2") throws -> ChromeWebStoreUpdateChecker.Update {
        let data = data ?? package
        return .init(extensionID: ChromeWebStoreID.bitwarden.rawValue, version: "2.0", downloadURL: try XCTUnwrap(URL(string: url)),
                     size: data.count, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    private func downloader(configuration: URLSessionConfiguration = .ephemeral) -> ChromeWebStoreUpdateDownloader {
        configuration.protocolClasses = [PackageDownloadURLProtocol.self]
        return ChromeWebStoreUpdateDownloader(configuration: configuration)
    }

    private func respond(_ data: Data, status: Int = 200, headers: [String: String] = [:], finalURL: URL? = nil) {
        PackageDownloadURLProtocol.setHandler { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(finalURL ?? request.url), statusCode: status,
                                                       httpVersion: "HTTP/1.1", headerFields: headers))
            return (response, data)
        }
    }

    private func assertFailure(_ failure: WebExtensionUpdateDownloadFailure, update: ChromeWebStoreUpdateChecker.Update,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await downloader().download(update)
            XCTFail("Expected \(failure)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? WebExtensionUpdateDownloadFailure, failure, file: file, line: line)
        }
    }

    func testUsesExactOfferedURLAndPrivateGenericRequestConfiguration() async throws {
        let update = try offer()
        let expectedURL = update.downloadURL
        let data = package
        PackageDownloadURLProtocol.setHandler { request in
            XCTAssertEqual(request.url, expectedURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Mozilla/5.0")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "en-US")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (try XCTUnwrap(HTTPURLResponse(url: expectedURL, statusCode: 200, httpVersion: nil,
                                                headerFields: ["Set-Cookie": "package=tracking"])), data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": "Browser/123", "Authorization": "private", "Accept-Language": "es-AR"]
        let downloader = downloader(configuration: configuration)
        let first = try await downloader.download(update)
        let second = try await downloader.download(update)
        XCTAssertEqual(first, package)
        XCTAssertEqual(second, package)
    }

    func testInvalidMetadataIsRejectedBeforeNetworkAccess() async throws {
        PackageDownloadURLProtocol.setHandler { _ in
            XCTFail("Invalid metadata must not start a request")
            throw URLError(.badURL)
        }
        await assertFailure(.invalidRequest, update: try offer(url: "https://example.com/package.crx"))
        let valid = try offer()
        for update in [
            ChromeWebStoreUpdateChecker.Update(extensionID: "invalid", version: valid.version, downloadURL: valid.downloadURL,
                                               size: valid.size, sha256: valid.sha256),
            .init(extensionID: valid.extensionID, version: valid.version, downloadURL: valid.downloadURL, size: 0, sha256: valid.sha256),
            .init(extensionID: valid.extensionID, version: valid.version, downloadURL: valid.downloadURL, size: valid.size, sha256: "bad")
        ] {
            await assertFailure(.invalidRequest, update: update)
        }
        let oversized = ChromeWebStoreUpdateChecker.Update(extensionID: valid.extensionID, version: valid.version, downloadURL: valid.downloadURL,
                                                            size: ChromeWebStoreUpdateDownloader.maximumPackageSize + 1, sha256: valid.sha256)
        await assertFailure(.packageTooLarge, update: oversized)
    }

    func testRejectsDisallowedFinalDestinationAndHTTPFailure() async throws {
        respond(package, finalURL: try XCTUnwrap(URL(string: "https://example.com/package.crx")))
        await assertFailure(.invalidResponse, update: try offer())
        respond(package, status: 503)
        await assertFailure(.httpStatus, update: try offer())
    }

    func testRejectsTruncatedAndOversizedDownloads() async throws {
        let update = try offer()
        respond(Data(package.dropLast()))
        await assertFailure(.sizeMismatch, update: update)
        let oversized = package + Data([0])
        for headers in [[:], ["Content-Length": String(oversized.count)]] {
            respond(oversized, headers: headers)
            await assertFailure(.sizeMismatch, update: update)
        }
    }

    func testRejectsHashMismatchAfterAnExactSizeDownload() async throws {
        var changed = package
        changed[0] ^= 1
        respond(changed)
        let update = try offer()
        let data = try await downloader().download(update)
        XCTAssertThrowsError(try ChromeWebStoreUpdateDownloader.validate(data, against: update)) { error in
            XCTAssertEqual(error as? WebExtensionUpdateDownloadFailure, .hashMismatch)
        }
    }

    func testOversizedStreamingDownloadIsCancelledBeforeTheServerFinishes() async throws {
        for declaredSize in [nil, "1048576"] {
            OversizedPackageURLProtocol.reset(contentLength: declaredSize)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OversizedPackageURLProtocol.self]
            do {
                _ = try await ChromeWebStoreUpdateDownloader(configuration: configuration).download(offer())
                XCTFail("Oversized stream must fail")
            } catch {
                XCTAssertEqual(error as? WebExtensionUpdateDownloadFailure, .sizeMismatch)
            }
            XCTAssertFalse(OversizedPackageURLProtocol.reachedEnd, "Transfer must stop before the remaining body is sent")
        }
    }

    func testCancellationStopsAnInFlightTransferWithoutAFailureReason() async throws {
        let started = expectation(description: "Response body started")
        OversizedPackageURLProtocol.reset(contentLength: nil, onStarted: { started.fulfill() })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OversizedPackageURLProtocol.self]
        let valid = try offer()
        let update = ChromeWebStoreUpdateChecker.Update(extensionID: valid.extensionID, version: valid.version, downloadURL: valid.downloadURL,
                                                        size: 1048576, sha256: valid.sha256)
        let downloader = ChromeWebStoreUpdateDownloader(configuration: configuration)
        let task = Task { try await downloader.download(update) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Transfer must be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(OversizedPackageURLProtocol.reachedEnd)
    }

    func testRedirectPolicyChecksEachDestination() throws {
        let policy = ChromeWebStoreUpdateDownloader.DownloadPolicy(expectedSize: package.count)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = try XCTUnwrap(URL(string: "https://clients2.google.com/package.crx"))
        let response = try XCTUnwrap(HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil))
        let task = session.downloadTask(with: original)
        for (destination, allowed) in [
            ("https://clients2.googleusercontent.com/package.crx", true),
            ("https://clients2.google.com/package.crx", true),
            ("https://example.com/package.crx", false),
            ("http://clients2.google.com/package.crx", false),
            ("https://user:password@clients2.google.com/package.crx", false)
        ] {
            let request = URLRequest(url: try XCTUnwrap(URL(string: destination)))
            var accepted: URLRequest?
            policy.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { accepted = $0 }
            XCTAssertEqual(accepted, allowed ? request : nil)
        }
    }

}

private final class PackageDownloadURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func setHandler(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.withLock { self.handler = handler }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = Self.lock.withLock { Self.handler }
            let (response, data) = try XCTUnwrap(handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class OversizedPackageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var contentLength: String?
    private static var finished = false
    private static var onStarted: (() -> Void)?
    private let stateLock = NSLock()
    private var stopped = false
    static var reachedEnd: Bool { lock.withLock { finished } }

    static func reset(contentLength: String?, onStarted: (() -> Void)? = nil) {
        lock.withLock {
            self.contentLength = contentLength
            self.onStarted = onStarted
            finished = false
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let length = Self.lock.withLock { Self.contentLength }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                             headerFields: length.map { ["Content-Length": $0] } ?? [:]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 0, count: 32768))
        Self.lock.withLock { Self.onStarted }?()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.stateLock.withLock({ self.stopped }) else { return }
            Self.lock.withLock { Self.finished = true }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stateLock.withLock { stopped = true }
    }
}
