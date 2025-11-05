//
//  LocalBrokerJSONService.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common
import SecureStorage
import os.log

public protocol ResourcesRepository {
    func fetchBrokerFromResourceFiles() throws -> [DataBroker]?
}

public final class FileResources: ResourcesRepository {

    enum FileResourcesError: Error {
        case bundleResourceURLNil
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fetchBrokerFromResourceFiles() throws -> [DataBroker]? {
        guard AppVersion.runType != .unitTests && AppVersion.runType != .uiTests else {
            /*
             There's a bug with the bundle resources in tests:
             https://forums.swift.org/t/swift-5-3-swiftpm-resources-in-tests-uses-wrong-bundle-path/37051/49
             */
            return []
        }

        guard let resourceURL = Bundle.module.resourceURL else {
            Logger.dataBrokerProtection.fault("🧩 LocalBrokerJSONService: error FileResources fetchBrokerFromResourceFiles, error: Bundle.module.resourceURL is nil")
            assertionFailure()
            throw FileResourcesError.bundleResourceURLNil
        }

        let shouldUseFakeBrokers = (AppVersion.runType == .integrationTests)
        let brokersURL = resourceURL.appendingPathComponent("BundleResources").appendingPathComponent("JSON")
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: brokersURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            let brokerJSONFiles = fileURLs.filter {
                $0.isJSON && (
                (shouldUseFakeBrokers && $0.hasFakePrefix) ||
                (!shouldUseFakeBrokers && !$0.hasFakePrefix))
            }

            return try brokerJSONFiles.map(DataBroker.initFromResource(_:))
        } catch let error as DecodingError {
            assertionFailure("Failed to decode bundled JSON: \(error.localizedDescription)")
            return nil
        } catch let error as Step.DecodingError {
            assertionFailure("Bundled JSON containing unsupported data: \(error.localizedDescription)")
            return nil
        } catch {
            Logger.dataBrokerProtection.error("🧩 LocalBrokerJSONService: error FileResources error: fetchBrokerFromResourceFiles, error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

public protocol BrokerUpdaterRepository {

    func saveLatestAppVersionCheck(version: String)
    func getLastCheckedVersion() -> String?
}

public final class BrokerUpdaterUserDefaults: BrokerUpdaterRepository {

    struct Consts {
        static let shouldCheckForUpdatesKey = "macos.browser.data-broker-protection.LastLocalVersionChecked"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func saveLatestAppVersionCheck(version: String) {
        UserDefaults.standard.set(version, forKey: Consts.shouldCheckForUpdatesKey)
    }

    public func getLastCheckedVersion() -> String? {
        UserDefaults.standard.string(forKey: Consts.shouldCheckForUpdatesKey)
    }
}

public protocol AppVersionNumberProvider {
    var versionNumber: String { get }
}

public final class AppVersionNumber: AppVersionNumberProvider {

    public var versionNumber: String = AppVersion.shared.versionNumber

    public init() {
    }
}

public struct LocalBrokerJSONService: BrokerJSONFallbackProvider {
    private let repository: BrokerUpdaterRepository
    private let resources: ResourcesRepository
    public let vault: any DataBrokerProtectionSecureVault
    private let appVersion: AppVersionNumberProvider
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>

    public init(repository: BrokerUpdaterRepository = BrokerUpdaterUserDefaults(),
                resources: ResourcesRepository = FileResources(),
                vault: any DataBrokerProtectionSecureVault,
                appVersion: AppVersionNumberProvider = AppVersionNumber(),
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>) {
        self.repository = repository
        self.resources = resources
        self.vault = vault
        self.appVersion = appVersion
        self.pixelHandler = pixelHandler
    }

    public func updateBrokers() {
        let brokers: [DataBroker]?
        do {
            brokers = try resources.fetchBrokerFromResourceFiles()
        } catch {
            Logger.dataBrokerProtection.error("🧩 FallbackBrokerJSONService updateBrokers, error: \(error.localizedDescription, privacy: .public)")
            pixelHandler.fire(.cocoaError(error: error, functionOccurredIn: "DataBrokerProtectionBrokerUpdater.updateBrokers"))
            return
        }
        guard let brokers = brokers else { return }

        for broker in brokers {
            do {
                try upsertBroker(broker)
                let brokerFileName = "\(broker.url).json"
                pixelHandler.fire(.updateDataBrokersSuccess(dataBrokerFileName: brokerFileName, removedAt: broker.removedAtTimestamp))
            } catch {
                Logger.dataBrokerProtection.log("🧩 Error updating broker: \(broker.name, privacy: .public), with version: \(broker.version, privacy: .public)")
                let brokerFileName = "\(broker.url).json"
                pixelHandler.fire(.updateDataBrokersFailure(dataBrokerFileName: brokerFileName, removedAt: broker.removedAtTimestamp, error: error))
            }
        }
    }

    public func bundledBrokers() throws -> [DataBroker]? {
        try resources.fetchBrokerFromResourceFiles()
    }

    public func checkForUpdates() async throws {
        if let lastCheckedVersion = repository.getLastCheckedVersion() {
            if Self.shouldUpdate(incoming: appVersion.versionNumber, storedVersion: lastCheckedVersion) {
                updateBrokersAndSaveLatestVersion()
            }
        } else {
            // There was not a last checked version. Probably new builds or ones without this new implementation
            // or user deleted user defaults.
            updateBrokersAndSaveLatestVersion()
        }
    }

    private func updateBrokersAndSaveLatestVersion() {
        repository.saveLatestAppVersionCheck(version: appVersion.versionNumber)
        updateBrokers()
    }
}

fileprivate extension URL {

    var isJSON: Bool {
        self.pathExtension.lowercased() == "json"
    }

    var hasFakePrefix: Bool {
        self.lastPathComponent.lowercased().hasPrefix("fake")
    }
}
