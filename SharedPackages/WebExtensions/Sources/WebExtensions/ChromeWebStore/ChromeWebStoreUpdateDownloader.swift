//
//  ChromeWebStoreUpdateDownloader.swift
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

/// Bounded download failures; package metadata and server messages are never sent.
public enum WebExtensionUpdateDownloadFailure: String, Error, CaseIterable, Sendable {
    case invalidRequest = "invalid_request"
    case invalidResponse = "invalid_response"
    case httpStatus = "http_status"
    case networkFailure = "network_failure"
    case sizeMismatch = "size_mismatch"
    case packageTooLarge = "package_too_large"
    case hashMismatch = "hash_mismatch"
}

@available(macOS 15.4, iOS 18.4, *)
struct ChromeWebStoreUpdateDownloader: Sendable {
    static let maximumPackageSize = 256 * 1024 * 1024
    private static let requestTimeout: TimeInterval = 120
    private static let resourceTimeout: TimeInterval = 30 * 60
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let configuration = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        configuration.httpAdditionalHeaders = ["User-Agent": ChromeWebStoreUpdateChecker.genericUserAgent, "Accept-Language": "en-US"]
        self.configuration = configuration
    }

    func download(_ update: ChromeWebStoreUpdateChecker.Update) async throws -> Data {
        try Task.checkCancellation()
        guard ChromeWebStoreURL.isValidExtensionID(update.extensionID),
              ChromeWebStoreURL.isAllowedDownloadDestination(update.downloadURL), update.downloadURL.fragment == nil,
              update.size > 0, update.sha256.count == SHA256.byteCount * 2,
              update.sha256.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw WebExtensionUpdateDownloadFailure.invalidRequest
        }
        guard update.size <= Self.maximumPackageSize else { throw WebExtensionUpdateDownloadFailure.packageTooLarge }
        let policy = DownloadPolicy(expectedSize: update.size)
        let session = URLSession(configuration: configuration, delegate: policy, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    policy.start(URLRequest(url: update.downloadURL), in: session, continuation: continuation)
                }
            } onCancel: {
                policy.cancel()
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw (error as? WebExtensionUpdateDownloadFailure) ?? .networkFailure
        }
    }

    static func validate(_ package: Data, against update: ChromeWebStoreUpdateChecker.Update) throws {
        guard package.count <= Self.maximumPackageSize else { throw WebExtensionUpdateDownloadFailure.packageTooLarge }
        guard package.count == update.size else { throw WebExtensionUpdateDownloadFailure.sizeMismatch }
        let hash = SHA256.hash(data: package).map { String(format: "%02x", $0) }.joined()
        guard hash == update.sha256.lowercased() else { throw WebExtensionUpdateDownloadFailure.hashMismatch }
    }

    // Response state is confined to URLSession's serial delegate queue; task cancellation uses the lock.
    final class DownloadPolicy: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let expectedSize: Int
        private let lock = NSLock()
        private var task: URLSessionDataTask?
        private var continuation: CheckedContinuation<Data, Error>?
        private var cancelled = false
        private var data = Data()
        private var failure: WebExtensionUpdateDownloadFailure?

        init(expectedSize: Int) { self.expectedSize = expectedSize }

        func start(_ request: URLRequest, in session: URLSession, continuation: CheckedContinuation<Data, Error>) {
            let task = session.dataTask(with: request)
            let cancelled = lock.withLock {
                self.task = task
                self.continuation = continuation
                return self.cancelled
            }
            task.resume()
            if cancelled { task.cancel() }
        }

        func cancel() {
            let task = lock.withLock {
                cancelled = true
                return self.task
            }
            task?.cancel()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let destination = request.url, ChromeWebStoreURL.isAllowedDownloadDestination(destination) else {
                failure = .invalidResponse
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            if let response = response as? HTTPURLResponse, let destination = response.url,
               ChromeWebStoreURL.isAllowedDownloadDestination(destination) {
                if response.statusCode != 200 { failure = .httpStatus }
                if response.statusCode == 200, response.expectedContentLength > 0, response.expectedContentLength != expectedSize {
                    failure = .sizeMismatch
                }
            } else {
                failure = .invalidResponse
            }
            completionHandler(failure == nil ? .allow : .cancel)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
            guard failure == nil else { return }
            guard chunk.count <= expectedSize - data.count else {
                failure = .sizeMismatch
                dataTask.cancel()
                return
            }
            data.append(chunk)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let continuation = lock.withLock {
                let continuation = self.continuation
                self.continuation = nil
                self.task = nil
                return continuation
            }
            if let failure {
                continuation?.resume(throwing: failure)
            } else if let error {
                continuation?.resume(throwing: error)
            } else if data.count != expectedSize {
                continuation?.resume(throwing: WebExtensionUpdateDownloadFailure.sizeMismatch)
            } else {
                continuation?.resume(returning: data)
            }
        }
    }
}
