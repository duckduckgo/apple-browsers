//
//  SparkleUpdateCompletionValidatorTests.swift
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

import Common
import Persistence
import PersistenceTestingUtils
import PixelKit
import PixelKitTestingUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class SparkleUpdateCompletionValidatorTests: XCTestCase {

    var validator: SparkleUpdateCompletionValidator!
    var testStore: ThrowingKeyValueStoring!
    var testSettings: (any ThrowingKeyedStoring<UpdateControllerSettings>)!
    fileprivate var mockPixelFiring: PixelKitMock!

    override func setUp() {
        super.setUp()

        // Use in-memory store for testing
        testStore = InMemoryThrowingKeyValueStore()
        testSettings = testStore.throwingKeyedStoring()
        validator = SparkleUpdateCompletionValidator(settings: testSettings!)
    }

    override func tearDown() {
        validator = nil
        testSettings = nil
        testStore = nil
        mockPixelFiring = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func osVersionString() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        return "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
    }

    private func makePixelMock(expecting expected: [ExpectedFireCall]) -> PixelKitMock {
        PixelKitMock(expecting: expected)
    }

    // MARK: - Validation Tests

    func testWhenUpdateStatusIsUpdatedAndMetadataExistsThenPixelIsFired() {
        // Given: Stored metadata
        validator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )

        let expectedPixel = UpdateFlowPixels.updateApplicationSuccess(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            targetVersion: "1.101.0",
            targetBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic",
            osVersion: osVersionString()
        )
        mockPixelFiring = makePixelMock(expecting: [ExpectedFireCall(pixel: expectedPixel, frequency: .dailyAndCount)])

        // When: Check with .updated status
        validator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457",
            pixelFiring: mockPixelFiring
        )

        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    func testWhenUpdateStatusIsNoChangeWithMetadataThenFailurePixelIsFired() throws {
        // Given: Stored metadata
        validator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )

        let expectedPixel = UpdateFlowPixels.updateApplicationFailure(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            actualVersion: "1.100.0",
            actualBuild: "123456",
            failureStatus: "noChange",
            initiationType: "manual",
            updateConfiguration: "automatic",
            osVersion: osVersionString()
        )
        mockPixelFiring = makePixelMock(expecting: [ExpectedFireCall(pixel: expectedPixel, frequency: .dailyAndCount)])

        // When: Check with .noChange status
        validator.validateExpectations(
            updateStatus: .noChange,
            currentVersion: "1.100.0",
            currentBuild: "123456",
            pixelFiring: mockPixelFiring
        )

        mockPixelFiring.verifyExpectations(file: #file, line: #line)

        // AND: Metadata should be cleared
        XCTAssertNil(try testSettings.pendingUpdateSourceVersion)
        XCTAssertNil(try testSettings.pendingUpdateSourceBuild)
        XCTAssertNil(try testSettings.pendingUpdateExpectedVersion)
        XCTAssertNil(try testSettings.pendingUpdateExpectedBuild)
        XCTAssertNil(try testSettings.pendingUpdateInitiationType)
        XCTAssertNil(try testSettings.pendingUpdateConfiguration)
    }

    func testWhenUpdateStatusIsDowngradedWithMetadataThenFailurePixelIsFired() throws {
        // Given: Stored metadata
        validator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )

        let expectedPixel = UpdateFlowPixels.updateApplicationFailure(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            actualVersion: "1.99.0",
            actualBuild: "123455",
            failureStatus: "downgraded",
            initiationType: "manual",
            updateConfiguration: "automatic",
            osVersion: osVersionString()
        )
        mockPixelFiring = makePixelMock(expecting: [ExpectedFireCall(pixel: expectedPixel, frequency: .dailyAndCount)])

        // When: Check with .downgraded status
        validator.validateExpectations(
            updateStatus: .downgraded,
            currentVersion: "1.99.0",
            currentBuild: "123455",
            pixelFiring: mockPixelFiring
        )

        mockPixelFiring.verifyExpectations(file: #file, line: #line)

        // AND: Metadata should be cleared
        XCTAssertNil(try testSettings.pendingUpdateSourceVersion)
        XCTAssertNil(try testSettings.pendingUpdateSourceBuild)
        XCTAssertNil(try testSettings.pendingUpdateExpectedVersion)
        XCTAssertNil(try testSettings.pendingUpdateExpectedBuild)
        XCTAssertNil(try testSettings.pendingUpdateInitiationType)
        XCTAssertNil(try testSettings.pendingUpdateConfiguration)
    }

    func testWhenUpdateStatusIsUpdatedWithNoMetadataThenPixelIsFiredWithNonSparkleFlag() {
        // Given: NO metadata stored (non-Sparkle update)
        let expectedPixel = UpdateFlowPixels.updateApplicationUnexpected(
            targetVersion: "1.101.0",
            targetBuild: "123457",
            osVersion: osVersionString()
        )
        mockPixelFiring = makePixelMock(expecting: [ExpectedFireCall(pixel: expectedPixel, frequency: .dailyAndCount)])

        // When: Check with .updated status
        validator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457",
            pixelFiring: mockPixelFiring
        )

        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    func testWhenPixelIsFiredWithAutomaticInitiationThenParametersAreCorrect() {
        // Given: Stored metadata with automatic initiation
        validator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "automatic",
            updateConfiguration: "automatic"
        )

        let expectedPixel = UpdateFlowPixels.updateApplicationSuccess(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            targetVersion: "1.101.0",
            targetBuild: "123457",
            initiationType: "automatic",
            updateConfiguration: "automatic",
            osVersion: osVersionString()
        )
        mockPixelFiring = makePixelMock(expecting: [ExpectedFireCall(pixel: expectedPixel, frequency: .dailyAndCount)])

        // When: Fire pixel
        validator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457",
            pixelFiring: mockPixelFiring
        )

        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    func testWhenPixelIsFiredWithManualConfigurationThenParametersAreCorrect() {
        // Given: Stored metadata with manual configuration
        validator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "manual"
        )

        let expectedPixel = UpdateFlowPixels.updateApplicationSuccess(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            targetVersion: "1.101.0",
            targetBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "manual",
            osVersion: osVersionString()
        )
        mockPixelFiring = makePixelMock(expecting: [ExpectedFireCall(pixel: expectedPixel, frequency: .dailyAndCount)])

        // When: Fire pixel
        validator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457",
            pixelFiring: mockPixelFiring
        )

        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    func testWhenPixelIsFiredThenMetadataIsCleared() {
        // Given: Stored metadata
        validator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )
        let expectedSuccess = UpdateFlowPixels.updateApplicationSuccess(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            targetVersion: "1.101.0",
            targetBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic",
            osVersion: osVersionString()
        )
        mockPixelFiring = makePixelMock(expecting: [ExpectedFireCall(pixel: expectedSuccess, frequency: .dailyAndCount)])

        // When: Fire pixel once
        validator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457",
            pixelFiring: mockPixelFiring
        )

        mockPixelFiring.verifyExpectations(file: #file, line: #line)

        // When: Try to fire again
        let expectedUnexpected = UpdateFlowPixels.updateApplicationUnexpected(
            targetVersion: "1.101.0",
            targetBuild: "123457",
            osVersion: osVersionString()
        )
        mockPixelFiring = makePixelMock(expecting: [ExpectedFireCall(pixel: expectedUnexpected, frequency: .dailyAndCount)])

        validator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457",
            pixelFiring: mockPixelFiring
        )

        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    func testWhenPixelIsFiredThenOSVersionIsFormattedCorrectly() {
        // Given: Stored metadata
        validator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )
        let expectedPixel = UpdateFlowPixels.updateApplicationSuccess(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            targetVersion: "1.101.0",
            targetBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic",
            osVersion: osVersionString()
        )
        mockPixelFiring = makePixelMock(expecting: [ExpectedFireCall(pixel: expectedPixel, frequency: .dailyAndCount)])

        // When: Fire pixel
        validator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457",
            pixelFiring: mockPixelFiring
        )

        mockPixelFiring.verifyExpectations(file: #file, line: #line)
        XCTAssertTrue(osVersionString().components(separatedBy: ".").count >= 2)
    }

    func testWhenValidationRunsThenMetadataIsAlwaysCleared() throws {
        // Given: Stored metadata
        validator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )
        let expectedPixel = UpdateFlowPixels.updateApplicationFailure(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            actualVersion: "1.100.0",
            actualBuild: "123456",
            failureStatus: "noChange",
            initiationType: "manual",
            updateConfiguration: "automatic",
            osVersion: osVersionString()
        )
        mockPixelFiring = makePixelMock(expecting: [ExpectedFireCall(pixel: expectedPixel, frequency: .dailyAndCount)])

        // When: Check with .noChange (failure pixel will fire)
        validator.validateExpectations(
            updateStatus: .noChange,
            currentVersion: "1.100.0",
            currentBuild: "123456",
            pixelFiring: mockPixelFiring
        )
        mockPixelFiring.verifyExpectations(file: #file, line: #line)

        // Then: Metadata should be cleared even after pixel fires
        XCTAssertNil(try testSettings.pendingUpdateSourceVersion)
        XCTAssertNil(try testSettings.pendingUpdateSourceBuild)
        XCTAssertNil(try testSettings.pendingUpdateExpectedVersion)
        XCTAssertNil(try testSettings.pendingUpdateExpectedBuild)
        XCTAssertNil(try testSettings.pendingUpdateInitiationType)
        XCTAssertNil(try testSettings.pendingUpdateConfiguration)
    }
}
