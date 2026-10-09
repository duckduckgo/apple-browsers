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
import PrivacyConfig

public protocol ZipArchiveHandling: FileManager, Sendable {
    func unzipArchive(at sourceURL: URL, to destinationURL: URL) throws
}

extension FileManager: @retroactive @unchecked Sendable {}
extension FileManager: ZipArchiveHandling {
    @objc public func unzipArchive(at sourceURL: URL, to destinationURL: URL) throws {
        try unzipItem(at: sourceURL, to: destinationURL, skipCRC32: false, allowUncontainedSymlinks: false, progress: nil, pathEncoding: nil)
    }
}

public final class RemoteBrokerJSONService: BrokerJSONServiceProvider {
    public typealias FeatureFlagging = OptOutRetryErrorFeatureFlagging

    enum Error: Swift.Error, CustomNSError {
        case serverError(httpCode: Int?)
        case clientError

        static var errorDomain: String { "RemoteBrokerJSONService" }

         var errorCode: Int {
             switch self {
             case .serverError:
                 return 101
             case .clientError:
                 return 102
             }
         }

         var errorUserInfo: [String: Any] {
             switch self {
             case .clientError:
                 return [:]
             case .serverError(httpCode: let code):
                 guard let code else { return [:] }
                 return [NSUnderlyingErrorKey: NSError(domain: "HTTPError", code: code)]
             }
         }
    }

    enum Endpoint {
        case mainConfig
        case mainConfigSignature
        case allBrokers

        static func request(for endpoint: Endpoint,
                            endpointURL: URL,
                            contentType: String? = nil,
                            eTag: String? = nil) throws -> URLRequest {
            var request = URLRequest(url: try url(for: endpoint, endpointURL: endpointURL))
            request.httpMethod = "GET"
            if let contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            if let eTag {
                request.cachePolicy = .reloadIgnoringCacheData
                request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
            }

            return request
        }

        private static func url(for endpoint: Endpoint, endpointURL: URL) throws -> URL {
            var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: true)

            switch endpoint {
            case .mainConfig:
                components?.path += "/dbp/remote/v0/main_config.json"
            case .mainConfigSignature:
                components?.path += "/dbp/remote/v0/main_config.json.sig"
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

    private let featureFlagger: FeatureFlagging
    private let settings: DataBrokerProtectionSettings
    public let vault: any DataBrokerProtectionSecureVault
    public var optOutRetryErrorFeatureFlagger: OptOutRetryErrorFeatureFlagging { featureFlagger }
    private let fileManager: ZipArchiveHandling
    private let urlSession: URLSession
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?
    private let localBrokerProvider: BrokerJSONFallbackProvider?
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let signingKeys: BrokerBundleSigningKeys

    public init(featureFlagger: FeatureFlagging,
                settings: DataBrokerProtectionSettings,
                vault: any DataBrokerProtectionSecureVault,
                fileManager: ZipArchiveHandling = FileManager.default,
                urlSession: URLSession = .shared,
                authenticationManager: DataBrokerProtectionAuthenticationManaging,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>? = nil,
                localBrokerProvider: BrokerJSONFallbackProvider?,
                privacyConfigurationManager: PrivacyConfigurationManaging,
                signingKeys: BrokerBundleSigningKeys = .builtIn) {
        self.featureFlagger = featureFlagger
        self.settings = settings
        self.vault = vault
        self.fileManager = fileManager
        self.urlSession = urlSession
        self.authenticationManager = authenticationManager
        self.pixelHandler = pixelHandler
        self.localBrokerProvider = localBrokerProvider
        self.privacyConfigurationManager = privacyConfigurationManager
        self.signingKeys = signingKeys
    }

    // MARK: - Local fallback

    public func bundledBrokers() throws -> [BrokerResource]? {
        try localBrokerProvider?.bundledBrokers()
    }

    // MARK: - Main flow

    public func checkForUpdates() async throws {
        try await checkForUpdates(skipsLimiter: false)
    }

    public func checkForUpdates(skipsLimiter: Bool) async throws {
        if let runTypeProvider = self.settings as? AppRunTypeProviding, runTypeProvider.runType == .integrationTests {
            Logger.dataBrokerProtection.log("Remote broker delivery not enabled due to run type")
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

            /// 2. Skip the update while any of our signing keys is revoked
            let keyRevocationChecker = BrokerBundleKeyRevocationChecker(privacyConfigurationManager: privacyConfigurationManager,
                                                                        settings: settings,
                                                                        signingKeys: signingKeys)
            if keyRevocationChecker.isAnyKeyRevoked {
                Logger.dataBrokerProtection.log("🧩 Broker bundle signing key revoked, skipping update")
                settings.updateLastSuccessfulBrokerJSONUpdateCheckTimestamp()
                throw BrokerBundleVerificationError.keyRevoked
            }

            /// 3. Use bundled JSONs to populate/update the database
            try? await localBrokerProvider?.checkForUpdates()

            /// 4. Hit main_config.json endpoint for ETag and active broker changes
            ///    Neither it nor its signature may come from the local cache, or they could be from different points in time
            var request = try Endpoint.request(for: .mainConfig,
                                               endpointURL: settings.endpointURL,
                                               contentType: "application/json",
                                               eTag: settings.mainConfigETag)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await urlSession.data(for: request)
            guard let response = response as? HTTPURLResponse else { return }

            if response.statusCode == 304 {
                Logger.dataBrokerProtection.log("🧩 Broker JSONs are up to date: main config eTag matches")
                settings.updateLastSuccessfulBrokerJSONUpdateCheckTimestamp()
                pixelHandler?.fire(.bundleVerificationSuccess)
                return
            }

            guard response.statusCode == 200, let newETag = response.etag else {
                throw Error.serverError(httpCode: response.statusCode)
            }

            /// 5. Verify the signature over the exact bytes received, then reject rollbacks
            let (mainConfig, signingKey) = try await verifiedMainConfig(from: data)

            /// 6. Download, extract, and process changed broker JSONs
            try await checkForBrokerJSONUpdatesFromMainConfig(mainConfig, eTag: newETag)

            /// 7. Update last successful update timestamp
            settings.lastManifestVersions[signingKey.id] = mainConfig.manifestVersion
            settings.mainConfigETag = newETag
            settings.updateLastSuccessfulBrokerJSONUpdateCheckTimestamp()
            pixelHandler?.fire(.bundleVerificationSuccess)
        } catch let error as BrokerBundleVerificationError {
            Logger.dataBrokerProtection.error("🧩 Broker bundle verification failed: \(error.rawValue, privacy: .public)")
            pixelHandler?.fire(.bundleVerificationFailure(reason: error))
            throw error
        } catch {
            pixelHandler?.fire(.miscError(error: error, functionOccurredIn: "RemoteBrokerJSONService checkForUpdates"))
            throw error
        }
    }

    private func verifiedMainConfig(from data: Data) async throws -> (MainConfig, BrokerBundleSigningKey) {
        let signature: Data?
        do {
            signature = try await fetchSignature()
        } catch {
            pixelHandler?.fire(.miscError(error: error, functionOccurredIn: "RemoteBrokerJSONService fetchSignature"))
            throw BrokerBundleVerificationError.other
        }

        let verifier = BrokerBundleVerifier(keys: signingKeys.keys(isProductionEndpoint: settings.isProductionEndpoint))
        let signingKey = try verifier.verifyingKey(manifest: data, signature: signature)

        let mainConfig: MainConfig
        do {
            mainConfig = try JSONDecoder().decode(MainConfig.self, from: data)
        } catch {
            pixelHandler?.fire(.miscError(error: error, functionOccurredIn: "RemoteBrokerJSONService decodeMainConfig"))
            throw BrokerBundleVerificationError.other
        }

        if let lastManifestVersion = settings.lastManifestVersions[signingKey.id],
           mainConfig.manifestVersion < lastManifestVersion {
            throw BrokerBundleVerificationError.rollback
        }

        return (mainConfig, signingKey)
    }

    private func fetchSignature() async throws -> Data? {
        var request = try Endpoint.request(for: .mainConfigSignature, endpointURL: settings.endpointURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await urlSession.data(for: request)

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:
            return data
        case 404:
            return nil
        case let statusCode:
            throw Error.serverError(httpCode: statusCode)
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

        let isFreeScan = !(await authenticationManager.isUserAuthenticated)

        defer { try? cleanUp(eTag: eTag) }
        try await downloadAndExtractBrokerJSONsIfNeeded(eTag: eTag)
        try processBrokerJSONs(eTag: eTag,
                               fileNames: diff.map(\.fileName),
                               eTagMapping: eTagMapping,
                               sha256Mapping: mainConfig.jsonSHA256,
                               activeBrokers: mainConfig.activeDataBrokers,
                               testBrokers: mainConfig.testDataBrokers,
                               isFreeScan: isFreeScan)
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
                let request = try Endpoint.request(for: .allBrokers,
                                                   endpointURL: settings.endpointURL)

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
                            sha256Mapping: [String: String],
                            activeBrokers: [String],
                            testBrokers: [String],
                            isFreeScan: Bool) throws {
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(eTag).appendingPathComponent("json", isDirectory: true)
        let fileURLs = try fileManager.contentsOfDirectory(at: directoryURL,
                                                           includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles])
        var hasDigestMismatch = false
        for fileURL in fileURLs {
            let fileName = fileURL.lastPathComponent
            guard changedBrokerFileNames.contains(fileName) else { continue }

            do {
                let data = try Data(contentsOf: fileURL)
                guard BrokerBundleVerifier.hasExpectedDigest(data, expectedSHA256: sha256Mapping[fileName]) else {
                    Logger.dataBrokerProtection.error("🧩 JSON file \(fileName, privacy: .public) doesn't match its SHA-256, skipping update")
                    hasDigestMismatch = true
                    continue
                }

                let brokerResource = try DataBroker.initFromData(data).with(eTag: eTagMapping[fileName] ?? "")
                if activeBrokers.contains(fileName) {
                    try upsertBroker(brokerResource)
                    pixelHandler?.fire(.updateDataBrokersSuccess(dataBrokerFileName: fileName, removedAt: brokerResource.broker.removedAtTimestamp, isFreeScan: isFreeScan))
                }
            } catch let error as DecodingError {
                Logger.dataBrokerProtection.log("🧩 Failed to decode JSON file \(fileURL.lastPathComponent): \(error), skipping update")
                pixelHandler?.fire(.updateDataBrokersFailure(dataBrokerFileName: fileName, removedAt: nil, isFreeScan: isFreeScan, error: error))
            } catch let error as Step.DecodingError {
                Logger.dataBrokerProtection.log("🧩 JSON file \(fileURL.lastPathComponent) contains unsupported data: \(error), skipping update")
                pixelHandler?.fire(.updateDataBrokersFailure(dataBrokerFileName: fileName, removedAt: nil, isFreeScan: isFreeScan, error: error))
            } catch {
                Logger.dataBrokerProtection.log("🧩 Failed to upsert broker \(fileName): \(error)")
                pixelHandler?.fire(.updateDataBrokersFailure(dataBrokerFileName: fileName, removedAt: nil, isFreeScan: isFreeScan, error: error))
                throw error
            }
        }

        if hasDigestMismatch {
            throw BrokerBundleVerificationError.digestMismatch
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
    let jsonSHA256: [String: String]
    let testDataBrokers: [String]
    let manifestVersion: Int

    struct JSONETagPayload: Codable {
        let current: [String: String]
    }

    enum CodingKeys: String, CodingKey {
        case mainConfigETag = "main_config_etag"
        case activeDataBrokers = "active_data_brokers"
        case jsonETags = "json_etags"
        case jsonSHA256 = "json_sha256"
        case testDataBrokers = "test_data_brokers"
        case manifestVersion = "manifest_version"
    }
}
