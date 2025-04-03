//
//  MaliciousSiteProtectionDataManagerTests.swift
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

import Foundation
import XCTest

@testable import MaliciousSiteProtection

class MaliciousSiteProtectionDataManagerTests: XCTestCase {
    var embeddedDataProvider: MockMaliciousSiteProtectionEmbeddedDataProvider!
    enum Constants {
        static let hashPrefixesFileName = "phishingHashPrefixes.json"
        static let filterSetFileName = "phishingFilterSet.json"
    }
    let datasetFiles: [String] = [Constants.hashPrefixesFileName, Constants.filterSetFileName]
    var dataManager: MaliciousSiteProtection.DataManager!
    var fileStore: MockMaliciousSiteProtectionFileStore!

    override func setUp() async throws {
        embeddedDataProvider = MockMaliciousSiteProtectionEmbeddedDataProvider()
        fileStore = MockMaliciousSiteProtectionFileStore()
        setUpDataManager()
    }

    func setUpDataManager() {
        dataManager = MaliciousSiteProtection.DataManager(fileStore: fileStore, embeddedDataProvider: embeddedDataProvider, fileNameProvider: { dataType in
            switch dataType {
            case .filterSet: Constants.filterSetFileName
            case .hashPrefixSet: Constants.hashPrefixesFileName
            }
        })
    }

    override func tearDown() async throws {
        embeddedDataProvider = nil
        dataManager = nil
    }

    func clearDatasets() throws {
        for fileName in datasetFiles {
            let emptyData = Data()
            try fileStore.write(data: emptyData, to: fileName)
        }
    }

    func testWhenNoDataSavedAndProviderIsNotNilThenProviderDataReturned() async throws {
        try clearDatasets()
        let expectedFilterSet = Set([Filter(hash: "some", regex: "some")])
        let expectedFilterDict = FilterDictionary(revision: 65, items: expectedFilterSet)
        let expectedHashPrefix = Set(["sassa"])
        embeddedDataProvider.filterSet = expectedFilterSet
        embeddedDataProvider.hashPrefixes = expectedHashPrefix

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))

        XCTAssertEqual(actualFilterSet, expectedFilterDict)
        XCTAssertEqual(actualHashPrefix.set, expectedHashPrefix)
    }

    func testWhenNoDataSavedAndEmbeddedProviderIsNilThenCreateAnEmptyDataSet() async throws {
        // GIVEN
        try clearDatasets()
        dataManager = MaliciousSiteProtection.DataManager(
            fileStore: fileStore,
            embeddedDataProvider: nil,
            fileNameProvider: { dataType in
                switch dataType {
                case .filterSet: Constants.filterSetFileName
                case .hashPrefixSet: Constants.hashPrefixesFileName
                }
            })
        let expectedFilterDict = FilterDictionary(revision: 0, items: [])
        let expectedHashPrefix = HashPrefixSet(revision: 0, items: [])

        // WHEN
        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))

        // THEN
        XCTAssertEqual(actualFilterSet, expectedFilterDict)
        XCTAssertEqual(actualHashPrefix, expectedHashPrefix)
    }

    func testWhenEmbeddedRevisionNewerThanOnDisk_ThenLoadEmbedded() async throws {
        let encoder = JSONEncoder()
        // On Disk Data Setup
        let onDiskFilterSet = Set([Filter(hash: "other", regex: "other")])
        let filterSetData = try! encoder.encode(Array(onDiskFilterSet))
        let onDiskHashPrefix = Set(["faffa"])
        let hashPrefixData = try! encoder.encode(Array(onDiskHashPrefix))
        try fileStore.write(data: filterSetData, to: Constants.filterSetFileName)
        try fileStore.write(data: hashPrefixData, to: Constants.hashPrefixesFileName)

        // Embedded Data Setup
        embeddedDataProvider.embeddedRevision = 5
        let embeddedFilterSet = Set([Filter(hash: "some", regex: "some")])
        let embeddedFilterDict = FilterDictionary(revision: 5, items: embeddedFilterSet)
        let embeddedHashPrefix = Set(["sassa"])
        embeddedDataProvider.filterSet = embeddedFilterSet
        embeddedDataProvider.hashPrefixes = embeddedHashPrefix

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(actualFilterSet, embeddedFilterDict)
        XCTAssertEqual(actualHashPrefix.set, embeddedHashPrefix)
        XCTAssertEqual(actualFilterSetRevision, 5)
        XCTAssertEqual(actualHashPrefixRevision, 5)
    }

    func testWhenEmbeddedRevisionOlderThanOnDisk_ThenDontLoadEmbedded() async throws {
        // On Disk Data Setup
        let onDiskFilterDict = FilterDictionary(revision: 6, items: [Filter(hash: "other", regex: "other")])
        let filterSetData = try! JSONEncoder().encode(onDiskFilterDict)
        let onDiskHashPrefix = HashPrefixSet(revision: 6, items: ["faffa"])
        let hashPrefixData = try! JSONEncoder().encode(onDiskHashPrefix)
        try fileStore.write(data: filterSetData, to: Constants.filterSetFileName)
        try fileStore.write(data: hashPrefixData, to: Constants.hashPrefixesFileName)

        // Embedded Data Setup
        embeddedDataProvider.embeddedRevision = 1
        let embeddedFilterSet = Set([Filter(hash: "some", regex: "some")])
        let embeddedHashPrefix = Set(["sassa"])
        embeddedDataProvider.filterSet = embeddedFilterSet
        embeddedDataProvider.hashPrefixes = embeddedHashPrefix

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(actualFilterSet, onDiskFilterDict)
        XCTAssertEqual(actualHashPrefix, onDiskHashPrefix)
        XCTAssertEqual(actualFilterSetRevision, 6)
        XCTAssertEqual(actualHashPrefixRevision, 6)
    }

    func testWhenStoredDataIsMalformed_ThenEmbeddedDataIsLoaded() async throws {
        // On Disk Data Setup
        try fileStore.write(data: "fake".utf8data, to: Constants.filterSetFileName)
        try fileStore.write(data: "fake".utf8data, to: Constants.hashPrefixesFileName)

        // Embedded Data Setup
        embeddedDataProvider.embeddedRevision = 1
        let embeddedFilterSet = Set([Filter(hash: "some", regex: "some")])
        let embeddedFilterDict = FilterDictionary(revision: 1, items: embeddedFilterSet)
        let embeddedHashPrefix = Set(["sassa"])
        embeddedDataProvider.filterSet = embeddedFilterSet
        embeddedDataProvider.hashPrefixes = embeddedHashPrefix

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(actualFilterSet, embeddedFilterDict)
        XCTAssertEqual(actualHashPrefix.set, embeddedHashPrefix)
        XCTAssertEqual(actualFilterSetRevision, 1)
        XCTAssertEqual(actualHashPrefixRevision, 1)
    }

    func testWhenEmbeddedProviderIsNilThenLoadDataFromDisk() async throws {
        // GIVEN
        // On Disk Data Setup
        let onDiskFilterDict = FilterDictionary(revision: 6, items: [Filter(hash: "other", regex: "other")])
        let filterSetData = try! JSONEncoder().encode(onDiskFilterDict)
        let onDiskHashPrefix = HashPrefixSet(revision: 6, items: ["faffa"])
        let hashPrefixData = try! JSONEncoder().encode(onDiskHashPrefix)
        try fileStore.write(data: filterSetData, to: Constants.filterSetFileName)
        try fileStore.write(data: hashPrefixData, to: Constants.hashPrefixesFileName)
        dataManager = MaliciousSiteProtection.DataManager(
            fileStore: fileStore,
            embeddedDataProvider: nil,
            fileNameProvider: { dataType in
                switch dataType {
                case .filterSet: Constants.filterSetFileName
                case .hashPrefixSet: Constants.hashPrefixesFileName
                }
            })

        // WHEN
        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        // THEN
        XCTAssertEqual(actualFilterSet, onDiskFilterDict)
        XCTAssertEqual(actualHashPrefix, onDiskHashPrefix)
        XCTAssertEqual(actualFilterSetRevision, 6)
        XCTAssertEqual(actualHashPrefixRevision, 6)
    }

    func testWriteAndLoadData() async throws {
        // Get and write data
        let expectedHashPrefixes = Set(["aabb"])
        let expectedFilterSet = Set([Filter(hash: "dummyhash", regex: "dummyregex")])
        let expectedRevision = 65

        try await dataManager.store(HashPrefixSet(revision: expectedRevision, items: expectedHashPrefixes), for: .hashPrefixes(threatKind: .phishing))
        try await dataManager.store(FilterDictionary(revision: expectedRevision, items: expectedFilterSet), for: .filterSet(threatKind: .phishing))

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(actualFilterSet, FilterDictionary(revision: expectedRevision, items: expectedFilterSet))
        XCTAssertEqual(actualHashPrefix.set, expectedHashPrefixes)
        XCTAssertEqual(actualFilterSetRevision, 65)
        XCTAssertEqual(actualHashPrefixRevision, 65)

        // Test reloading data
        setUpDataManager()

        let reloadedFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let reloadedHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let reloadedFilterSetRevision = actualFilterSet.revision
        let reloadedHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(reloadedFilterSet, FilterDictionary(revision: expectedRevision, items: expectedFilterSet))
        XCTAssertEqual(reloadedHashPrefix.set, expectedHashPrefixes)
        XCTAssertEqual(reloadedFilterSetRevision, 65)
        XCTAssertEqual(reloadedHashPrefixRevision, 65)
    }

    func testLazyLoadingDoesNotReturnStaleData() async throws {
        try clearDatasets()

        // Set up initial data
        let initialFilterSet = Set([Filter(hash: "initial", regex: "initial")])
        let initialHashPrefixes = Set(["initialPrefix"])
        embeddedDataProvider.filterSet = initialFilterSet
        embeddedDataProvider.hashPrefixes = initialHashPrefixes

        // Access the lazy-loaded properties to trigger loading
        let loadedFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let loadedHashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))

        // Validate loaded data matches initial data
        XCTAssertEqual(loadedFilterSet, FilterDictionary(revision: 65, items: initialFilterSet))
        XCTAssertEqual(loadedHashPrefixes.set, initialHashPrefixes)

        // Update in-memory data
        let updatedFilterSet = Set([Filter(hash: "updated", regex: "updated")])
        let updatedHashPrefixes = Set(["updatedPrefix"])
        try await dataManager.store(HashPrefixSet(revision: 1, items: updatedHashPrefixes), for: .hashPrefixes(threatKind: .phishing))
        try await dataManager.store(FilterDictionary(revision: 1, items: updatedFilterSet), for: .filterSet(threatKind: .phishing))

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(actualFilterSet, FilterDictionary(revision: 1, items: updatedFilterSet))
        XCTAssertEqual(actualHashPrefix.set, updatedHashPrefixes)
        XCTAssertEqual(actualFilterSetRevision, 1)
        XCTAssertEqual(actualHashPrefixRevision, 1)

        // Test reloading data – embedded data should be returned as its revision is greater
        setUpDataManager()

        let reloadedFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let reloadedHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let reloadedFilterSetRevision = actualFilterSet.revision
        let reloadedHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(reloadedFilterSet, FilterDictionary(revision: 65, items: initialFilterSet))
        XCTAssertEqual(reloadedHashPrefix.set, initialHashPrefixes)
        XCTAssertEqual(reloadedFilterSetRevision, 1)
        XCTAssertEqual(reloadedHashPrefixRevision, 1)
    }

    func testSuccessfulWriteOfDataDoesNotThrowError() async throws {
        // GIVEN
        fileStore.writeSuccess = true
        let expectedHashPrefixes = Set(["aabb"])
        let expectedFilterSet = Set([Filter(hash: "dummyhash", regex: "dummyregex")])
        let expectedRevision = 65

        // WHEN
        await XCTAssertNoThrow(try await dataManager.store(HashPrefixSet(revision: expectedRevision, items: expectedHashPrefixes), for: .hashPrefixes(threatKind: .phishing)))
        await XCTAssertNoThrow(try await dataManager.store(FilterDictionary(revision: expectedRevision, items: expectedFilterSet), for: .filterSet(threatKind: .phishing)))
    }

    func testUnsuccessfulWriteOfDataThrowsError() async {
        // GIVEN
        fileStore.writeSuccess = false
        let expectedHashPrefixes = Set(["aabb"])
        let expectedFilterSet = Set([Filter(hash: "dummyhash", regex: "dummyregex")])
        let expectedRevision = 65

        // WHEN
        await XCTAssertThrowsError(try await dataManager.store(HashPrefixSet(revision: expectedRevision, items: expectedHashPrefixes), for: .hashPrefixes(threatKind: .phishing)))
        await XCTAssertThrowsError(try await dataManager.store(FilterDictionary(revision: expectedRevision, items: expectedFilterSet), for: .filterSet(threatKind: .phishing)))
    }

}

class MockMaliciousSiteProtectionFileStore: MaliciousSiteProtection.FileStoring {

    private var data: [String: Data] = [:]

    var writeSuccess: Bool = true

    func write(data: Data, to filename: String) throws {
        if writeSuccess {
            self.data[filename] = data
        } else {
            throw NSError(domain: "com.au.duckduckgo.MockMaliciousSiteProtectionFileStore", code: 0, userInfo: nil)
        }
    }

    func read(from filename: String) -> Data? {
        return data[filename]
    }
}
