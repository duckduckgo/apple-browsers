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
    let vault: DataBrokerProtectionSecureVaultMock? = try? DataBrokerProtectionSecureVaultMock(providers:
                                                        SecureStorageProviders(
                                                            crypto: EmptySecureStorageCryptoProviderMock(),
                                                            database: SecureStorageDatabaseProviderMock(),
                                                            keystore: EmptySecureStorageKeyStoreProviderMock()))

    override func tearDown() {
        repository.reset()
        resources.reset()
        vault?.reset()
    }

    func testWhenNoVersionIsStored_thenWeTryToUpdateBrokers() async throws {
        if let vault = self.vault {
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler)
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
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, appVersion: MockAppVersion(versionNumber: "1.74.1"), pixelHandler: pixelHandler)
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
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, appVersion: MockAppVersion(versionNumber: "1.74.0"), pixelHandler: pixelHandler)
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
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, appVersion: MockAppVersion(versionNumber: "1.74.0"), pixelHandler: pixelHandler)
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
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, appVersion: MockAppVersion(versionNumber: "1.74.0"), pixelHandler: pixelHandler)
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
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler)
            repository.lastCheckedVersion = nil
            resources.brokersList = [.init(id: 1, name: "Broker", url: "broker.com", steps: [Step](), version: "1.0.1", schedulingConfig: .mock, optOutUrl: "", eTag: "")]
            vault.shouldReturnOldVersionBroker = true

            try await sut.checkForUpdates()

            XCTAssertTrue(repository.wasSaveLatestAppVersionCheckCalled)
            XCTAssertTrue(resources.wasFetchBrokerFromResourcesFilesCalled)
            XCTAssertTrue(vault.wasBrokerUpdateCalled)
            XCTAssertFalse(vault.wasBrokerSavedCalled)
        } else {
            XCTFail("Mock vault issue")
        }
    }

    func testWhenSavedBrokerIsOnTheCurrentVersion_thenWeDoNotUpdateIt() async throws {
        if let vault = self.vault {
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler)
            repository.lastCheckedVersion = nil
            resources.brokersList = [.init(id: 1, name: "Broker", url: "broker.com", steps: [Step](), version: "1.0.1", schedulingConfig: .mock, optOutUrl: "", eTag: "")]
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
            let sut = LocalBrokerJSONService(repository: repository, resources: resources, vault: vault, pixelHandler: pixelHandler)
            repository.lastCheckedVersion = nil
            resources.brokersList = [.init(id: 1, name: "Broker", url: "broker.com", steps: [Step](), version: "1.0.0", schedulingConfig: .mock, optOutUrl: "", eTag: "")]
            vault.profileQueries = [.mock]

            try await sut.checkForUpdates()

            XCTAssertTrue(repository.wasSaveLatestAppVersionCheckCalled)
            XCTAssertTrue(resources.wasFetchBrokerFromResourcesFilesCalled)
            XCTAssertFalse(vault.wasBrokerUpdateCalled)
            XCTAssertTrue(vault.wasBrokerSavedCalled)
            XCTAssertTrue(areDatesEqualIgnoringSeconds(
                date1: Date(),
                date2: vault.lastPreferredRunDateOnScan)
            )
        } else {
            XCTFail("Mock vault issue")
        }
    }

}
