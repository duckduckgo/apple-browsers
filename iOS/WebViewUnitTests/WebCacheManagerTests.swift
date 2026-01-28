//
//  WebCacheManagerTests.swift
//  UnitTests
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
@testable import Core
import WebKit
import PersistenceTestingUtils
import BrowserServicesKitTestsUtils
import WKAbstractions

@MainActor
class WebCacheManagerTests: XCTestCase {

    let keyValueStore = MockKeyValueStore()

    lazy var cookieStorage = MigratableCookieStorage(store: keyValueStore)
    lazy var fireproofing = MockFireproofing()
    lazy var dataStoreIDManager = DataStoreIDManager(store: keyValueStore)
    let dataStoreCleaner = MockDataStoreCleaner()
    let observationsCleaner = MockObservationsCleaner()

    func test_whenClearingData_ThenCookiesAreRemoved() async {
        let cookieStore = MockHTTPCookieStore(allCookiesReturnValue: [
            .make(name: "Test1", value: "Value", domain: "example.com"),
            .make(name: "Test2", value: "Value", domain: ".example.com"),
            .make(name: "Test3", value: "Value", domain: "facebook.com")
        ])
        let dataStore = MockWebsiteDataStore(httpCookieStore: cookieStore)

        let webCacheManager = makeWebCacheManager()
        await webCacheManager.clear(dataStore: dataStore)

        XCTAssertEqual(3, cookieStore.cookiesThatWereDeleted.count)
        XCTAssertEqual("Test1", cookieStore.cookiesThatWereDeleted[0].name)
        XCTAssertEqual("Test2", cookieStore.cookiesThatWereDeleted[1].name)
        XCTAssertEqual("Test3", cookieStore.cookiesThatWereDeleted[2].name)
    }

    func test_WhenClearingDefaultPersistence_ThenLeaveFireproofedCookies() async {
        fireproofing = MockFireproofing(domains: ["example.com"])
        let cookieStore = MockHTTPCookieStore(allCookiesReturnValue: [
            .make(name: "Test1", value: "Value", domain: "example.com"),
            .make(name: "Test2", value: "Value", domain: ".example.com"),
            .make(name: "Test3", value: "Value", domain: "facebook.com")
        ])
        let dataStore = MockWebsiteDataStore(httpCookieStore: cookieStore)

        let webCacheManager = makeWebCacheManager()
        await webCacheManager.clear(dataStore: dataStore)

        XCTAssertEqual(1, cookieStore.cookiesThatWereDeleted.count)
        XCTAssertEqual("Test3", cookieStore.cookiesThatWereDeleted[0].name)
    }

    func test_WhenClearingData_ThenObservationsDatabaseIsCleared() async {
        XCTAssertEqual(0, observationsCleaner.removeObservationsDataCallCount)
        await makeWebCacheManager().clear(dataStore: MockWebsiteDataStore())
        XCTAssertEqual(1, observationsCleaner.removeObservationsDataCallCount)
    }

     func test_WhenClearingDataAfterUsingContainer_ThenCookiesAreMigratedAndOldContainersAreRemoved() async {
         // Mock having a single container so we can validate cleaning it gets called
         dataStoreCleaner.countContainersReturnValue = 1

         // Mock a data store id to force migration to happen
         keyValueStore.store = [DataStoreIDManager.Constants.currentWebContainerID.rawValue: UUID().uuidString]
         dataStoreIDManager = DataStoreIDManager(store: keyValueStore)

         fireproofing = MockFireproofing(domains: ["example.com"])

         MigratableCookieStorage.addCookies([
             .make(name: "Test1", value: "Value", domain: "example.com"),
             .make(name: "Test2", value: "Value", domain: ".example.com"),
             .make(name: "Test3", value: "Value", domain: "facebook.com"),
         ], keyValueStore)

         let mockCookieStore = MockHTTPCookieStore()
         let dataStore = MockWebsiteDataStore(httpCookieStore: mockCookieStore)

         let webCacheManager = makeWebCacheManager()
         await webCacheManager.clear(dataStore: dataStore)

         // All three actually get set as part of the migration
         XCTAssertEqual(3, mockCookieStore.cookiesThatWereSet.count)

         // But then we remove the ones that are not fireproofed (that is tested explicit in the test above)
         XCTAssertEqual(1, dataStore.removedDataOfTypesModifiedSince.count)
         XCTAssertEqual(1, dataStore.removedDataOfTypesForRecords.count)

         // And then check the containers are claned up
         XCTAssertEqual(1, dataStoreCleaner.removeAllContainersAfterDelayCalls.count)
         XCTAssertEqual(1, dataStoreCleaner.removeAllContainersAfterDelayCalls[0])
    }

    func test_WhenClearingData_ThenOldContainersAreRemoved() async {
        // Mock existence of 5 containers so we can validate that cleaning it is called even without migrations
        dataStoreCleaner.countContainersReturnValue = 5
        await makeWebCacheManager().clear(dataStore: MockWebsiteDataStore())
        XCTAssertEqual(1, dataStoreCleaner.removeAllContainersAfterDelayCalls.count)
        XCTAssertEqual(5, dataStoreCleaner.removeAllContainersAfterDelayCalls[0])
    }

    func test_WhenCookiesAreFromPreviousAppWithContainers_ThenTheyAreConsumed() async {
        MigratableCookieStorage.addCookies([
        .make(name: "Test1", value: "Value", domain: "example.com"),
        .make(name: "Test2", value: "Value", domain: ".example.com"),
        .make(name: "Test3", value: "Value", domain: "facebook.com"),
        ], keyValueStore)

        keyValueStore.set(false, forKey: MigratableCookieStorage.Keys.consumed)

        cookieStorage = MigratableCookieStorage(store: keyValueStore)

        // let dataStore = await WKWebsiteDataStore.default()
        let httpCookieStore = MockHTTPCookieStore()
        await makeWebCacheManager().consumeCookies(into: httpCookieStore)

        XCTAssertTrue(self.cookieStorage.isConsumed)
        XCTAssertTrue(self.cookieStorage.cookies.isEmpty)

        XCTAssertEqual(3, httpCookieStore.cookiesThatWereSet.count)
    }

    func test_WhenRemoveCookiesForDomains_ThenUnaffectedLeftBehind() async {
        let mockHttpCookieStore = MockHTTPCookieStore(allCookiesReturnValue: [
            .make(name: "Test1", value: "Value", domain: "example.com"),
            .make(name: "Test4", value: "Value", domain: "sample.com"),
            .make(name: "Test2", value: "Value", domain: ".example.com"),
            .make(name: "Test3", value: "Value", domain: "facebook.com"),
        ])
        let dataStore = MockWebsiteDataStore(httpCookieStore: mockHttpCookieStore)

        let cookies = await dataStore.httpCookieStore.allCookies()
        XCTAssertEqual(4, cookies.count)

        let webCacheManager = makeWebCacheManager()
        await webCacheManager.removeCookies(forDomains: ["example.com", "sample.com"], fromDataStore: dataStore)

        XCTAssertEqual(3, mockHttpCookieStore.cookiesThatWereDeleted.count)
    }

    // MARK: - Domain-Specific Clearing Tests

    func test_WhenClearingForDomains_ThenOnlySpecifiedDomainsAreCleared() async {
        let mockCookieStore = MockHTTPCookieStore(allCookiesReturnValue: [
            .make(name: "Cookie1", value: "Value", domain: "example.com"),
            .make(name: "Cookie2", value: "Value", domain: "other.com"),
            .make(name: "Cookie3", value: "Value", domain: "facebook.com"),
        ])
        let dataStore = MockWebsiteDataStore(
            httpCookieStore: mockCookieStore,
            dataRecordsOfTypesReturnValue: [
                MockWebsiteDataRecord(displayName: "example.com"),
                MockWebsiteDataRecord(displayName: "other.com"),
                MockWebsiteDataRecord(displayName: "facebook.com"),
            ]
        )

        let webCacheManager = makeWebCacheManager()
        await webCacheManager.clear(dataStore: dataStore, forDomains: ["example.com", "facebook.com"])

        // Verify data records were removed for specified domains only
        XCTAssertEqual(1, dataStore.removedDataOfTypesForRecords.count)
        let removedRecords = dataStore.removedDataOfTypesForRecords[0].records
        XCTAssertEqual(2, removedRecords.count)
        XCTAssertTrue(removedRecords.contains { $0.displayName == "example.com" })
        XCTAssertTrue(removedRecords.contains { $0.displayName == "facebook.com" })
        XCTAssertFalse(removedRecords.contains { $0.displayName == "other.com" })

        // Verify cookies were removed for specified domains only
        XCTAssertEqual(2, mockCookieStore.cookiesThatWereDeleted.count)
        XCTAssertTrue(mockCookieStore.cookiesThatWereDeleted.contains { $0.name == "Cookie1" })
        XCTAssertTrue(mockCookieStore.cookiesThatWereDeleted.contains { $0.name == "Cookie3" })
        XCTAssertFalse(mockCookieStore.cookiesThatWereDeleted.contains { $0.name == "Cookie2" })
    }

    func test_WhenClearingForDomains_ThenFireproofedDomainsAreNotCleared() async {
        fireproofing = MockFireproofing(domains: ["example.com"])
        let mockCookieStore = MockHTTPCookieStore(allCookiesReturnValue: [
            .make(name: "Cookie1", value: "Value", domain: "example.com"),
            .make(name: "Cookie2", value: "Value", domain: "facebook.com"),
        ])
        let dataStore = MockWebsiteDataStore(
            httpCookieStore: mockCookieStore,
            dataRecordsOfTypesReturnValue: [
                MockWebsiteDataRecord(displayName: "example.com"),
                MockWebsiteDataRecord(displayName: "facebook.com"),
            ]
        )

        let webCacheManager = makeWebCacheManager()
        await webCacheManager.clear(dataStore: dataStore, forDomains: ["example.com", "facebook.com"])

        // Verify only non-fireproofed domain data records were removed
        XCTAssertEqual(1, dataStore.removedDataOfTypesForRecords.count)
        let removedRecords = dataStore.removedDataOfTypesForRecords[0].records
        XCTAssertEqual(1, removedRecords.count)
        XCTAssertEqual("facebook.com", removedRecords[0].displayName)

        // Verify only non-fireproofed domain cookies were removed
        XCTAssertEqual(1, mockCookieStore.cookiesThatWereDeleted.count)
        XCTAssertEqual("Cookie2", mockCookieStore.cookiesThatWereDeleted[0].name)
    }

    func test_WhenClearingForDomains_WithDotPrefixedCookies_ThenMatchingCookiesAreCleared() async {
        let mockCookieStore = MockHTTPCookieStore(allCookiesReturnValue: [
            .make(name: "Cookie1", value: "Value", domain: "example.com"),
            .make(name: "Cookie2", value: "Value", domain: ".example.com"),
            .make(name: "Cookie3", value: "Value", domain: ".test.com"),
            .make(name: "Cookie4", value: "Value", domain: "other.com"),
        ])
        let dataStore = MockWebsiteDataStore(
            httpCookieStore: mockCookieStore,
            dataRecordsOfTypesReturnValue: [
                MockWebsiteDataRecord(displayName: "example.com"),
            ]
        )

        let webCacheManager = makeWebCacheManager()
        await webCacheManager.clear(dataStore: dataStore, forDomains: ["example.com", "sub.test.com"])

        // Verify cookies for exact domain and dot-prefixed domain were removed
        // Note: sub.example.com is a distinct host and not matched when clearing example.com
        XCTAssertEqual(3, mockCookieStore.cookiesThatWereDeleted.count)
        XCTAssertTrue(mockCookieStore.cookiesThatWereDeleted.contains { $0.name == "Cookie1" })
        XCTAssertTrue(mockCookieStore.cookiesThatWereDeleted.contains { $0.name == "Cookie2" })
        XCTAssertTrue(mockCookieStore.cookiesThatWereDeleted.contains { $0.name == "Cookie3" })
        XCTAssertFalse(mockCookieStore.cookiesThatWereDeleted.contains { $0.name == "Cookie4" })
    }

    @MainActor
    private func makeWebCacheManager() -> WebCacheManager {
        return WebCacheManager(
            cookieStorage: cookieStorage,
            fireproofing: fireproofing,
            dataStoreIDManager: dataStoreIDManager,
            dataStoreCleaner: dataStoreCleaner,
            observationsCleaner: observationsCleaner
        )
    }
}


class MockDataStoreCleaner: WebsiteDataStoreCleaning {

    var countContainersReturnValue = 0
    var removeAllContainersAfterDelayCalls: [Int] = []

    func countContainers() async -> Int {
        return countContainersReturnValue
    }
    
    func removeAllContainersAfterDelay(previousCount: Int) {
        removeAllContainersAfterDelayCalls.append(previousCount)
    }

}

class MockObservationsCleaner: ObservationsDataCleaning {

    var removeObservationsDataCallCount = 0

    func removeObservationsData() async {
        removeObservationsDataCallCount += 1
    }

}
