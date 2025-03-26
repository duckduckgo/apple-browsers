//
//  BrokerJSONService.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Subscription
import ZIPFoundation

public protocol BrokerJSONServiceProvider: AnyObject {
    func checkForBrokerJSONUpdates() async throws
}

public final class BrokerJSONService: BrokerJSONServiceProvider {
    enum Error: Swift.Error {
        case missingAccessToken
        case serverError
        case clientError
    }

    enum Endpoint {
        case mainConfig
        case allBrokers

        static func request(for endpoint: Endpoint,
                            baseURL: URL,
                            contentType: String? = nil,
                            eTag: String? = nil,
                            accessToken: String) throws -> URLRequest {
            var request = URLRequest(url: try url(for: endpoint, baseURL: baseURL))
            request.httpMethod = "GET"
            if let contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            if let eTag {
                request.cachePolicy = .reloadIgnoringCacheData
                request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
            }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            return request
        }

        private static func url(for endpoint: Endpoint, baseURL: URL) throws -> URL {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)

            switch endpoint {
            case .mainConfig:
                components?.path = "/dbp/remote/v0/main_config.json"
            case .allBrokers:
                var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
                components?.path = "/dbp/remote/v0"
                components?.queryItems = [
                    .init(name: "name", value: "all.zip"),
                    .init(name: "type", value: "spec")
                ]
            }

            guard let url = components?.url else {
                throw Error.clientError
            }

            return url
        }
    }

    struct BrokerJSON: Hashable {
        let fileName: String
        let eTag: String

        static func from(payload: [String: String]) -> [BrokerJSON] {
            payload.map { fileName, eTag in
                .init(fileName: fileName, eTag: eTag)
            }
        }
    }

    private static let mainConfigETagKey = "brokerJSONMainConfigETag"

    private let defaults: UserDefaults
    private let settings: DataBrokerProtectionSettings
    private let vault: any DataBrokerProtectionSecureVault
    private let accountManager: AccountManager

    private let uncompressedBrokerJSONDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    public init(defaults: UserDefaults, settings: DataBrokerProtectionSettings, vault: any DataBrokerProtectionSecureVault, accountManager: AccountManager) {
        self.defaults = defaults
        self.settings = settings
        self.vault = vault
        self.accountManager = accountManager
    }

    // MARK: - Main flow

    public func checkForBrokerJSONUpdates() async throws {
        guard let accessToken = accountManager.accessToken else { throw Error.missingAccessToken }

        let request = try Endpoint.request(for: .mainConfig,
                                           baseURL: settings.selectedEnvironment.endpointURL,
                                           contentType: "application/json",
                                           eTag: loadMainConfigETag(),
                                           accessToken: accessToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { return }

        if response.statusCode == 304 {
            return
        }

        guard response.statusCode == 200 else { throw Error.serverError }

        try await checkForBrokerJSONUpdatesFromMainConfig(try JSONDecoder().decode(MainConfig.self, from: data))
        saveMainConfigETag(response.etag)
    }

    func checkForBrokerJSONUpdatesFromMainConfig(_ mainConfig: MainConfig) async throws {
        let eTagMapping = mainConfig.jsonETags.current
        let incomingBrokerJSONs = BrokerJSON.from(payload: eTagMapping)
        let savedBrokerJSONs = try vault.fetchAllBrokers().map { BrokerJSON(fileName: $0.url, eTag: $0.eTag) }
        let diff = Set(incomingBrokerJSONs).subtracting(Set(savedBrokerJSONs))
        guard !diff.isEmpty else { return }

        try await downloadBrokerJSONs()
        try processBrokerJSONs(withFileNames: diff.map(\.fileName),
                               eTagMapping: eTagMapping,
                               activeBrokers: mainConfig.activeDataBrokers)
    }

    // MARK: - File handling

    func downloadBrokerJSONs() async throws {
        guard let accessToken = accountManager.accessToken else { throw Error.missingAccessToken }

        let request = try Endpoint.request(for: .allBrokers,
                                           baseURL: settings.selectedEnvironment.endpointURL,
                                           accessToken: accessToken)
        let temporaryURL: URL

        if #available(macOS 12.0, *) {
            let (url, response) = try await URLSession.shared.download(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw Error.serverError
            }
            temporaryURL = url
        } else {
            temporaryURL = try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.downloadTask(with: request) { url, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                        continuation.resume(throwing: Error.serverError)
                        return
                    }

                    guard let url else {
                        continuation.resume(throwing: Error.clientError)
                        return
                    }

                    continuation.resume(returning: url)
                }
                task.resume()
            }
        }

        try FileManager.default.unzipItem(at: temporaryURL, to: uncompressedBrokerJSONDirectoryURL)
    }

    func processBrokerJSONs(withFileNames brokerFileNames: [String],
                            eTagMapping: [String: String],
                            activeBrokers: [String]) throws {
        let directoryURL: URL
        if #available(macOS 13.0, iOS 16.0, *) {
            directoryURL = uncompressedBrokerJSONDirectoryURL.appending(path: "json", directoryHint: .isDirectory)
        } else {
            directoryURL = uncompressedBrokerJSONDirectoryURL.appendingPathComponent("json", isDirectory: true)
        }
        let fileURLs = try FileManager.default.contentsOfDirectory(at: directoryURL,
                                                                   includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])
        for fileURL in fileURLs {
            let fileName = fileURL.lastPathComponent
            guard brokerFileNames.contains(fileName) else { continue }

            var dataBroker = try DataBroker.initFromResource(fileURL)
            dataBroker.setETag(eTagMapping[fileName] ?? "")
            dataBroker.setIsActive(activeBrokers.contains(fileName))

            try upsertBroker(dataBroker)
        }
    }

    func upsertBroker(_ broker: DataBroker) throws {
        guard let savedBroker = try vault.fetchBroker(with: broker.url) else {
            try addBroker(broker)
            return
        }

        guard shouldUpdate(incoming: broker.version, storedVersion: savedBroker.version) else { return }
        guard let savedBrokerId = savedBroker.id else { return }

        try vault.update(broker, with: savedBrokerId)
        try updateAttemptCount(broker)
    }

    /// 1. We save the broker into the database
    /// 2. We fetch the user profile and obtain the profile queries
    /// 3. We create the new scans operations for the profile queries and the new broker id
    func addBroker(_ broker: DataBroker) throws {
        let brokerId = try vault.save(broker: broker)
        let profileQueries = try vault.fetchAllProfileQueries(for: 1)
        let profileQueryIDs = profileQueries.compactMap({ $0.id })

        for profileQueryId in profileQueryIDs {
            try vault.save(brokerId: brokerId, profileQueryId: profileQueryId, lastRunDate: nil, preferredRunDate: Date())
        }
    }

    func shouldUpdate(incoming: String, storedVersion: String) -> Bool {
        let result = incoming.compare(storedVersion, options: .numeric)

        return result == .orderedDescending
    }

    /// Reset attempt count to 0 when broker JSON is updated
    func updateAttemptCount(_ broker: DataBroker) throws {
        guard let brokerId = broker.id else { return }

        let optOutJobs = try vault.fetchOptOuts(brokerId: brokerId)
        for optOutJob in optOutJobs {
            if let extractedProfileId = optOutJob.extractedProfile.id {
                try vault.updateAttemptCount(0, brokerId: brokerId, profileQueryId: optOutJob.profileQueryId, extractedProfileId: extractedProfileId)
            }
        }
    }

    // MARK: - ETag storage

    func loadMainConfigETag() -> String? {
        defaults.string(forKey: Self.mainConfigETagKey)
    }

    func saveMainConfigETag(_ etag: String?) {
        defaults.set(etag, forKey: Self.mainConfigETagKey)
    }

    func loadETag(forBrokerNamed name: String) throws -> String? {
        guard let broker = try vault.fetchBroker(with: name) else { return nil }
        return broker.eTag
    }
}

struct MainConfig: Decodable {
    let mainConfigETag: String
    let activeDataBrokers: [String]
    let jsonETags: JSONETagPayload
    let testDataBrokers: [String]

    struct JSONETagPayload: Decodable {
        let current: [String: String]
    }

    enum CodingKeys: String, CodingKey {
        case mainConfigETag = "main_config_etag"
        case activeDataBrokers = "active_data_brokers"
        case jsonETags = "json_etags"
        case testDataBrokers = "test_data_brokers"
    }
}
