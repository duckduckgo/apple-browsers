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
@testable import DuckDuckGo_Privacy_Browser

// MARK: - Mocks

final class MockApplicationBuildType: ApplicationBuildType {
    var isSparkleBuild: Bool = true
    var isAppStoreBuild: Bool = false
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

    // MARK: - Properties

    private var sut: DefaultReinstallUserDetection!
    private var mockBuildType: MockApplicationBuildType!
    private var mockFileManager: MockFileManagerForReinstallDetection!
    private var mockBundleURLProvider: MockBundleURLProvider!
    private var appGroupDefaults: UserDefaults!
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

        // Create fresh in-memory UserDefaults for each test
        let appGroupSuiteName = "test.reinstall.detection.appgroup.\(UUID().uuidString)"
        let standardSuiteName = "test.reinstall.detection.standard.\(UUID().uuidString)"
        appGroupDefaults = UserDefaults(suiteName: appGroupSuiteName)!
        standardDefaults = UserDefaults(suiteName: standardSuiteName)!

        createSUT()
    }

    override func tearDown() {
        sut = nil
        mockBuildType = nil
        mockFileManager = nil
        mockBundleURLProvider = nil
        appGroupDefaults.removePersistentDomain(forName: appGroupDefaults.description)
        standardDefaults.removePersistentDomain(forName: standardDefaults.description)
        appGroupDefaults = nil
        standardDefaults = nil

        super.tearDown()
    }

    private func createSUT() {
        sut = DefaultReinstallUserDetection(
            buildType: mockBuildType,
            fileManager: mockFileManager,
            bundleURLProvider: mockBundleURLProvider,
            appGroupDefaults: appGroupDefaults,
            standardDefaults: standardDefaults
        )
    }

    // MARK: - isReinstallingUser Property Tests

    func testWhenNoValueStoredThenIsReinstallingUserReturnsFalse() {
        XCTAssertFalse(sut.isReinstallingUser)
    }

    func testWhenTrueStoredThenIsReinstallingUserReturnsTrue() {
        appGroupDefaults.set(true, forKey: "reinstall.detection.is-reinstalling-user")

        XCTAssertTrue(sut.isReinstallingUser)
    }

    func testWhenFalseStoredThenIsReinstallingUserReturnsFalse() {
        appGroupDefaults.set(false, forKey: "reinstall.detection.is-reinstalling-user")

        XCTAssertFalse(sut.isReinstallingUser)
    }

    // MARK: - App Store Build Tests

    func testWhenAppStoreBuildThenIsReinstallingUserReturnsFalse() {
        mockBuildType.isSparkleBuild = false
        mockBuildType.isAppStoreBuild = true

        // Even if stored value is true, should return false for App Store
        appGroupDefaults.set(true, forKey: "reinstall.detection.is-reinstalling-user")

        XCTAssertFalse(sut.isReinstallingUser)
    }

    func testWhenAppStoreBuildThenCheckForReinstallingUserIsNoOp() {
        mockBuildType.isSparkleBuild = false
        mockBuildType.isAppStoreBuild = true
        mockFileManager.mockCreationDate = january1

        sut.checkForReinstallingUser()

        // Should not store anything
        XCTAssertNil(appGroupDefaults.object(forKey: "reinstall.detection.bundle-creation-date"))
        XCTAssertFalse(sut.isReinstallingUser)
    }

    // MARK: - First Launch Tests

    func testWhenNoStoredDateThenStoresCurrentBundleDate() {
        mockFileManager.mockCreationDate = january1

        sut.checkForReinstallingUser()

        let storedDate = appGroupDefaults.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        XCTAssertEqual(storedDate, january1)
    }

    func testWhenNoStoredDateThenDoesNotFlagAsReinstall() {
        mockFileManager.mockCreationDate = january1

        sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
    }

    // MARK: - Same Bundle Tests (Dates Match)

    func testWhenDatesMatchExactlyThenNoChanges() {
        mockFileManager.mockCreationDate = january1
        appGroupDefaults.set(january1, forKey: "reinstall.detection.bundle-creation-date")

        sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
        let storedDate = appGroupDefaults.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        XCTAssertEqual(storedDate, january1)
    }

    func testWhenDatesWithinToleranceThenTreatedAsEqual() {
        let storedDate = january1
        let currentDate = january1.addingTimeInterval(0.5) // 0.5 seconds later
        mockFileManager.mockCreationDate = currentDate
        appGroupDefaults.set(storedDate, forKey: "reinstall.detection.bundle-creation-date")

        sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
    }

    func testWhenDatesExactlyAtToleranceBoundaryThenTreatedAsDifferent() {
        let storedDate = january1
        let currentDate = january1.addingTimeInterval(1.0) // Exactly 1 second later
        mockFileManager.mockCreationDate = currentDate
        appGroupDefaults.set(storedDate, forKey: "reinstall.detection.bundle-creation-date")

        sut.checkForReinstallingUser()

        // At exactly 1.0 second, dates are considered different (since we use < 1.0)
        XCTAssertTrue(sut.isReinstallingUser)
    }

    // MARK: - Sparkle Update Tests

    func testWhenDatesChangedAndSparkleMetadataPresentThenNotFlaggedAsReinstall() {
        mockFileManager.mockCreationDate = january2
        appGroupDefaults.set(january1, forKey: "reinstall.detection.bundle-creation-date")
        standardDefaults.set("1.0.0", forKey: "pending.update.source.version")

        sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
    }

    func testWhenDatesChangedAndSparkleMetadataPresentThenUpdatesStoredDate() {
        mockFileManager.mockCreationDate = january2
        appGroupDefaults.set(january1, forKey: "reinstall.detection.bundle-creation-date")
        standardDefaults.set("1.0.0", forKey: "pending.update.source.version")

        sut.checkForReinstallingUser()

        let storedDate = appGroupDefaults.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        XCTAssertEqual(storedDate, january2)
    }

    // MARK: - Reinstall Detection Tests

    func testWhenDatesChangedAndNoSparkleMetadataThenFlaggedAsReinstall() {
        mockFileManager.mockCreationDate = january2
        appGroupDefaults.set(january1, forKey: "reinstall.detection.bundle-creation-date")
        // No Sparkle metadata set

        sut.checkForReinstallingUser()

        XCTAssertTrue(sut.isReinstallingUser)
    }

    func testWhenDatesChangedAndNoSparkleMetadataThenUpdatesStoredDate() {
        mockFileManager.mockCreationDate = january2
        appGroupDefaults.set(january1, forKey: "reinstall.detection.bundle-creation-date")

        sut.checkForReinstallingUser()

        let storedDate = appGroupDefaults.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        XCTAssertEqual(storedDate, january2)
    }

    func testWhenReinstallDetectedThenSubsequentCallsReturnTrue() {
        // First call - simulate reinstall
        mockFileManager.mockCreationDate = january2
        appGroupDefaults.set(january1, forKey: "reinstall.detection.bundle-creation-date")
        sut.checkForReinstallingUser()

        XCTAssertTrue(sut.isReinstallingUser)

        // Second call - should still return true
        createSUT()
        XCTAssertTrue(sut.isReinstallingUser)
    }

    // MARK: - Edge Case Tests

    func testWhenCannotReadBundleCreationDateThenSkipsDetection() {
        mockFileManager.shouldThrowError = true
        appGroupDefaults.set(january1, forKey: "reinstall.detection.bundle-creation-date")

        sut.checkForReinstallingUser()

        // Should not flag as reinstall
        XCTAssertFalse(sut.isReinstallingUser)
        // Should not modify stored date
        let storedDate = appGroupDefaults.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        XCTAssertEqual(storedDate, january1)
    }

    func testWhenBundleCreationDateNotInAttributesThenSkipsDetection() {
        mockFileManager.mockCreationDate = nil // No creation date in attributes

        sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
        XCTAssertNil(appGroupDefaults.object(forKey: "reinstall.detection.bundle-creation-date"))
    }

    // MARK: - Integration-like Tests

    func testTypicalReinstallFlow() {
        // Step 1: First launch - new user
        mockFileManager.mockCreationDate = january1
        sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)

        // Step 2: Normal app launch (same bundle)
        createSUT()
        sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)

        // Step 3: User reinstalls (new bundle, no Sparkle)
        mockFileManager.mockCreationDate = january2
        createSUT()
        sut.checkForReinstallingUser()

        XCTAssertTrue(sut.isReinstallingUser)
    }

    func testTypicalSparkleUpdateFlow() {
        // Step 1: First launch
        mockFileManager.mockCreationDate = january1
        sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)

        // Step 2: Sparkle update (new bundle, Sparkle metadata present)
        mockFileManager.mockCreationDate = january2
        standardDefaults.set("1.0.0", forKey: "pending.update.source.version")
        createSUT()
        sut.checkForReinstallingUser()

        XCTAssertFalse(sut.isReinstallingUser)
    }
}
