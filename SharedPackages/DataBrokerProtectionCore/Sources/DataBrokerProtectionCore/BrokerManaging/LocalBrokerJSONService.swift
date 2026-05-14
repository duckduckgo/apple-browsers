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
    func fetchBrokerResourcesFromFiles() throws -> [BrokerResource]?
}

public final class FileResources: ResourcesRepository {

    enum FileResourcesError: Error {
        case bundleResourceURLNil
    }

    private let fileManager: FileManager
    private let runTypeProvider: AppRunTypeProviding

    public init(fileManager: FileManager = .default, runTypeProvider: AppRunTypeProviding) {
        self.fileManager = fileManager
        self.runTypeProvider = runTypeProvider
    }

    public func fetchBrokerResourcesFromFiles() throws -> [BrokerResource]? {
        guard AppVersion.runType != .unitTests && AppVersion.runType != .uiTests else {
            /*
             There's a bug with the bundle resources in tests:
             https://forums.swift.org/t/swift-5-3-swiftpm-resources-in-tests-uses-wrong-bundle-path/37051/49
             */
            Logger.dataBrokerProtection.fault("🧩 LocalBrokerJSONService: Unsupported runtime, returning empty brokers array")
            return []
        }

        guard let resourceURL = Bundle.module.resourceURL else {
            Logger.dataBrokerProtection.fault("🧩 LocalBrokerJSONService: error FileResources fetchBrokerFromResourceFiles, error: Bundle.module.resourceURL is nil")
            assertionFailure()
            throw FileResourcesError.bundleResourceURLNil
        }

        let runType = runTypeProvider.runType
        let shouldUseFakeBrokers = (runType == .integrationTests || runType == .uiTests)

        Logger.dataBrokerProtection.fault("🧩 LocalBrokerJSONService: Using fake brokers = \(shouldUseFakeBrokers, privacy: .public)")

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
    private let runTypeProvider: AppRunTypeProviding
    private let isAuthenticatedUser: () async -> Bool

    public init(repository: BrokerUpdaterRepository = BrokerUpdaterUserDefaults(),
                resources: ResourcesRepository,
                vault: any DataBrokerProtectionSecureVault,
                appVersion: AppVersionNumberProvider = AppVersionNumber(),
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                runTypeProvider: AppRunTypeProviding,
                isAuthenticatedUser: @escaping () async -> Bool) {
        self.repository = repository
        self.resources = resources
        self.vault = vault
        self.appVersion = appVersion
        self.pixelHandler = pixelHandler
        self.runTypeProvider = runTypeProvider
        self.isAuthenticatedUser = isAuthenticatedUser
    }

    public func bundledBrokers() throws -> [BrokerResource]? {
        try resources.fetchBrokerResourcesFromFiles()
    }

    public func checkForUpdates() async throws {
        let isFreeScan = !(await isAuthenticatedUser())
        if let lastCheckedVersion = repository.getLastCheckedVersion() {
            if Self.shouldUpdate(incoming: appVersion.versionNumber, storedVersion: lastCheckedVersion) {
                updateBrokersAndSaveLatestVersion(isFreeScan: isFreeScan)
            }
        } else {
            // There was not a last checked version. Probably new builds or ones without this new implementation
            // or user deleted user defaults.
            updateBrokersAndSaveLatestVersion(isFreeScan: isFreeScan)
        }
    }

    private func updateBrokersAndSaveLatestVersion(isFreeScan: Bool) {
        repository.saveLatestAppVersionCheck(version: appVersion.versionNumber)
        updateBrokers(isFreeScan: isFreeScan)
    }

    private func updateBrokers(isFreeScan: Bool?) {
        guard runTypeProvider.runType != .integrationTests else {
            Logger.dataBrokerProtection.error("🧩 LocalBrokerJSONService updateBrokers skipping due to running integration tests")
            return
        }

        Logger.dataBrokerProtection.error("🧩 LocalBrokerJSONService updateBrokers beginning")

        let brokerResources: [BrokerResource]?
        do {
            brokerResources = try resources.fetchBrokerResourcesFromFiles()
        } catch {
            Logger.dataBrokerProtection.error("🧩 FallbackBrokerJSONService updateBrokers, error: \(error.localizedDescription, privacy: .public)")
            pixelHandler.fire(.cocoaError(error: error, functionOccurredIn: "DataBrokerProtectionBrokerUpdater.updateBrokers"))
            return
        }
        guard let brokerResources = brokerResources else { return }

        for brokerResource in brokerResources {
            do {
                try upsertBroker(brokerResource)
                let brokerFileName = "\(brokerResource.broker.url).json"
                pixelHandler.fire(.updateDataBrokersSuccess(dataBrokerFileName: brokerFileName, removedAt: brokerResource.broker.removedAtTimestamp, isFreeScan: isFreeScan))
            } catch {
                let broker = brokerResource.broker
                let brokerFileName = "\(broker.url).json"
                Logger.dataBrokerProtection.log("🧩 Error updating broker: \(broker.name, privacy: .public), with version: \(broker.version, privacy: .public)")
                pixelHandler.fire(.updateDataBrokersFailure(dataBrokerFileName: brokerFileName, removedAt: broker.removedAtTimestamp, isFreeScan: isFreeScan, error: error))
            }
        }
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
