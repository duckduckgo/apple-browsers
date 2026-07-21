//
//  RemoteBrokerRulesProvider.swift
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
import ZIPFoundation
import DataBrokerProtectionCore

/// A resolved remote rules base URL. Mirrors dbp-api's hosting scheme; branch deploys are served at
/// `https://dbp-staging.duckduckgo.com/branches/<sanitized-branch>`.
public enum RemoteBrokerEndpoint {
    case production
    case staging
    /// Staging + `branches/<sanitized>` prefix. Applies dbp-api's branch-name sanitization.
    case stagingBranch(String)
    /// A verbatim custom base URL (e.g. a localhost fake broker).
    case custom(URL)

    public var baseURL: URL {
        switch self {
        case .production:
            return PIRDebugRemoteHosts.production
        case .staging:
            return PIRDebugRemoteHosts.staging
        case .stagingBranch(let name):
            let sanitized = PIRDebugBranchNameSanitizer.sanitize(name)
            return PIRDebugRemoteHosts.staging
                .appendingPathComponent("branches")
                .appendingPathComponent(sanitized)
        case .custom(let url):
            return url
        }
    }
}

/// In-memory equivalent of `RemoteBrokerJSONService`: fetches `main_config.json` (ETag /
/// If-None-Match) and `all.zip&type=spec`, unzips to a temp directory, and decodes the brokers
/// named in `active_data_brokers` (+ `test_data_brokers` when enabled). Sends no Authorization
/// header — these endpoints are unauthenticated — and never touches the vault or keychain.
public final class RemoteBrokerRulesProvider: BrokerRulesProviding {

    private struct MainConfigResponse: Decodable {
        let activeDataBrokers: [String]
        let testDataBrokers: [String]

        enum CodingKeys: String, CodingKey {
            case activeDataBrokers = "active_data_brokers"
            case testDataBrokers = "test_data_brokers"
        }
    }

    /// Remote rules downloaded and extracted to a caller-owned temp directory. Shared by
    /// `fetchBrokers()` and the CLI's `fetch-rules`.
    public struct MaterializedRules {
        /// Raw `main_config.json` bytes (byte-identical to the served file).
        public let mainConfigData: Data
        /// Temp directory holding the extracted broker JSONs. The caller must remove it.
        public let extractionDirectory: URL
        /// Extracted broker files keyed by file name (e.g. `fakebroker.com.json`).
        public let brokerFilesByName: [String: URL]
        public let activeDataBrokers: [String]
        public let testDataBrokers: [String]
    }

    public let baseURL: URL
    public let includeTestBrokers: Bool
    /// When set, sent as `If-None-Match`; a 304 response throws `PIRDebugError.remoteRulesNotModified`.
    public let eTag: String?
    private let urlSession: URLSession
    private let fileManager: FileManager

    public init(endpoint: RemoteBrokerEndpoint,
                includeTestBrokers: Bool = false,
                eTag: String? = nil,
                urlSession: URLSession = .shared,
                fileManager: FileManager = .default) {
        self.baseURL = endpoint.baseURL
        self.includeTestBrokers = includeTestBrokers
        self.eTag = eTag
        self.urlSession = urlSession
        self.fileManager = fileManager
    }

    public init(baseURL: URL,
                includeTestBrokers: Bool = false,
                eTag: String? = nil,
                urlSession: URLSession = .shared,
                fileManager: FileManager = .default) {
        self.baseURL = baseURL
        self.includeTestBrokers = includeTestBrokers
        self.eTag = eTag
        self.urlSession = urlSession
        self.fileManager = fileManager
    }

    public func fetchBrokers() async throws -> [DataBroker] {
        let materialized = try await materialize()
        defer { try? fileManager.removeItem(at: materialized.extractionDirectory) }

        var wantedFileNames = Set(materialized.activeDataBrokers)
        if includeTestBrokers {
            wantedFileNames.formUnion(materialized.testDataBrokers)
        }

        let decoder = makeBrokerRulesDecoder()
        return try materialized.brokerFilesByName
            .filter { wantedFileNames.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { try decoder.decode(DataBroker.self, from: Data(contentsOf: $0.value)) }
    }

    /// Downloads and extracts the remote rules to a fresh temp directory the caller owns (and must
    /// remove via ``MaterializedRules/extractionDirectory``). `fetch-rules` uses this to write the
    /// files byte-identical to the zip contents; `fetchBrokers()` decodes from it.
    public func materialize() async throws -> MaterializedRules {
        let mainConfigData = try await fetchMainConfigData()
        let config = try JSONDecoder().decode(MainConfigResponse.self, from: mainConfigData)
        let extractionDir = try await downloadAndExtractAllBrokers()

        let jsonDir = extractionDir.appendingPathComponent("json", isDirectory: true)
        let searchDir = fileManager.fileExists(atPath: jsonDir.path) ? jsonDir : extractionDir
        let fileURLs = try fileManager.contentsOfDirectory(at: searchDir,
                                                           includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles])
        let byName = Dictionary(fileURLs.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        return MaterializedRules(mainConfigData: mainConfigData,
                                 extractionDirectory: extractionDir,
                                 brokerFilesByName: byName,
                                 activeDataBrokers: config.activeDataBrokers,
                                 testDataBrokers: config.testDataBrokers)
    }

    // MARK: - Requests

    private func mainConfigURL() -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        components?.path += "/dbp/remote/v0/main_config.json"
        return components?.url ?? baseURL.appendingPathComponent("dbp/remote/v0/main_config.json")
    }

    private func allBrokersURL() -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        components?.path += "/dbp/remote/v0"
        components?.queryItems = [
            URLQueryItem(name: "name", value: "all.zip"),
            URLQueryItem(name: "type", value: "spec")
        ]
        return components?.url ?? baseURL.appendingPathComponent("dbp/remote/v0")
    }

    private func fetchMainConfigData() async throws -> Data {
        var request = URLRequest(url: mainConfigURL())
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let eTag {
            request.cachePolicy = .reloadIgnoringCacheData
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PIRDebugError.remoteRulesClientError
        }
        if httpResponse.statusCode == 304 {
            throw PIRDebugError.remoteRulesNotModified
        }
        guard httpResponse.statusCode == 200 else {
            throw PIRDebugError.remoteRulesServerError(statusCode: httpResponse.statusCode)
        }
        return data
    }

    private func downloadAndExtractAllBrokers() async throws -> URL {
        var request = URLRequest(url: allBrokersURL())
        request.httpMethod = "GET"

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PIRDebugError.remoteRulesServerError(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }

        let uniqueName = UUID().uuidString
        let archiveURL = fileManager.temporaryDirectory.appendingPathComponent(uniqueName).appendingPathExtension("zip")
        let extractionDir = fileManager.temporaryDirectory.appendingPathComponent(uniqueName, isDirectory: true)

        try data.write(to: archiveURL)
        defer { try? fileManager.removeItem(at: archiveURL) }

        do {
            try fileManager.unzipItem(at: archiveURL, to: extractionDir, allowUncontainedSymlinks: false)
        } catch {
            try? fileManager.removeItem(at: extractionDir)
            throw error
        }
        return extractionDir
    }
}
