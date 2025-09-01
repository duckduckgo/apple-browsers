//
//  MaliciousSiteProtectionUpdateManagerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Clocks
import Common
import Foundation
import Networking
import XCTest

@testable import MaliciousSiteProtection

@available(iOS 16, macOS 13, *)
class MaliciousSiteProtectionUpdateManagerTests: XCTestCase {

    var updateManager: MaliciousSiteProtection.UpdateManager!
    var dataManager: MockMaliciousSiteProtectionDataManager!
    var apiClient: MockMaliciousSiteProtectionAPIClient!
    var updateIntervalProvider: UpdateManager.UpdateIntervalProvider!
    var updateManagerInfoStore: MockMaliciousSiteProtectionUpdateManagerInfoStore!
    var clock: TestClock<Duration>!
    var willSleep: ((TimeInterval) -> Void)?
    var updateTask: Task<Void, Error>?
    private var isScamProtectionSupported = false
    private var mockEventMapping: MockEventMapping!

    override func setUp() async throws {
        apiClient = MockMaliciousSiteProtectionAPIClient()
        dataManager = MockMaliciousSiteProtectionDataManager()
        clock = TestClock()
        updateManagerInfoStore = MockMaliciousSiteProtectionUpdateManagerInfoStore()
        mockEventMapping = MockEventMapping()

        let clockSleeper = Sleeper(clock: clock)
        let reportingSleeper = Sleeper {
            self.willSleep?($0)
            try await clockSleeper.sleep(for: $0)
        }

        updateManager = MaliciousSiteProtection.UpdateManager(apiClient: apiClient, dataManager: dataManager, eventMapping: mockEventMapping, sleeper: reportingSleeper, updateInfoStorage: updateManagerInfoStore, updateIntervalProvider: { self.updateIntervalProvider($0) }, supportedThreatsProvider: { return self.isScamProtectionSupported ? ThreatKind.allCases : ThreatKind.allCases.filter { $0 != .scam } })
    }

    override func tearDown() async throws {
        clock = nil
        updateManager = nil
        updateManagerInfoStore = nil
        dataManager = nil
        apiClient = nil
        updateIntervalProvider = nil
        mockEventMapping = nil
        updateTask?.cancel()
        do {
            try await withTimeout(1) { [updateTask] in
                try await updateTask?.value
            }
        } catch is CancellationError {
        }
        updateTask = nil
    }

    func testUpdateHashPrefixes() async throws {
        try await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))
        let dataSet = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        XCTAssertEqual(dataSet, HashPrefixSet(revision: 1, items: [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ]))
    }

    func testUpdateHashPrefixesForScamWhenFlagOff() async throws {
        isScamProtectionSupported = false
        try await updateManager.updateData(for: .hashPrefixes(threatKind: .scam))
        let dataSet = await dataManager.dataSet(for: .hashPrefixes(threatKind: .scam))
        XCTAssertEqual(dataSet, HashPrefixSet(revision: 0, items: []))
    }

    func testUpdateHashPrefixesForScamWhenFlagOn() async throws {
        isScamProtectionSupported = true
        try await updateManager.updateData(for: .hashPrefixes(threatKind: .scam))
        let dataSet = await dataManager.dataSet(for: .hashPrefixes(threatKind: .scam))
        XCTAssertEqual(dataSet, HashPrefixSet(revision: 1, items: [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ]))
    }

    func testUpdateFilterSet() async throws {
        try await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        let dataSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        XCTAssertEqual(dataSet, FilterDictionary(revision: 1, items: [
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash2", regex: ".*test.*")
        ]))
    }

    func testUpdateFilterSetForScamWhenFlagIsOff() async throws {
        isScamProtectionSupported = false
        try await updateManager.updateData(for: .filterSet(threatKind: .scam))
        let dataSet = await dataManager.dataSet(for: .filterSet(threatKind: .scam))
        XCTAssertEqual(dataSet, FilterDictionary(revision: 0, items: []))
    }

    func testUpdateFilterSetForScamWhenFlagIsOn() async throws {
        isScamProtectionSupported = true
        try await updateManager.updateData(for: .filterSet(threatKind: .scam))
        let dataSet = await dataManager.dataSet(for: .filterSet(threatKind: .scam))
        XCTAssertEqual(dataSet, FilterDictionary(revision: 1, items: [
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash2", regex: ".*test.*")
        ]))
    }

    func testRevision1AddsAndDeletesData() async throws {
        let expectedFilterSet: Set<Filter> = [
            Filter(hash: "testhash2", regex: ".*test.*"),
            Filter(hash: "testhash3", regex: ".*test.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "aa00bb11",
            "bb00cc11",
            "a379a6f6",
            "93e2435e"
        ]

        // revision 0 -> 1
        try await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        try await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

        // revision 1 -> 2
        try await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        try await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 2, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 2, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

    func testRevision2AddsAndDeletesData() async throws {
        let expectedFilterSet: Set<Filter> = [
            Filter(hash: "testhash4", regex: ".*test.*"),
            Filter(hash: "testhash2", regex: ".*test1.*"),
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash3", regex: ".*test3.*"),
        ]
        let expectedHashPrefixes: Set<String> = [
            "aa00bb11",
            "a379a6f6",
            "c0be0d0a6",
            "dd00ee11",
            "cc00dd11"
        ]

        // Save revision and update the filter set and hash prefixes
        try await dataManager.store(FilterDictionary(revision: 2, items: [
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash2", regex: ".*test.*"),
            Filter(hash: "testhash2", regex: ".*test1.*"),
            Filter(hash: "testhash3", regex: ".*test3.*"),
        ]), for: .filterSet(threatKind: .phishing))
        try await dataManager.store(HashPrefixSet(revision: 2, items: [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ]), for: .hashPrefixes(threatKind: .phishing))

        try await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        try await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 3, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 3, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

    func testRevision3AddsAndDeletesNothing() async throws {
        let expectedFilterSet: Set<Filter> = []
        let expectedHashPrefixes: Set<String> = []

        // Save revision and update the filter set and hash prefixes
        try await dataManager.store(FilterDictionary(revision: 3, items: []), for: .filterSet(threatKind: .phishing))
        try await dataManager.store(HashPrefixSet(revision: 3, items: []), for: .hashPrefixes(threatKind: .phishing))

        try await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        try await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 3, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 3, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

    func testRevision4AddsAndDeletesData() async throws {
        let expectedFilterSet: Set<Filter> = [
            Filter(hash: "testhash5", regex: ".*test.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "a379a6f6",
        ]

        // Save revision and update the filter set and hash prefixes
        try await dataManager.store(FilterDictionary(revision: 4, items: []), for: .filterSet(threatKind: .phishing))
        try await dataManager.store(HashPrefixSet(revision: 4, items: []), for: .hashPrefixes(threatKind: .phishing))

        try await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        try await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 5, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 5, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

    func testRevision5replacesData() async throws {
        let expectedFilterSet: Set<Filter> = [
            Filter(hash: "testhash6", regex: ".*test6.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "aa55aa55"
        ]

        // Save revision and update the filter set and hash prefixes
        try await dataManager.store(FilterDictionary(revision: 5, items: [
            Filter(hash: "testhash2", regex: ".*test.*"),
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash5", regex: ".*test.*")
        ]), for: .filterSet(threatKind: .phishing))
        try await dataManager.store(HashPrefixSet(revision: 5, items: [
            "a379a6f6",
            "dd00ee11",
            "cc00dd11",
            "bb00cc11"
        ]), for: .hashPrefixes(threatKind: .phishing))

        try await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        try await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 6, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 6, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

    #if os(macOS)
    func testWhenPeriodicUpdatesStart_dataSetsAreUpdated() async throws {
        self.updateIntervalProvider = { _ in 0.9 }

        let eHashPrefixesUpdated = expectation(description: "Hash prefixes updated")
        let c1 = await dataManager.publisher(for: .hashPrefixes(threatKind: .phishing)).dropFirst().sink { data in
            eHashPrefixesUpdated.fulfill()
        }
        let eFilterSetUpdated = expectation(description: "Filter set updated")
        let c2 = await dataManager.publisher(for: .filterSet(threatKind: .phishing)).dropFirst().sink { data in
            eFilterSetUpdated.fulfill()
        }

        updateTask = updateManager.startPeriodicUpdates()
        await Task.megaYield(count: 10)

        // expect initial update run instantly
        await fulfillment(of: [eHashPrefixesUpdated, eFilterSetUpdated], timeout: 1)

        withExtendedLifetime((c1, c2)) {}
    }

    func testWhenPeriodicUpdatesStart_forScam_andFlagOn_dataSetsAreUpdated() async throws {
        isScamProtectionSupported = true
        self.updateIntervalProvider = { _ in 0.9 }

        let eHashPrefixesUpdated = expectation(description: "Hash prefixes updated")
        let c1 = await dataManager.publisher(for: .hashPrefixes(threatKind: .scam)).dropFirst().sink { data in
            eHashPrefixesUpdated.fulfill()
        }
        let eFilterSetUpdated = expectation(description: "Filter set updated")
        let c2 = await dataManager.publisher(for: .filterSet(threatKind: .scam)).dropFirst().sink { data in
            eFilterSetUpdated.fulfill()
        }

        updateTask = updateManager.startPeriodicUpdates()
        await Task.megaYield(count: 10)

        // expect initial update run instantly
        await fulfillment(of: [eHashPrefixesUpdated, eFilterSetUpdated], timeout: 1)

        withExtendedLifetime((c1, c2)) {}
    }

    func testWhenPeriodicUpdatesStart_forScam_andFlagOff_dataSetsAreNotUpdated() async throws {
        isScamProtectionSupported = false
        self.updateIntervalProvider = { _ in 0.9 }

        // Data for both hash prefixes and filter set should not be updated when scam protection is disabled
        let c1 = await dataManager.publisher(for: .hashPrefixes(threatKind: .scam))
            .dropFirst()
            .sink { data in
                XCTFail("Unexpected hash prefixes update received: \(data)")
            }

        let c2 = await dataManager.publisher(for: .filterSet(threatKind: .scam))
            .dropFirst()
            .sink { data in
                XCTFail("Unexpected filter set update received: \(data)")
            }

        // Set up sleep expectations to synchronize with the mock clock
        var sleepIndex = 0
        let sleepExpectations = [
            XCTestExpectation(description: "Will Sleep 1"),
            XCTestExpectation(description: "Will Sleep 2"),
        ]
        self.willSleep = { _ in
            DispatchQueue.main.async {
                sleepExpectations[safe: sleepIndex]?.fulfill()
                sleepIndex += 1
            }
        }

        updateTask = updateManager.startPeriodicUpdates()
        await fulfillment(of: [sleepExpectations[0]], timeout: 1)

        // Advance the clock to trigger the next sleep interval
        await self.clock.advance(by: .seconds(1))
        await fulfillment(of: [sleepExpectations[1]], timeout: 1)

        withExtendedLifetime((c1, c2)) {}
    }

    func testWhenPeriodicUpdatesAreEnabled_dataSetsAreUpdatedContinuously() async throws {
        // Start periodic updates
        self.updateIntervalProvider = { dataType in
            switch dataType {
            case .hashPrefixSet(.init(threatKind: .phishing)): 1 * 0.99 // update hash prefixes every second
            case .filterSet(.init(threatKind: .phishing)): 2 * 0.99 // update filter set every 2 seconds
            default: nil // only update phishing data
            }
        }

        let hashPrefixUpdateExpectations = [
            XCTestExpectation(description: "Hash prefixes rev.1 update received"),
            XCTestExpectation(description: "Hash prefixes rev.2 update received"),
            XCTestExpectation(description: "Hash prefixes rev.3 update received"),
        ]
        let filterSetUpdateExpectations = [
            XCTestExpectation(description: "Filter set rev.1 update received"),
            XCTestExpectation(description: "Filter set rev.2 update received"),
            XCTestExpectation(description: "Filter set rev.3 update received"),
        ]
        let hashPrefixSleepExpectations = [
            XCTestExpectation(description: "HP Will Sleep 1"),
            XCTestExpectation(description: "HP Will Sleep 2"),
            XCTestExpectation(description: "HP Will Sleep 3"),
        ]
        let filterSetSleepExpectations = [
            XCTestExpectation(description: "FS Will Sleep 1"),
            XCTestExpectation(description: "FS Will Sleep 2"),
            XCTestExpectation(description: "FS Will Sleep 3"),
        ]

        let c1 = await dataManager.publisher(for: .hashPrefixes(threatKind: .phishing)).dropFirst().sink { data in
            hashPrefixUpdateExpectations[data.revision - 1].fulfill()
        }
        let c2 = await dataManager.publisher(for: .filterSet(threatKind: .phishing)).dropFirst().sink { data in
            filterSetUpdateExpectations[data.revision - 1].fulfill()
        }
        var hashPrefixSleepIndex = 0
        var filterSetSleepIndex = 0
        self.willSleep = { interval in
            DispatchQueue.main.async {
                if interval <= 1 {
                    hashPrefixSleepExpectations[safe: hashPrefixSleepIndex]?.fulfill()
                    hashPrefixSleepIndex += 1
                } else {
                    filterSetSleepExpectations[safe: filterSetSleepIndex]?.fulfill()
                    filterSetSleepIndex += 1
                }
            }
        }

        // expect initial hashPrefixes update run instantly
        updateTask = updateManager.startPeriodicUpdates()
        await fulfillment(of: [hashPrefixUpdateExpectations[0], hashPrefixSleepExpectations[0], filterSetUpdateExpectations[0], filterSetSleepExpectations[0]], timeout: 1)

        // Advance the clock by 1 seconds
        await self.clock.advance(by: .seconds(1))
        // expect to receive v.2 update for hashPrefixes (1s. interval)
        await fulfillment(of: [hashPrefixUpdateExpectations[1], hashPrefixSleepExpectations[1]], timeout: 1)

        // Advance the clock by 1 seconds
        await self.clock.advance(by: .seconds(1))
        // expect to receive v.3 update for hashPrefixes (1s. interval) and v.2 update for filterSet (2s. interval)
        await fulfillment(of: [hashPrefixUpdateExpectations[2], hashPrefixSleepExpectations[2], filterSetUpdateExpectations[1], filterSetSleepExpectations[1]], timeout: 1)

        // Advance the clock by 1 seconds
        await self.clock.advance(by: .seconds(2))
        // expect to receive v.3 update for filterSet (2s. interval) and no update for hashPrefixes (no v.3->v.4 update in MockMaliciousSiteProtectionAPIClient)
        await fulfillment(of: [filterSetSleepExpectations[2], filterSetUpdateExpectations[2]], timeout: 1)

        withExtendedLifetime((c1, c2)) {}
    }

    func testWhenPeriodicUpdatesAreDisabled_noDataSetsAreUpdated() async throws {
        // Start periodic updates
        self.updateIntervalProvider = { dataType in
            switch dataType {
            case .hashPrefixSet(.init(threatKind: .phishing)): return 0.9
            default: return nil // Set update interval to nil for FilterSet or other threat kinds
            }
        }

        let expectations = [
            XCTestExpectation(description: "Hash prefixes rev.1 update received"),
            XCTestExpectation(description: "Hash prefixes rev.2 update received"),
            XCTestExpectation(description: "Hash prefixes rev.3 update received"),
        ]
        let c1 = await dataManager.publisher(for: .hashPrefixes(threatKind: .phishing)).dropFirst().sink { data in
            expectations[data.revision - 1].fulfill()
        }
        // data for FilterSet should not be updated
        let c2 = await dataManager.publisher(for: .filterSet(threatKind: .phishing)).dropFirst().sink { data in
            XCTFail("Unexpected filter set update received: \(data)")
        }
        // synchronize Task threads to advance the Test Clock when the updated Task is sleeping,
        // otherwise we‘ll eventually advance the clock before the sleep and get hung.
        var sleepIndex = 0
        let sleepExpectations = [
            XCTestExpectation(description: "Will Sleep 1"),
            XCTestExpectation(description: "Will Sleep 2"),
            XCTestExpectation(description: "Will Sleep 3"),
        ]
        self.willSleep = { _ in
            DispatchQueue.main.async {
                sleepExpectations[safe: sleepIndex]?.fulfill()
                sleepIndex += 1
            }
        }

        // expect initial hashPrefixes update run instantly
        updateTask = updateManager.startPeriodicUpdates()
        await fulfillment(of: [expectations[0], sleepExpectations[0]], timeout: 1)

        // Advance the clock by 1 seconds
        await self.clock.advance(by: .seconds(1))
        // expect to receive v.2 update for hashPrefixes
        await fulfillment(of: [expectations[1], sleepExpectations[1]], timeout: 1)

        // Advance the clock by 1 seconds
        await self.clock.advance(by: .seconds(1))
        // expect to receive v.3 update for hashPrefixes
        await fulfillment(of: [expectations[2], sleepExpectations[2]], timeout: 1)

        withExtendedLifetime((c1, c2)) {}
    }

    func testWhenPeriodicUpdatesAreCancelled_noFurtherUpdatesReceived() async throws {
        // Start periodic updates
        self.updateIntervalProvider = { _ in 0.99 }
        updateTask = updateManager.startPeriodicUpdates()

        // Wait for the initial update
        try await withTimeout(1) { [self] in
            for await _ in await dataManager.publisher(for: .hashPrefixes(threatKind: .phishing)).first(where: { $0.revision == 1 }).values {}
            for await _ in await dataManager.publisher(for: .filterSet(threatKind: .phishing)).first(where: { $0.revision == 1 }).values {}
        }

        // Cancel the update task
        updateTask!.cancel()
        do {
            try await withTimeout(1) { [updateTask=updateTask!] in
                try await updateTask.value
            }
        } catch is CancellationError {
        }

        // Reset expectations for further updates
        let c = await dataManager.$store.dropFirst().sink { data in
            XCTFail("Unexpected data update received: \(data)")
        }

        // Advance the clock to check for further updates
        await self.clock.advance(by: .seconds(1))
        await clock.run()
        await Task.megaYield(count: 10)

        // Verify that the data sets have not been updated further
        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        XCTAssertEqual(hashPrefixes.revision, 1) // Expecting revision to remain 1
        XCTAssertEqual(filterSet.revision, 1) // Expecting revision to remain 1

        withExtendedLifetime(c) {}
    }
    #endif

    #if os(iOS)
    func testWhenLastHashPrefixSetUpdateDateIsCalledThenReturnStoredDate() {
        // GIVEN
        let date = Date()
        updateManagerInfoStore.lastHashPrefixSetsUpdateDate = date

        // WHEN
        let result = updateManager.lastHashPrefixSetUpdateDate

        // THEN
        XCTAssertEqual(result, date)
    }

    func testWhenLastFilterSetUpdateDateIsCalledThenReturnStoredDate() {
        // GIVEN
        let date = Date()
        updateManagerInfoStore.lastFilterSetsUpdateDate = date

        // WHEN
        let result = updateManager.lastFilterSetUpdateDate

        // THEN
        XCTAssertEqual(result, date)
    }

    func testWhenUpdateDataForDatasetTypeIsCalled_AndTypeIsHashPrefix_AndDatasetIsUpdated_ThenSaveUpdateDate() async throws {
        // GIVEN
        XCTAssertEqual(updateManagerInfoStore.lastHashPrefixSetsUpdateDate, .distantPast)

        // WHEN
        await updateManager.updateData(datasetType: .hashPrefixSet).value

        // THEN
        XCTAssertNotEqual(updateManagerInfoStore.lastHashPrefixSetsUpdateDate, .distantPast)
    }

    func testWhenUpdateDataForDatasetTypeIsCalled_AndTypeIsFilterSet_AndDatasetIsUpdated_ThenSaveUpdateDate() async throws {
        // GIVEN
        XCTAssertEqual(updateManagerInfoStore.lastFilterSetsUpdateDate, .distantPast)

        // WHEN
        await updateManager.updateData(datasetType: .filterSet).value

        // THEN
        XCTAssertNotEqual(updateManagerInfoStore.lastFilterSetsUpdateDate, .distantPast)
    }

    func testWhenUpdateDataForDatasetTypeIsCalled_AndTypeIsHashPrefix_AndDatasetIsNotUpdated_ThenDoNotSaveUpdateDate() async throws {
        // GIVEN
        dataManager = MockMaliciousSiteProtectionDataManager(storeDatasetSuccess: false)
        updateManager = MaliciousSiteProtection.UpdateManager(apiClient: apiClient, dataManager: dataManager, eventMapping: mockEventMapping, updateInfoStorage: updateManagerInfoStore, updateIntervalProvider: { self.updateIntervalProvider($0) }, supportedThreatsProvider: { return self.isScamProtectionSupported ? ThreatKind.allCases : ThreatKind.allCases.filter { $0 != .scam } })
        XCTAssertEqual(updateManagerInfoStore.lastHashPrefixSetsUpdateDate, .distantPast)

        // WHEN
        await updateManager.updateData(datasetType: .hashPrefixSet).value

        // THEN
        XCTAssertEqual(updateManagerInfoStore.lastHashPrefixSetsUpdateDate, .distantPast)
    }

    func testWhenUpdateDataForDatasetTypeIsCalled_AndTypeIsFilterSet_AndDatasetIsNotUpdated_ThenDoNotSaveUpdateDate() async throws {
        // GIVEN
        dataManager = MockMaliciousSiteProtectionDataManager(storeDatasetSuccess: false)
        updateManager = MaliciousSiteProtection.UpdateManager(apiClient: apiClient, dataManager: dataManager, eventMapping: mockEventMapping, updateInfoStorage: updateManagerInfoStore, updateIntervalProvider: { self.updateIntervalProvider($0) }, supportedThreatsProvider: { return self.isScamProtectionSupported ? ThreatKind.allCases : ThreatKind.allCases.filter { $0 != .scam } })
        XCTAssertEqual(updateManagerInfoStore.lastFilterSetsUpdateDate, .distantPast)

        // WHEN
        await updateManager.updateData(datasetType: .hashPrefixSet).value

        // THEN
        XCTAssertEqual(updateManagerInfoStore.lastFilterSetsUpdateDate, .distantPast)
    }
    #endif

    func testWhenUpdateDataApiFails_AndInitialLocalDatasetIsEmpty_AndErrorIsNoInternetConnection_ThenSendFailedToFetchDatasetsPixel() async {
        // GIVEN
        apiClient.loadRequestError = APIRequestV2.Error.urlSession(URLError(.notConnectedToInternet))
        updateManager = MaliciousSiteProtection.UpdateManager(apiClient: apiClient, dataManager: dataManager, eventMapping: mockEventMapping, updateIntervalProvider: { self.updateIntervalProvider($0) }, supportedThreatsProvider: { return self.isScamProtectionSupported ? ThreatKind.allCases : ThreatKind.allCases.filter { $0 != .scam } })
        XCTAssertTrue(mockEventMapping.events.isEmpty)

        // WHEN
        await XCTAssertThrowsError(try await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing)))

        // THEN
        switch mockEventMapping.events.last {
        case let .failedToDownloadInitialDataSets(category, type):
            XCTAssertEqual(category, .phishing)
            XCTAssertEqual(type, .hashPrefixSet)
        default:
            XCTFail("Unexpected event sent: \(mockEventMapping.events)")
        }
    }

    func testWhenUpdateDataApiFails_AndInitialLocalDatasetIsNotEmpty_AndErrorIsNoInternetConnection_ThenDoNotSendFailedToFetchDatasetsPixel() async throws {
        // GIVEN
        try await dataManager.store(HashPrefixSet(revision: 3, items: []), for: .hashPrefixes(threatKind: .phishing))
        apiClient.loadRequestError = APIRequestV2.Error.urlSession(URLError(.notConnectedToInternet))
        updateManager = MaliciousSiteProtection.UpdateManager(apiClient: apiClient, dataManager: dataManager, eventMapping: mockEventMapping, updateIntervalProvider: { self.updateIntervalProvider($0) }, supportedThreatsProvider: { return self.isScamProtectionSupported ? ThreatKind.allCases : ThreatKind.allCases.filter { $0 != .scam } })
        XCTAssertTrue(mockEventMapping.events.isEmpty)

        // WHEN
        await XCTAssertThrowsError(try await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing)))

        // THEN
        XCTAssertTrue(mockEventMapping.events.isEmpty)
    }

}
