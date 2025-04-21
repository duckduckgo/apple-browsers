//
//  RemoteBrokerJSONService.swift
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
import Common
import os.log

public protocol ZipArchiveHandling: FileManager {
    func unzipArchive(at sourceURL: URL, to destinationURL: URL) throws
}

extension FileManager: ZipArchiveHandling {
    @objc public func unzipArchive(at sourceURL: URL, to destinationURL: URL) throws {
        try unzipItem(at: sourceURL, to: destinationURL, skipCRC32: false, allowUncontainedSymlinks: false, progress: nil, pathEncoding: nil)
    }
}

public final class RemoteBrokerJSONService: BrokerJSONServiceProvider {
    enum Error: Swift.Error {
        case missingAccessToken
        case serverError
        case clientError
        case invalidDestinationURL
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

    private static let updateCheckInterval = TimeInterval.hours(1)

    private let settings: DataBrokerProtectionSettings
    public let vault: any DataBrokerProtectionSecureVault
    private let fileManager: ZipArchiveHandling
    private let urlSession: URLSession
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?
    private let localBrokerProvider: BrokerJSONFallbackProvider?

    private var uncompressedBrokerJSONDirectoryURL: URL?

    public init(settings: DataBrokerProtectionSettings,
                vault: any DataBrokerProtectionSecureVault,
                fileManager: ZipArchiveHandling = FileManager.default,
                urlSession: URLSession = .shared,
                authenticationManager: DataBrokerProtectionAuthenticationManaging,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>? = nil,
                localBrokerProvider: BrokerJSONFallbackProvider?) {
        self.settings = settings
        self.vault = vault
        self.fileManager = fileManager
        self.urlSession = urlSession
        self.authenticationManager = authenticationManager
        self.pixelHandler = pixelHandler
        self.localBrokerProvider = localBrokerProvider
    }

    // MARK: - Local fallback

    public func bundledBrokers() throws -> [DataBroker]? {
        try localBrokerProvider?.bundledBrokers()
    }

    // MARK: - Main flow

    public func checkForUpdates() async throws {
        try await checkForUpdates(skipsLimiter: false)
    }

    /// TODO: First scan should check for updates (needs double checking)
    public func checkForUpdates(skipsLimiter: Bool) async throws {
        do {
            /// 1. Ensure we're due for an update
            let lastBrokerJSONUpdateCheck = Date(timeIntervalSince1970: settings.lastBrokerJSONUpdateCheckTimestamp)
            if !skipsLimiter,
               Date().timeIntervalSince(lastBrokerJSONUpdateCheck) < Self.updateCheckInterval {
                Logger.dataBrokerProtection.log("Skipping broker JSON update check due to rate limiting")
                return
            }

            /// 2. Use bundled JSONs to populate/update the database
            try? await localBrokerProvider?.checkForUpdates()

            /// 3. Hit main_config.json endpoint for ETag and active broker changes
            guard let accessToken = await authenticationManager.accessToken() else { throw Error.missingAccessToken }

            let request = try Endpoint.request(for: .mainConfig,
                                               baseURL: settings.selectedEnvironment.endpointURL,
                                               contentType: "application/json",
                                               eTag: settings.mainConfigETag,
                                               accessToken: accessToken)
            let (data, response) = try await urlSession.data(for: request)
            guard let response = response as? HTTPURLResponse else { return }

            if response.statusCode == 304 {
                Logger.dataBrokerProtection.log("Broker JSONs are up to date: main config eTag matches")
                settings.updateLastSuccessfulBrokerJSONUpdateCheckTimestamp()
                return
            }

            guard response.statusCode == 200 else { throw Error.serverError }

            /// 4. Download, extract, and process changed broker JSONs
            try await checkForBrokerJSONUpdatesFromMainConfig(try JSONDecoder().decode(MainConfig.self, from: data))

            /// 5. Update last successful update timestamp
            settings.mainConfigETag = response.etag
            settings.updateLastSuccessfulBrokerJSONUpdateCheckTimestamp()
        } catch {
            pixelHandler?.fire(.miscError(error: error, functionOccurredIn: "checkForBrokerJSONUpdates"))
            throw error
        }
    }

    func checkForBrokerJSONUpdatesFromMainConfig(_ mainConfig: MainConfig) async throws {
        let eTagMapping = mainConfig.jsonETags.current
        let incomingBrokerJSONs = BrokerJSON.from(payload: eTagMapping)
        let savedBrokerJSONs = try vault.fetchAllBrokers().map { BrokerJSON(fileName: $0.url.appendingPathExtension("json"), eTag: $0.eTag) }
        let diff = Set(incomingBrokerJSONs).subtracting(Set(savedBrokerJSONs))

        guard !diff.isEmpty else {
            Logger.dataBrokerProtection.log("No changes detected in brokers, skipping update")
            return
        }

        Logger.dataBrokerProtection.log("Changes detected in \(diff.count, privacy: .public) brokers")

        try await downloadAndExtractBrokerJSONs()
        try processBrokerJSONs(withFileNames: diff.map(\.fileName),
                               eTagMapping: eTagMapping,
                               activeBrokers: mainConfig.activeDataBrokers,
                               testBrokers: mainConfig.testDataBrokers)
        try cleanUp()
    }

    // MARK: - File handling

    func downloadAndExtractBrokerJSONs() async throws {
        uncompressedBrokerJSONDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        guard let uncompressedBrokerJSONDirectoryURL else { throw Error.invalidDestinationURL }

        var isDirectory: ObjCBool = false
        guard !fileManager.fileExists(atPath: uncompressedBrokerJSONDirectoryURL.path, isDirectory: &isDirectory) else {
            Logger.dataBrokerProtection.log("Broker JSONs already downloaded and extracted, skipping download")
            return
        }

        guard let accessToken = await authenticationManager.accessToken() else { throw Error.missingAccessToken }

        let request = try Endpoint.request(for: .allBrokers,
                                           baseURL: settings.selectedEnvironment.endpointURL,
                                           accessToken: accessToken)

        let temporaryURL: URL = try await withCheckedThrowingContinuation { continuation in
            let task = urlSession.downloadTask(with: request) { url, response, error in
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

        do {
            try fileManager.unzipArchive(at: temporaryURL, to: uncompressedBrokerJSONDirectoryURL)
            Logger.dataBrokerProtection.log("Broker JSONs downloaded and extracted to temporary directory")
        } catch {
            Logger.dataBrokerProtection.log("Failed to extract downloaded broker JSONs: \(error)")
            throw error
        }
    }

    /// brokerFileNames might contain both active and test brokers
    /// TODO: Inject directory URL, test this logic
    func processBrokerJSONs(withFileNames changedBrokerFileNames: [String],
                            eTagMapping: [String: String],
                            activeBrokers: [String],
                            testBrokers: [String]) throws {
        guard let uncompressedBrokerJSONDirectoryURL else { throw Error.invalidDestinationURL }

        let directoryURL = uncompressedBrokerJSONDirectoryURL.appendingPathComponent("json", isDirectory: true)
        let fileURLs = try fileManager.contentsOfDirectory(at: directoryURL,
                                                           includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles])
        for fileURL in fileURLs {
            let fileName = fileURL.lastPathComponent
            guard changedBrokerFileNames.contains(fileName) else { continue }

            var dataBroker = try DataBroker.initFromResource(fileURL)
            dataBroker.setETag(eTagMapping[fileName] ?? "")
            if activeBrokers.contains(fileName) {
                try upsertBroker(dataBroker)
            }
        }
    }

    private func cleanUp() throws {
        guard let uncompressedBrokerJSONDirectoryURL else { return }
        try fileManager.removeItem(at: uncompressedBrokerJSONDirectoryURL)
        Logger.dataBrokerProtection.log("Temporary directory removed")
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
