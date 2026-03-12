//
//  LocalBrokerJSONServiceTests.swift
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

import XCTest
import Foundation
import SecureStorage
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class LocalBrokerJSONServiceTests: XCTestCase {

    let repository = BrokerUpdaterRepositoryMock()
    let resources = ResourcesRepositoryMock()
    let pixelHandler = MockDataBrokerProtectionPixelsHandler()
    let runTypeProvider = MockAppRunTypeProvider()
    let vault: DataBrokerProtectionSecureVaultMock? = try? DataBrokerProtectionSecureVaultMock(providers:
                                                        SecureStorageProviders(
                                                            crypto: EmptySecureStorageCryptoProviderMock(),
                                                            database: SecureStorageDatabaseProviderMock(),
                                                            keystore: EmptySecureStorageKeyStoreProviderMock()))

    override func tearDown() {
        repository.reset()
        resources.reset()
        vault?.reset()
        pixelHandler.clear()
    }

    func testWhenNoVersionIsStored_thenWeTryToUpdateBrokers() async throws {
        if let vault = self.vault {
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
            repository.lastCheckedVersion = nil

            try await sut.checkForUpdates()

            XCTAssertTrue(repository.wasSaveLatestAppVersionCheckCalled)
            XCTAssertTrue(resources.wasFetchBrokerFromResourcesFilesCalled)
        } else {
            XCTFail("Mock vault issue")
        }
    }

    func testWhenVersionIsStoredAndPatchIsLessThanCurrentOne_thenWeTryToUpdateBrokers() async throws {
        if let vault = self.vault {
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, appVersion: MockAppVersion(versionNumber: "1.74.1"), pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
            repository.lastCheckedVersion = "1.74.0"

            try await sut.checkForUpdates()

            XCTAssertTrue(repository.wasSaveLatestAppVersionCheckCalled)
            XCTAssertTrue(resources.wasFetchBrokerFromResourcesFilesCalled)
        } else {
            XCTFail("Mock vault issue")
        }
    }

    func testWhenVersionIsStoredAndMinorIsLessThanCurrentOne_thenWeTryToUpdateBrokers() async throws {
        if let vault = self.vault {
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, appVersion: MockAppVersion(versionNumber: "1.74.0"), pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
            repository.lastCheckedVersion = "1.73.0"

            try await sut.checkForUpdates()

            XCTAssertTrue(repository.wasSaveLatestAppVersionCheckCalled)
            XCTAssertTrue(resources.wasFetchBrokerFromResourcesFilesCalled)
        } else {
            XCTFail("Mock vault issue")
        }
    }

    func testWhenVersionIsStoredAndMajorIsLessThanCurrentOne_thenWeTryToUpdateBrokers() async throws {
        if let vault = self.vault {
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, appVersion: MockAppVersion(versionNumber: "1.74.0"), pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
            repository.lastCheckedVersion = "0.74.0"

            try await sut.checkForUpdates()

            XCTAssertTrue(repository.wasSaveLatestAppVersionCheckCalled)
            XCTAssertTrue(resources.wasFetchBrokerFromResourcesFilesCalled)
        } else {
            XCTFail("Mock vault issue")
        }
    }

    func testWhenVersionIsStoredAndIsEqualOrGreaterThanCurrentOne_thenCheckingUpdatesIsSkipped() async throws {
        if let vault = self.vault {
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, appVersion: MockAppVersion(versionNumber: "1.74.0"), pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
            repository.lastCheckedVersion = "1.74.0"

            try await sut.checkForUpdates()

            XCTAssertFalse(repository.wasSaveLatestAppVersionCheckCalled)
            XCTAssertFalse(resources.wasFetchBrokerFromResourcesFilesCalled)
        } else {
            XCTFail("Mock vault issue")
        }
    }

    func testWhenSavedBrokerIsOnAnOldVersion_thenWeUpdateIt() async throws {
        if let vault = self.vault {
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
            repository.lastCheckedVersion = nil
            let expectedBrokerResource = try brokerResource(fileName: "valid-broker-1.0.1")
            resources.brokerResourcesList = [expectedBrokerResource]
            vault.shouldReturnOldVersionBroker = true

            try await sut.checkForUpdates()

            XCTAssertTrue(repository.wasSaveLatestAppVersionCheckCalled)
            XCTAssertTrue(resources.wasFetchBrokerFromResourcesFilesCalled)
            XCTAssertTrue(vault.wasBrokerUpdateCalled)
            XCTAssertFalse(vault.wasBrokerSavedCalled)

            let updatedBrokerResource = try XCTUnwrap(vault.lastUpdatedBrokerResource)
            XCTAssertEqual(updatedBrokerResource.rawJSON, expectedBrokerResource.rawJSON)
            let updatedPayload = try jsonObject(from: updatedBrokerResource.rawJSON)
            XCTAssertEqual((updatedPayload["addedDatetime"] as? NSNumber)?.int64Value, 1725632531153)
        } else {
            XCTFail("Mock vault issue")
        }
    }

    func testWhenSavedBrokerIsOnTheCurrentVersion_thenWeDoNotUpdateIt() async throws {
        if let vault = self.vault {
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
            repository.lastCheckedVersion = nil
            resources.brokerResourcesList = [try brokerResource(fileName: "valid-broker-1.0.1")]
            vault.shouldReturnNewVersionBroker = true

            try await sut.checkForUpdates()

            XCTAssertTrue(repository.wasSaveLatestAppVersionCheckCalled)
            XCTAssertTrue(resources.wasFetchBrokerFromResourcesFilesCalled)
            XCTAssertFalse(vault.wasBrokerUpdateCalled)
        } else {
            XCTFail("Mock vault issue")
        }
    }

    func testWhenFileBrokerIsNotStored_thenWeAddTheBrokerAndScanOperations() async throws {
        if let vault = self.vault {
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
            repository.lastCheckedVersion = nil
            let expectedBrokerResource = try brokerResource(fileName: "valid-broker")
            resources.brokerResourcesList = [expectedBrokerResource]
            vault.profileQueries = [.mock]

            try await sut.checkForUpdates()

            XCTAssertTrue(repository.wasSaveLatestAppVersionCheckCalled)
            XCTAssertTrue(resources.wasFetchBrokerFromResourcesFilesCalled)
            XCTAssertFalse(vault.wasBrokerUpdateCalled)
            XCTAssertTrue(vault.wasBrokerSavedCalled)

            let savedBrokerResource = try XCTUnwrap(vault.lastSavedBrokerResource)
            XCTAssertEqual(savedBrokerResource.rawJSON, expectedBrokerResource.rawJSON)
            let savedPayload = try jsonObject(from: savedBrokerResource.rawJSON)
            XCTAssertEqual((savedPayload["addedDatetime"] as? NSNumber)?.int64Value, 1725632531153)

            XCTAssertTrue(areDatesEqualIgnoringSeconds(
                date1: Date(),
                date2: vault.lastPreferredRunDateOnScan)
            )
        } else {
            XCTFail("Mock vault issue")
        }
    }

    func testWhenBrokerUpdateSucceeds_thenSuccessPixelIsFired() async throws {
        guard let vault = self.vault else {
            XCTFail("Mock vault issue")
            return
        }

        let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
        repository.lastCheckedVersion = nil
        resources.brokerResourcesList = [try brokerResource(fileName: "valid-broker")]
        vault.profileQueries = [.mock]

        try await sut.checkForUpdates()

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let successPixels = firedPixels.compactMap { pixel in
            switch pixel {
            case .updateDataBrokersSuccess(let dataBrokerFileName, let removedAt, _):
                return (dataBrokerFileName, removedAt)
            default:
                return nil
            }
        }

        XCTAssertFalse(successPixels.isEmpty, "updateDataBrokersSuccess pixel should be fired")
        let (dataBroker, removedAt) = successPixels.first!
        XCTAssertEqual(dataBroker, "fakebroker.com.json")
        XCTAssertNil(removedAt, "removedAt should be nil for broker without removal date")
    }

    func testWhenBrokerWithRemovedAtUpdateSucceeds_thenSuccessPixelIsFiredWithTimestamp() async throws {
        guard let vault = self.vault else {
            XCTFail("Mock vault issue")
            return
        }

        let expectedTimestamp: Int64 = 1693526400000

        let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
        repository.lastCheckedVersion = nil
        resources.brokerResourcesList = [try brokerResource(fileName: "valid-broker-removed-1.0.1")]
        vault.profileQueries = [.mock]

        try await sut.checkForUpdates()

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let successPixels = firedPixels.compactMap { pixel in
            switch pixel {
            case .updateDataBrokersSuccess(let dataBrokerFileName, let removedAt, _):
                return (dataBrokerFileName, removedAt)
            default:
                return nil
            }
        }

        XCTAssertFalse(successPixels.isEmpty, "updateDataBrokersSuccess pixel should be fired")
        let (dataBroker, removedAt) = successPixels.first!
        XCTAssertEqual(dataBroker, "fakebroker.com.json")
        XCTAssertEqual(removedAt, expectedTimestamp, "removedAt should be converted to milliseconds timestamp")
    }

    func testWhenBrokerUpdateFails_thenFailurePixelIsFired() async throws {
        guard let vault = self.vault else {
            XCTFail("Mock vault issue")
            return
        }

        let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
        repository.lastCheckedVersion = nil
        resources.brokerResourcesList = [try brokerResource(fileName: "valid-broker-1.0.1")] // Newer than mock's "1.0.0" to trigger update
        vault.profileQueries = [.mock]
        vault.shouldReturnOldVersionBroker = true // Ensure broker exists so update path is taken  
        vault.shouldThrowOnUpdate = true // Force update to fail

        try await sut.checkForUpdates()

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let failurePixels = firedPixels.compactMap { pixel in
            switch pixel {
            case .updateDataBrokersFailure(let dataBrokerFileName, let removedAt, _, _):
                return (dataBrokerFileName, removedAt)
            default:
                return nil
            }
        }

        XCTAssertFalse(failurePixels.isEmpty, "updateDataBrokersFailure pixel should be fired")
        let (dataBroker, removedAt) = failurePixels.first!
        XCTAssertEqual(dataBroker, "fakebroker.com.json")
        XCTAssertNil(removedAt, "removedAt should be nil for broker without removal date")
    }

    func testWhenResourcesFetchFails_thenOldCocoaErrorPixelIsFired() async throws {
        // This test verifies we didn't change the behavior for resource fetch failures
        guard let vault = self.vault else {
            XCTFail("Mock vault issue")
            return
        }

        let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
        repository.lastCheckedVersion = nil
        resources.shouldThrowOnFetch = true // Force fetch to fail

        try await sut.checkForUpdates()

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let cocoaErrorPixels = firedPixels.filter { pixel in
            switch pixel {
            case .cocoaError:
                return true
            default:
                return false
            }
        }

        XCTAssertFalse(cocoaErrorPixels.isEmpty, "cocoaError pixel should still be fired for resource fetch failures")
    }

    func testWhenUserIsAuthenticated_thenBrokerUpdatePixelsIncludeFreeScanFalse() async throws {
        guard let vault = self.vault else {
            XCTFail("Mock vault issue")
            return
        }

        let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { true })
        repository.lastCheckedVersion = nil
        let broker = DataBroker(id: 1,
                                name: "Broker",
                                url: "broker.com",
                                steps: [Step](),
                                version: "1.0.0",
                                schedulingConfig: .mock,
                                optOutUrl: "",
                                eTag: "",
                                removedAt: nil)
        resources.brokerResourcesList = [BrokerResource(broker: broker, rawJSON: Data())]
        vault.profileQueries = [.mock]

        try await sut.checkForUpdates()

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        XCTAssertFalse(firedPixels.isEmpty)
        for pixel in firedPixels where pixel.name.contains("update_databrokers") {
            XCTAssertEqual(pixel.parameters?["free_scan"], "false", "Expected free_scan=false for authenticated user on pixel \(pixel.name)")
        }
    }

    func testWhenUserIsNotAuthenticated_thenBrokerUpdatePixelsIncludeFreeScanTrue() async throws {
        guard let vault = self.vault else {
            XCTFail("Mock vault issue")
            return
        }

        let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler, runTypeProvider: runTypeProvider, isAuthenticatedUser: { false })
        repository.lastCheckedVersion = nil
        let broker = DataBroker(id: 1,
                                name: "Broker",
                                url: "broker.com",
                                steps: [Step](),
                                version: "1.0.0",
                                schedulingConfig: .mock,
                                optOutUrl: "",
                                eTag: "",
                                removedAt: nil)
        resources.brokerResourcesList = [BrokerResource(broker: broker, rawJSON: Data())]
        vault.profileQueries = [.mock]

        try await sut.checkForUpdates()

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        XCTAssertFalse(firedPixels.isEmpty)
        for pixel in firedPixels where pixel.name.contains("update_databrokers") {
            XCTAssertEqual(pixel.parameters?["free_scan"], "true", "Expected free_scan=true for unauthenticated user on pixel \(pixel.name)")
        }
    }

    private func brokerResource(fileName: String) throws -> BrokerResource {
        let fileURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: fileName,
                withExtension: "json",
                subdirectory: "BundleResources"
            )
        )
        return try DataBroker.initFromResource(fileURL)
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

}
