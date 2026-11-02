//
//  ChromeWebStoreUpdateChecker.swift
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

/// Discovers updates without downloading or installing their packages. The caller owns scheduling
/// and must honor `retryNotBefore` for subsequent checks against the update server.
@available(macOS 15.4, iOS 18.4, *)
public struct ChromeWebStoreUpdateChecker {
    /// Untrusted server metadata. The downloader must independently verify the package against it.
    public struct Update: Equatable, Sendable {
        public let extensionID: String
        public let version: String
        public let downloadURL: URL
        public let size: Int
        public let sha256: String
    }

    public enum Failure: Error, Equatable, Sendable {
        case invalidRequest, invalidResponse, invalidManifest, responseTooLarge, networkFailure, cancelled
        case httpStatus(Int)
    }

    public enum Outcome: Equatable, Sendable {
        case update(Update)
        case noUpdate
        case failure(Failure)
    }

    public struct CheckResult: Equatable, Sendable {
        public let outcome: Outcome
        /// Server-wide lower bound, retained even if the response fails validation.
        public let retryNotBefore: Date?
    }

    static let maximumResponseSize = 1024 * 1024
    private static let requestTimeout: TimeInterval = 30
    private static let maximumRetryDelay: TimeInterval = 24 * 60 * 60
    private static let maximumVersionComponents = 4
    private let configuration: URLSessionConfiguration

    public init() {
        self.init(configuration: .ephemeral)
    }

    init(configuration: URLSessionConfiguration) {
        let configuration = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.requestTimeout
        self.configuration = configuration
    }

    public func check(extensionID: String, installedVersion: String) async -> CheckResult {
        guard !Task.isCancelled else { return CheckResult(outcome: .failure(.cancelled), retryNotBefore: nil) }
        guard Self.isValidVersion(installedVersion),
              let url = try? ChromeWebStoreURL.updateCheckURL(for: extensionID, installedVersion: installedVersion) else {
            return CheckResult(outcome: .failure(.invalidRequest), retryNotBefore: nil)
        }
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var retryNotBefore: Date?
        do {
            let (bytes, response) = try await session.bytes(from: url, delegate: RedirectPolicy())
            guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
            retryNotBefore = Self.retryDeadline(response: response)
            guard let destination = response.url, ChromeWebStoreURL.isAllowedDownloadDestination(destination) else {
                throw Failure.invalidResponse
            }
            guard response.statusCode == 200 else { throw Failure.httpStatus(response.statusCode) }
            guard response.expectedContentLength <= Self.maximumResponseSize else { throw Failure.responseTooLarge }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumResponseSize else { throw Failure.responseTooLarge }
                data.append(byte)
            }
            try Task.checkCancellation()
            let update = try ChromeWebStoreUpdateManifestParser.parse(data, extensionID: extensionID)
            let outcome: Outcome
            if let update, SemanticVersionComparator().isVersion(update.version, newerThan: installedVersion) {
                outcome = .update(update)
            } else {
                outcome = .noUpdate
            }
            return CheckResult(outcome: outcome, retryNotBefore: retryNotBefore)
        } catch {
            return CheckResult(outcome: .failure(Self.failure(for: error)), retryNotBefore: retryNotBefore)
        }
    }

    private static func failure(for error: Error) -> Failure {
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
            return .cancelled
        }
        return (error as? Failure) ?? .networkFailure
    }

    static func isValidVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        return (1...Self.maximumVersionComponents).contains(parts.count) && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
                && (part.count == 1 || part.first != "0") && UInt16(part) != nil
        } && parts.contains { $0 != "0" }
    }

    static func retryDeadline(response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "X-Retry-After")?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        // Very large positive integers also mean the capped delay, rather than losing the throttle.
        let seconds = min(Double(value) ?? .infinity, Self.maximumRetryDelay)
        guard seconds > 0 else { return nil }
        return Date().addingTimeInterval(seconds)
    }

    final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(request.url.flatMap { ChromeWebStoreURL.isAllowedDownloadDestination($0) ? request : nil })
        }
    }
}
