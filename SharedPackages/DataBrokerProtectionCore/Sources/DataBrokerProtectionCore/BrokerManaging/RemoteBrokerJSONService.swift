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
import BrowserServicesKit

public protocol ZipArchiveHandling: FileManager, Sendable {
    func unzipArchive(at sourceURL: URL, to destinationURL: URL) throws
}

extension FileManager: @retroactive @unchecked Sendable {}
extension FileManager: ZipArchiveHandling {
    @objc public func unzipArchive(at sourceURL: URL, to destinationURL: URL) throws {
        try unzipItem(at: sourceURL, to: destinationURL, skipCRC32: false, allowUncontainedSymlinks: false, progress: nil, pathEncoding: nil)
    }
}

public protocol RemoteBrokerDeliveryFeatureFlagging {
    var isRemoteBrokerDeliveryFeatureOn: Bool { get }
}

public final class RemoteBrokerJSONService: BrokerJSONServiceProvider {
    enum Error: Swift.Error {
        case serverError(httpCode: Int?)
        case clientError
    }

    enum Endpoint {
        case mainConfig
        case allBrokers

        static func request(for endpoint: Endpoint,
                            endpointURL: URL,
                            contentType: String? = nil,
                            eTag: String? = nil,
                            accessToken: String) throws -> URLRequest {
            var request = URLRequest(url: try url(for: endpoint, endpointURL: endpointURL))
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

        private static func url(for endpoint: Endpoint, endpointURL: URL) throws -> URL {
            var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: true)

            switch endpoint {
            case .mainConfig:
                components?.path += "/dbp/remote/v0/main_config.json"
            case .allBrokers:
                components?.path += "/dbp/remote/v0"
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

    private let featureFlagger: RemoteBrokerDeliveryFeatureFlagging
    private let settings: DataBrokerProtectionSettings
    public let vault: any DataBrokerProtectionSecureVault
    private let fileManager: ZipArchiveHandling
    private let urlSession: URLSession
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?
    private let localBrokerProvider: BrokerJSONFallbackProvider?

    public init(featureFlagger: RemoteBrokerDeliveryFeatureFlagging,
                settings: DataBrokerProtectionSettings,
                vault: any DataBrokerProtectionSecureVault,
                fileManager: ZipArchiveHandling = FileManager.default,
                urlSession: URLSession = .shared,
                authenticationManager: DataBrokerProtectionAuthenticationManaging,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>? = nil,
                localBrokerProvider: BrokerJSONFallbackProvider?) {
        self.featureFlagger = featureFlagger
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

    public func checkForUpdates(skipsLimiter: Bool) async throws {
        if !featureFlagger.isRemoteBrokerDeliveryFeatureOn {
            Logger.dataBrokerProtection.log("Remote broker delivery not enabled, skip to local fallback")
            try? await localBrokerProvider?.checkForUpdates()
            return
        }

        do {
            /// 1. Ensure we're due for an update
            let lastBrokerJSONUpdateCheck = Date(timeIntervalSince1970: settings.lastBrokerJSONUpdateCheckTimestamp)
            if !skipsLimiter,
               Date().timeIntervalSince(lastBrokerJSONUpdateCheck) < Self.updateCheckInterval {
                Logger.dataBrokerProtection.log("🧩 Skipping broker JSON update check due to rate limiting")
                return
            }

            /// 2. Use bundled JSONs to populate/update the database
            try? await localBrokerProvider?.checkForUpdates()

            /// 3. Hit main_config.json endpoint for ETag and active broker changes
            guard let accessToken = await authenticationManager.accessToken() else {
                Logger.dataBrokerProtection.log("🧩 Skipping broker JSON update check due to absence of access token")
                return
            }

            let request = try Endpoint.request(for: .mainConfig,
                                               endpointURL: settings.endpointURL,
                                               contentType: "application/json",
                                               eTag: settings.mainConfigETag,
                                               accessToken: accessToken)
            let (data, response) = try await urlSession.data(for: request)
            guard let response = response as? HTTPURLResponse else { return }

            if response.statusCode == 304 {
                Logger.dataBrokerProtection.log("🧩 Broker JSONs are up to date: main config eTag matches")
                settings.updateLastSuccessfulBrokerJSONUpdateCheckTimestamp()
                return
            }

            guard response.statusCode == 200, let newETag = response.etag else {
                throw Error.serverError(httpCode: response.statusCode)
            }

            /// 4. Download, extract, and process changed broker JSONs
            try await checkForBrokerJSONUpdatesFromMainConfig(try JSONDecoder().decode(MainConfig.self, from: data), eTag: newETag)

            /// 5. Update last successful update timestamp
            settings.mainConfigETag = newETag
            settings.updateLastSuccessfulBrokerJSONUpdateCheckTimestamp()
        } catch {
            pixelHandler?.fire(.miscError(error: error, functionOccurredIn: "RemoteBrokerJSONService checkForUpdates"))
            throw error
        }
    }

    func checkForBrokerJSONUpdatesFromMainConfig(_ mainConfig: MainConfig, eTag: String) async throws {
        let eTagMapping = mainConfig.jsonETags.current
        let incomingBrokerJSONs = BrokerJSON.from(payload: eTagMapping)
        let savedBrokerJSONs = try vault.fetchAllBrokers().map { BrokerJSON(fileName: $0.url.appendingPathExtension("json"), eTag: $0.eTag) }
        let diff = Set(incomingBrokerJSONs).subtracting(Set(savedBrokerJSONs))

        guard !diff.isEmpty else {
            Logger.dataBrokerProtection.log("🧩 No changes detected in brokers, skipping update")
            return
        }

        Logger.dataBrokerProtection.log("🧩 Changes detected in \(diff.count, privacy: .public) brokers")

        try await downloadAndExtractBrokerJSONsIfNeeded(eTag: eTag)
        try processBrokerJSONs(eTag: eTag,
                               fileNames: diff.map(\.fileName),
                               eTagMapping: eTagMapping,
                               activeBrokers: mainConfig.activeDataBrokers,
                               testBrokers: mainConfig.testDataBrokers)
        try cleanUp(eTag: eTag)
    }

    // MARK: - File handling

    func downloadAndExtractBrokerJSONsIfNeeded(eTag: String) async throws {
        let brokerArchiveURL = fileManager.temporaryDirectory.appendingPathComponent(eTag).appendingPathExtension("zip")
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(eTag)

        /// 1. Return early if all.zip is already extracted
        var isDirectory: ObjCBool = false
        guard !fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            Logger.dataBrokerProtection.log("🧩 Broker JSONs already downloaded and extracted, skipping download")
            return
        }

        /// 2. Download all.zip if not exists
        do {
            if !fileManager.fileExists(atPath: brokerArchiveURL.path) {
                guard let accessToken = await authenticationManager.accessToken() else {
                    Logger.dataBrokerProtection.log("🧩 Skipping broker JSON update check due to absence of access token")
                    return
                }

                let request = try Endpoint.request(for: .allBrokers,
                                                   endpointURL: settings.endpointURL,
                                                   accessToken: accessToken)

                let _: URL = try await withCheckedThrowingContinuation { [weak fileManager] continuation in
                    let task = urlSession.downloadTask(with: request) { url, response, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }

                        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                            continuation.resume(throwing: Error.serverError(httpCode: (response as? HTTPURLResponse)?.statusCode))
                            return
                        }

                        guard let url else {
                            continuation.resume(throwing: Error.clientError)
                            return
                        }

                        do {
                            try fileManager?.moveItem(at: url, to: brokerArchiveURL)
                            Logger.dataBrokerProtection.log("🧩 Remote broker JSON downloaded: \(url, privacy: .public)")
                            continuation.resume(returning: url)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                    task.resume()
                }
            }
            Logger.dataBrokerProtection.log("🧩 Broker JSONs downloaded")
        } catch {
            Logger.dataBrokerProtection.log("🧩 Failed to download broker JSONs: \(error)")
            throw error
        }

        /// 3. Extract all.zip
        do {
            try fileManager.unzipArchive(at: brokerArchiveURL, to: directoryURL)
            Logger.dataBrokerProtection.log("🧩 Broker JSONs extracted to temporary directory")
        } catch {
            Logger.dataBrokerProtection.log("🧩 Failed to extract broker JSONs: \(error)")
            throw error
        }
    }

    /// brokerFileNames might contain both active and test brokers
    func processBrokerJSONs(eTag: String,
                            fileNames changedBrokerFileNames: [String],
                            eTagMapping: [String: String],
                            activeBrokers: [String],
                            testBrokers: [String]) throws {
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(eTag).appendingPathComponent("json", isDirectory: true)
        let fileURLs = try fileManager.contentsOfDirectory(at: directoryURL,
                                                           includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles])
        for fileURL in fileURLs {
            let fileName = fileURL.lastPathComponent
            guard changedBrokerFileNames.contains(fileName) else { continue }

            do {
                var dataBroker = try DataBroker.initFromResource(fileURL)
                dataBroker.setETag(eTagMapping[fileName] ?? "")
                if activeBrokers.contains(fileName) {
                    try upsertBroker(dataBroker)
                }
            } catch let error as DecodingError {
                Logger.dataBrokerProtection.log("🧩 Failed to decode JSON file \(fileURL.lastPathComponent): \(error), skipping update")
                pixelHandler?.fire(.miscError(error: error, functionOccurredIn: "RemoteBrokerJSONService processBrokerJSONs"))
            } catch let error as Step.DecodingError {
                Logger.dataBrokerProtection.log("🧩 JSON file \(fileURL.lastPathComponent) contains unsupported data: \(error), skipping update")
                pixelHandler?.fire(.miscError(error: error, functionOccurredIn: "RemoteBrokerJSONService processBrokerJSONs"))
            } catch {
                throw error
            }
        }
    }

    private func cleanUp(eTag: String) throws {
        let brokerArchiveURL = fileManager.temporaryDirectory.appendingPathComponent(eTag).appendingPathExtension("zip")
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(eTag)

        try fileManager.removeItem(at: brokerArchiveURL)
        try fileManager.removeItem(at: directoryURL)
        Logger.dataBrokerProtection.log("🧩 Temporary files removed")
    }
}

struct MainConfig: Codable {
    let mainConfigETag: String
    let activeDataBrokers: [String]
    let jsonETags: JSONETagPayload
    let testDataBrokers: [String]

    struct JSONETagPayload: Codable {
        let current: [String: String]
    }

    enum CodingKeys: String, CodingKey {
        case mainConfigETag = "main_config_etag"
        case activeDataBrokers = "active_data_brokers"
        case jsonETags = "json_etags"
        case testDataBrokers = "test_data_brokers"
    }
}
