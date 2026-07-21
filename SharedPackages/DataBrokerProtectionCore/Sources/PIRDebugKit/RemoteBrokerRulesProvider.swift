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
            return URL(string: "https://dbp.duckduckgo.com")!
        case .staging:
            return URL(string: "https://dbp-staging.duckduckgo.com")!
        case .stagingBranch(let name):
            let sanitized = PIRDebugBranchNameSanitizer.sanitize(name)
            return URL(string: "https://dbp-staging.duckduckgo.com")!
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
        let mainConfig = try await fetchMainConfig()
        let extractionDir = try await downloadAndExtractAllBrokers()
        defer { try? fileManager.removeItem(at: extractionDir) }

        var wantedFileNames = Set(mainConfig.activeDataBrokers)
        if includeTestBrokers {
            wantedFileNames.formUnion(mainConfig.testDataBrokers)
        }

        let jsonDir = extractionDir.appendingPathComponent("json", isDirectory: true)
        let searchDir = fileManager.fileExists(atPath: jsonDir.path) ? jsonDir : extractionDir
        let fileURLs = try fileManager.contentsOfDirectory(at: searchDir,
                                                           includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        var brokers: [DataBroker] = []
        for fileURL in fileURLs where wantedFileNames.contains(fileURL.lastPathComponent) {
            let data = try Data(contentsOf: fileURL)
            brokers.append(try decoder.decode(DataBroker.self, from: data))
        }
        return brokers
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

    private func fetchMainConfig() async throws -> MainConfigResponse {
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
        return try JSONDecoder().decode(MainConfigResponse.self, from: data)
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
            try fileManager.unzipItem(at: archiveURL, to: extractionDir)
        } catch {
            throw error
        }
        return extractionDir
    }
}
