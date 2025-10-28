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
@testable import DuckDuckGo_Privacy_Browser
@testable import PixelKit
import XCTest

final class SparkleUpdateCompletionValidatorTests: XCTestCase {

    var pixelKit: PixelKit!
    var firedPixels: [(name: String, parameters: [String: String]?)] = []
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()

        // Create isolated UserDefaults for testing
        let suiteName = "test_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        // Setup mock PixelKit
        pixelKit = PixelKit(dryRun: false,
                           appVersion: "1.0.0",
                           defaultHeaders: [:],
                           defaults: testDefaults) { [weak self] pixelName, _, parameters, _, _, _ in
            guard let self else { return }
            self.firedPixels.append((name: pixelName, parameters: parameters))
        }
        pixelKit.clearFrequencyHistoryForAllPixels()
        PixelKit.setSharedForTesting(pixelKit: pixelKit)

        // Clear any existing metadata
        SparkleUpdateCompletionValidator.clearPendingUpdateMetadata()

        firedPixels = []
    }

    override func tearDown() {
        PixelKit.tearDown()
        pixelKit = nil
        testDefaults = nil
        firedPixels = []
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func assertPixelFired(named pixelName: String, file: StaticString = #file, line: UInt = #line) -> [String: String]? {
        guard let pixel = firedPixels.first(where: { $0.name == pixelName }) else {
            XCTFail("Expected pixel '\(pixelName)' was not fired", file: file, line: line)
            return nil
        }
        return pixel.parameters
    }

    private func assertNoPixelFired(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(firedPixels.isEmpty, "Expected no pixels to fire, but \(firedPixels.count) were fired", file: file, line: line)
    }

    // MARK: - Validation Tests

    func testWhenUpdateStatusIsUpdatedAndMetadataExistsThenPixelIsFired() {
        // Given: Stored metadata
        SparkleUpdateCompletionValidator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )

        // When: Check with .updated status
        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457"
        )

        // Then: Pixel should be fired with correct parameters
        let parameters = assertPixelFired(named: "m_mac_update_application_success")
        XCTAssertEqual(parameters?["sourceVersion"], "1.100.0")
        XCTAssertEqual(parameters?["sourceBuild"], "123456")
        XCTAssertEqual(parameters?["targetVersion"], "1.101.0")
        XCTAssertEqual(parameters?["targetBuild"], "123457")
        XCTAssertEqual(parameters?["initiationType"], "manual")
        XCTAssertEqual(parameters?["updateConfiguration"], "automatic")
        XCTAssertNotNil(parameters?["osVersion"])
    }

    func testWhenUpdateStatusIsNoChangeWithMetadataThenFailurePixelIsFired() {
        // Given: Stored metadata
        SparkleUpdateCompletionValidator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )

        // When: Check with .noChange status
        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: .noChange,
            currentVersion: "1.100.0",
            currentBuild: "123456"
        )

        // Then: Failure pixel should be fired
        let parameters = assertPixelFired(named: "m_mac_update_application_failure")
        XCTAssertEqual(parameters?["sourceVersion"], "1.100.0")
        XCTAssertEqual(parameters?["sourceBuild"], "123456")
        XCTAssertEqual(parameters?["expectedVersion"], "1.101.0")
        XCTAssertEqual(parameters?["expectedBuild"], "123457")
        XCTAssertEqual(parameters?["actualVersion"], "1.100.0")
        XCTAssertEqual(parameters?["actualBuild"], "123456")
        XCTAssertEqual(parameters?["failureStatus"], "noChange")
        XCTAssertEqual(parameters?["initiationType"], "manual")
        XCTAssertEqual(parameters?["updateConfiguration"], "automatic")
        XCTAssertNotNil(parameters?["osVersion"])

        // AND: Metadata should be cleared
        XCTAssertNil(testDefaults.string(forKey: "pending.update.source.version"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.source.build"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.expected.version"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.expected.build"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.initiation.type"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.configuration"))
    }

    func testWhenUpdateStatusIsDowngradedWithMetadataThenFailurePixelIsFired() {
        // Given: Stored metadata
        SparkleUpdateCompletionValidator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )

        // When: Check with .downgraded status
        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: .downgraded,
            currentVersion: "1.99.0",
            currentBuild: "123455"
        )

        // Then: Failure pixel should be fired
        let parameters = assertPixelFired(named: "m_mac_update_application_failure")
        XCTAssertEqual(parameters?["sourceVersion"], "1.100.0")
        XCTAssertEqual(parameters?["sourceBuild"], "123456")
        XCTAssertEqual(parameters?["expectedVersion"], "1.101.0")
        XCTAssertEqual(parameters?["expectedBuild"], "123457")
        XCTAssertEqual(parameters?["actualVersion"], "1.99.0")
        XCTAssertEqual(parameters?["actualBuild"], "123455")
        XCTAssertEqual(parameters?["failureStatus"], "downgraded")
        XCTAssertEqual(parameters?["initiationType"], "manual")
        XCTAssertEqual(parameters?["updateConfiguration"], "automatic")
        XCTAssertNotNil(parameters?["osVersion"])

        // AND: Metadata should be cleared
        XCTAssertNil(testDefaults.string(forKey: "pending.update.source.version"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.source.build"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.expected.version"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.expected.build"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.initiation.type"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.configuration"))
    }

    func testWhenUpdateStatusIsUpdatedWithNoMetadataThenPixelIsFiredWithNonSparkleFlag() {
        // Given: NO metadata stored (non-Sparkle update)

        // When: Check with .updated status
        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457"
        )

        // Then: Unexpected pixel should be fired
        let parameters = assertPixelFired(named: "m_mac_update_application_unexpected")
        XCTAssertEqual(parameters?["targetVersion"], "1.101.0")
        XCTAssertEqual(parameters?["targetBuild"], "123457")
        XCTAssertNotNil(parameters?["osVersion"])
    }

    func testWhenPixelIsFiredWithAutomaticInitiationThenParametersAreCorrect() {
        // Given: Stored metadata with automatic initiation
        SparkleUpdateCompletionValidator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "automatic",
            updateConfiguration: "automatic"
        )

        // When: Fire pixel
        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457"
        )

        // Then: Verify initiationType is automatic
        let parameters = assertPixelFired(named: "m_mac_update_application_success")
        XCTAssertEqual(parameters?["initiationType"], "automatic")
    }

    func testWhenPixelIsFiredWithManualConfigurationThenParametersAreCorrect() {
        // Given: Stored metadata with manual configuration
        SparkleUpdateCompletionValidator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "manual"
        )

        // When: Fire pixel
        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457"
        )

        // Then: Verify updateConfiguration is manual
        let parameters = assertPixelFired(named: "m_mac_update_application_success")
        XCTAssertEqual(parameters?["updateConfiguration"], "manual")
    }

    func testWhenPixelIsFiredThenMetadataIsCleared() {
        // Given: Stored metadata
        SparkleUpdateCompletionValidator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )

        // When: Fire pixel once
        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457"
        )

        // Then: First call should fire success pixel (Sparkle-initiated)
        let firstCallParams = assertPixelFired(named: "m_mac_update_application_success")
        XCTAssertEqual(firstCallParams?["sourceVersion"], "1.100.0")

        // Clear the fired pixels array
        firedPixels = []

        // When: Try to fire again
        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457"
        )

        // Then: Second call should fire unexpected pixel (metadata was cleared)
        let secondCallParams = assertPixelFired(named: "m_mac_update_application_unexpected")
        XCTAssertEqual(secondCallParams?["targetVersion"], "1.101.0")
        XCTAssertEqual(secondCallParams?["targetBuild"], "123457")
        XCTAssertNotNil(secondCallParams?["osVersion"])
    }

    func testWhenPixelIsFiredThenOSVersionIsFormattedCorrectly() {
        // Given: Stored metadata
        SparkleUpdateCompletionValidator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )

        // When: Fire pixel
        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: .updated,
            currentVersion: "1.101.0",
            currentBuild: "123457"
        )

        // Then: OS version should be present and formatted correctly
        let parameters = assertPixelFired(named: "m_mac_update_application_success")
        let osVersion = parameters?["osVersion"]
        XCTAssertNotNil(osVersion)
        // Should be in format "14.2.1" (major.minor.patch)
        XCTAssertTrue(osVersion?.components(separatedBy: ".").count ?? 0 >= 2)
    }

    func testWhenValidationRunsThenMetadataIsAlwaysCleared() {
        // Given: Stored metadata
        SparkleUpdateCompletionValidator.storePendingUpdateMetadata(
            sourceVersion: "1.100.0",
            sourceBuild: "123456",
            expectedVersion: "1.101.0",
            expectedBuild: "123457",
            initiationType: "manual",
            updateConfiguration: "automatic"
        )

        // When: Check with .noChange (failure pixel will fire)
        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: .noChange,
            currentVersion: "1.100.0",
            currentBuild: "123456"
        )

        // Then: Metadata should be cleared even after pixel fires
        XCTAssertNil(testDefaults.string(forKey: "pending.update.source.version"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.source.build"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.expected.version"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.expected.build"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.initiation.type"))
        XCTAssertNil(testDefaults.string(forKey: "pending.update.configuration"))
    }
}
