//
//  ReinstallUserDetectionTests.swift
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

import XCTest
import PersistenceTestingUtils
@testable import DuckDuckGo_Privacy_Browser

// MARK: - Mocks

final class MockApplicationBuildType: ApplicationBuildType {
    var isSparkleBuild: Bool = true
    var isAppStoreBuild: Bool = false
    var isDebugBuild: Bool = false
    var isReviewBuild: Bool = false
}

final class MockBundleURLProvider: BundleURLProviding {
    var bundleURL: URL = URL(fileURLWithPath: "/Applications/DuckDuckGo.app")
}

final class MockFileManagerForReinstallDetection: FileManager {
    var mockCreationDate: Date?
    var shouldThrowError = false

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if shouldThrowError {
            throw NSError(domain: "MockFileManager", code: 1, userInfo: nil)
        }
        var attributes: [FileAttributeKey: Any] = [:]
        if let date = mockCreationDate {
            attributes[.creationDate] = date
        }
        return attributes
    }
}

// MARK: - Tests

final class ReinstallUserDetectionTests: XCTestCase {

    private static let suiteName = "testing_reinstall_user_detection"

    // MARK: - Properties

    private var sut: DefaultReinstallUserDetection!
    private var mockBuildType: MockApplicationBuildType!
    private var mockFileManager: MockFileManagerForReinstallDetection!
    private var mockBundleURLProvider: MockBundleURLProvider!
    private var mockKeyValueStore: MockThrowingKeyValueStore!
    private var standardDefaults: UserDefaults!

    // MARK: - Test Dates

    private let january1 = Date(timeIntervalSince1970: 1704067200) // Jan 1, 2024 00:00:00 UTC
    private let january2 = Date(timeIntervalSince1970: 1704153600) // Jan 2, 2024 00:00:00 UTC

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()

        mockBuildType = MockApplicationBuildType()
        mockFileManager = MockFileManagerForReinstallDetection()
        mockBundleURLProvider = MockBundleURLProvider()
        mockKeyValueStore = MockThrowingKeyValueStore()
        standardDefaults = UserDefaults(suiteName: Self.suiteName)

        createSUT()
    }

    override func tearDown() {
        sut = nil
        mockBuildType = nil
        mockFileManager = nil
        mockBundleURLProvider = nil
        mockKeyValueStore = nil
        standardDefaults.removePersistentDomain(forName: Self.suiteName)
        standardDefaults = nil

        super.tearDown()
    }

    private func createSUT() {
        sut = DefaultReinstallUserDetection(
            buildType: mockBuildType,
            fileManager: mockFileManager,
            bundleURLProvider: mockBundleURLProvider,
            keyValueStore: mockKeyValueStore,
            standardDefaults: standardDefaults
        )
    }

    // MARK: - isReinstallingUser Property Tests

    func testWhenNoValueStoredThenIsReinstallingUserReturnsFalse() {
        XCTAssertFalse(sut.isReinstallingUser)
    }

    func testWhenTrueStoredThenIsReinstallingUserReturnsTrue() throws {
        try mockKeyValueStore.set(true, forKey: "reinstall.detection.is-reinstalling-user")

        XCTAssertTrue(sut.isReinstallingUser)
    }

    func testWhenFalseStoredThenIsReinstallingUserReturnsFalse() throws {
        try mockKeyValueStore.set(false, forKey: "reinstall.detection.is-reinstalling-user")

        XCTAssertFalse(sut.isReinstallingUser)
    }

    // MARK: - App Store Build Tests

    func testWhenAppStoreBuildThenIsReinstallingUserReturnsFalse() throws {
        mockBuildType.isSparkleBuild = false
        mockBuildType.isAppStoreBuild = true

        // Even if stored value is true, should return false for App Store
        try mockKeyValueStore.set(true, forKey: "reinstall.detection.is-reinstalling-user")

        XCTAssertFalse(sut.isReinstallingUser)
    }

    func testWhenAppStoreBuildThenCheckForReinstallingUserIsNoOp() throws {
        mockBuildType.isSparkleBuild = false
        mockBuildType.isAppStoreBuild = true
        mockFileManager.mockCreationDate = january1

        try sut.checkForReinstallingUser()

        // Should not store anything
        let storedDate = try mockKeyValueStore.object(forKey: "reinstall.detection.bundle-creation-date")
        XCTAssertNil(storedDate)
        XCTAssertFalse(sut.isReinstallingUser)
    }

    // MARK: - First Launch Tests

    func testWhenNoStoredDateThenStoresCurrentBundleDate() throws {
        mockFileManager.mockCreationDate = january1

        try sut.checkForReinstallingUser()

        let storedDate = try mockKeyValueStore.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        XCTAssertEqual(storedDate, january1)
    }

    func testWhenNoStoredDateThenDoesNotFlagAsReinstall() throws {
        mockFileManager.mockCreationDate = january1

        try sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
    }

    // MARK: - Same Bundle Tests (Dates Match)

    func testWhenDatesMatchExactlyThenNoChanges() throws {
        mockFileManager.mockCreationDate = january1
        try mockKeyValueStore.set(january1, forKey: "reinstall.detection.bundle-creation-date")

        try sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
        let storedDate = try mockKeyValueStore.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        XCTAssertEqual(storedDate, january1)
    }

    func testWhenDatesWithinToleranceThenTreatedAsEqual() throws {
        let storedDate = january1
        let currentDate = january1.addingTimeInterval(0.5) // 0.5 seconds later
        mockFileManager.mockCreationDate = currentDate
        try mockKeyValueStore.set(storedDate, forKey: "reinstall.detection.bundle-creation-date")

        try sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
    }

    func testWhenDatesExactlyAtToleranceBoundaryThenTreatedAsDifferent() throws {
        let storedDate = january1
        let currentDate = january1.addingTimeInterval(1.0) // Exactly 1 second later
        mockFileManager.mockCreationDate = currentDate
        try mockKeyValueStore.set(storedDate, forKey: "reinstall.detection.bundle-creation-date")

        try sut.checkForReinstallingUser()

        // At exactly 1.0 second, dates are considered different (since we use < 1.0)
        XCTAssertTrue(sut.isReinstallingUser)
    }

    // MARK: - Sparkle Update Tests

    func testWhenDatesChangedAndSparkleMetadataPresentThenNotFlaggedAsReinstall() throws {
        mockFileManager.mockCreationDate = january2
        try mockKeyValueStore.set(january1, forKey: "reinstall.detection.bundle-creation-date")
        standardDefaults.set("1.0.0", forKey: "pending.update.source.version")

        try sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
    }

    func testWhenDatesChangedAndSparkleMetadataPresentThenUpdatesStoredDate() throws {
        mockFileManager.mockCreationDate = january2
        try mockKeyValueStore.set(january1, forKey: "reinstall.detection.bundle-creation-date")
        standardDefaults.set("1.0.0", forKey: "pending.update.source.version")

        try sut.checkForReinstallingUser()

        let storedDate = try mockKeyValueStore.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        XCTAssertEqual(storedDate, january2)
    }

    // MARK: - Reinstall Detection Tests

    func testWhenDatesChangedAndNoSparkleMetadataThenFlaggedAsReinstall() throws {
        mockFileManager.mockCreationDate = january2
        try mockKeyValueStore.set(january1, forKey: "reinstall.detection.bundle-creation-date")
        // No Sparkle metadata set

        try sut.checkForReinstallingUser()

        XCTAssertTrue(sut.isReinstallingUser)
    }

    func testWhenDatesChangedAndNoSparkleMetadataThenUpdatesStoredDate() throws {
        mockFileManager.mockCreationDate = january2
        try mockKeyValueStore.set(january1, forKey: "reinstall.detection.bundle-creation-date")

        try sut.checkForReinstallingUser()

        let storedDate = try mockKeyValueStore.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        XCTAssertEqual(storedDate, january2)
    }

    func testWhenReinstallDetectedThenSubsequentCallsReturnTrue() throws {
        // First call - simulate reinstall
        mockFileManager.mockCreationDate = january2
        try mockKeyValueStore.set(january1, forKey: "reinstall.detection.bundle-creation-date")
        try sut.checkForReinstallingUser()

        XCTAssertTrue(sut.isReinstallingUser)

        // Second call - should still return true
        createSUT()
        XCTAssertTrue(sut.isReinstallingUser)
    }

    // MARK: - Edge Case Tests

    func testWhenCannotReadBundleCreationDateThenSkipsDetection() throws {
        mockFileManager.shouldThrowError = true
        try mockKeyValueStore.set(january1, forKey: "reinstall.detection.bundle-creation-date")

        try sut.checkForReinstallingUser()

        // Should not flag as reinstall
        XCTAssertFalse(sut.isReinstallingUser)
        // Should not modify stored date
        let storedDate = try mockKeyValueStore.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        XCTAssertEqual(storedDate, january1)
    }

    func testWhenBundleCreationDateNotInAttributesThenSkipsDetection() throws {
        mockFileManager.mockCreationDate = nil // No creation date in attributes

        try sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
        let storedDate = try mockKeyValueStore.object(forKey: "reinstall.detection.bundle-creation-date")
        XCTAssertNil(storedDate)
    }

    // MARK: - Integration-like Tests

    func testTypicalReinstallFlow() throws {
        // Step 1: First launch - new user
        mockFileManager.mockCreationDate = january1
        try sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)

        // Step 2: Normal app launch (same bundle)
        createSUT()
        try sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)

        // Step 3: User reinstalls (new bundle, no Sparkle)
        mockFileManager.mockCreationDate = january2
        createSUT()
        try sut.checkForReinstallingUser()

        XCTAssertTrue(sut.isReinstallingUser)
    }

    func testTypicalSparkleUpdateFlow() throws {
        // Step 1: First launch
        mockFileManager.mockCreationDate = january1
        try sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)

        // Step 2: Sparkle update (new bundle, Sparkle metadata present)
        mockFileManager.mockCreationDate = january2
        standardDefaults.set("1.0.0", forKey: "pending.update.source.version")
        createSUT()
        try sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
    }
}
