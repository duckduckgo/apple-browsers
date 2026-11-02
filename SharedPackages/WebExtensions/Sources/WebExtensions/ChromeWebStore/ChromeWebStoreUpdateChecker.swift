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
            let update = try ManifestParser.parse(data, extensionID: extensionID)
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

    private static func isValidVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        return (1...Self.maximumVersionComponents).contains(parts.count) && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
                && (part.count == 1 || part.first != "0") && UInt16(part) != nil
        } && parts.contains { $0 != "0" }
    }

    private static func retryDeadline(response: HTTPURLResponse) -> Date? {
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

    private final class ManifestParser: NSObject, XMLParserDelegate {
        private static let namespace = "http://www.google.com/update2/response"
        private static let protocolVersion = "2.0"
        private static let successStatus = "ok"
        private static let noUpdateStatus = "noupdate"
        private static let maximumDepth = 16
        private static let maximumElementCount = 256
        private static let sha256HexLength = 64
        private let extensionID: String
        private var path: [String] = []
        private var elementCount = 0
        private var appCount = 0
        private var updateCount = 0
        private var invalid = false
        private var update: Update?

        private init(extensionID: String) {
            self.extensionID = extensionID
        }

        static func parse(_ data: Data, extensionID: String) throws -> Update? {
            guard let xml = String(data: data, encoding: .utf8), !xml.contains("\0"), !xml.contains("<!DOCTYPE") else {
                throw Failure.invalidManifest
            }
            // Reject declarations of other encodings before XMLParser can reinterpret the UTF-8 bytes.
            let document = xml.hasPrefix("\u{FEFF}") ? String(xml.dropFirst()) : xml
            if document.hasPrefix("<?xml"), let end = document.range(of: "?>") {
                let declaration = String(document[..<end.lowerBound])
                if declaration.contains("encoding"),
                   declaration.range(of: #"encoding\s*=\s*['"]UTF-8['"]"#, options: [.regularExpression, .caseInsensitive]) == nil {
                    throw Failure.invalidManifest
                }
            }
            let delegate = ManifestParser(extensionID: extensionID)
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse(), !delegate.invalid, delegate.appCount == 1, delegate.updateCount == 1 else {
                throw Failure.invalidManifest
            }
            return delegate.update
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            path.append(elementName)
            elementCount += 1
            guard path.count <= Self.maximumDepth, elementCount <= Self.maximumElementCount, namespaceURI == Self.namespace else {
                reject(parser)
                return
            }
            switch path {
            case ["gupdate"]:
                if attributeDict["protocol"] != Self.protocolVersion { reject(parser) }
            case ["gupdate", "app"]:
                appCount += 1
                if appCount != 1 || attributeDict["appid"] != extensionID || attributeDict["status"] != Self.successStatus { reject(parser) }
            case ["gupdate", "app", "updatecheck"]:
                readUpdate(attributeDict, parser: parser)
            case ["gupdate", "daystart"]:
                break
            default:
                reject(parser)
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            _ = path.popLast()
        }

        private func readUpdate(_ attributes: [String: String], parser: XMLParser) {
            updateCount += 1
            guard updateCount == 1 else { reject(parser); return }
            if attributes["status"] == Self.noUpdateStatus { return }
            guard attributes["status"] == Self.successStatus, let version = attributes["version"], ChromeWebStoreUpdateChecker.isValidVersion(version),
                  let codebase = attributes["codebase"], let url = URL(string: codebase),
                  ChromeWebStoreURL.isAllowedDownloadDestination(url), url.fragment == nil,
                  let sizeValue = attributes["size"], !sizeValue.isEmpty, sizeValue.utf8.allSatisfy({ (48...57).contains($0) }),
                  let size = Int(sizeValue), size > 0,
                  let hash = attributes["hash_sha256"], hash.utf8.count == Self.sha256HexLength,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
                reject(parser)
                return
            }
            update = Update(extensionID: extensionID, version: version, downloadURL: url, size: size, sha256: hash.lowercased())
        }

        private func reject(_ parser: XMLParser) {
            invalid = true
            parser.abortParsing()
        }

    }
}
