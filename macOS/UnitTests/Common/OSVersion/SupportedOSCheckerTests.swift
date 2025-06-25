//
//  SupportedOSCheckerTests.swift
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
import FeatureFlags
@testable import DuckDuckGo_Privacy_Browser

final class SupportedOSCheckerTests: XCTestCase {

    // MARK: - Test Data

    private static let catalinaVersion = OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 0)
    private static let bigSurVersion = OperatingSystemVersion(majorVersion: 11, minorVersion: 4, patchVersion: 0)
    private static let montereyVersion = OperatingSystemVersion(majorVersion: 12, minorVersion: 3, patchVersion: 0)
    private static let venturaVersion = OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)

    // MARK: - Minimum Version Tests

    func testWhenCurrentVersionIsHigherThanMinSupportedThenNoWarning() {
        // Given
        let mockFeatureFlagger = FeatureFlaggerMock()
        let checker = SupportedOSChecker(
            featureFlagger: mockFeatureFlagger,
            currentOSVersionOverride: Self.venturaVersion,
            minSupportedOSVersionOverride: Self.bigSurVersion,
            upcomingMinSupportedOSVersionOverride: nil)

        // When
        let warning = checker.supportWarning

        // Then
        XCTAssertNil(warning)
    }

    func testWhenCurrentVersionIsLowerThanMinSupportedThenShowsUnsupportedWarning() {
        // Given
        let mockFeatureFlagger = FeatureFlaggerMock()
        let checker = SupportedOSChecker(
            featureFlagger: mockFeatureFlagger,
            currentOSVersionOverride: Self.catalinaVersion,
            minSupportedOSVersionOverride: Self.bigSurVersion,
            upcomingMinSupportedOSVersionOverride: Self.montereyVersion)

        // When
        let warning = checker.supportWarning

        // Then
        guard case .unsupported(let version) = warning else {
            XCTFail("Expected unsupported warning")
            return
        }
        XCTAssertEqual(version, "11.4")
    }

    func testWhenCurrentVersionIsEqualToMinSupportedThenNoWarning() {
        // Given
        let mockFeatureFlagger = FeatureFlaggerMock()
        let checker = SupportedOSChecker(
            featureFlagger: mockFeatureFlagger,
            currentOSVersionOverride: Self.bigSurVersion,
            minSupportedOSVersionOverride: Self.bigSurVersion,
            upcomingMinSupportedOSVersionOverride: nil)

        // When
        let warning = checker.supportWarning

        // Then
        XCTAssertNil(warning)
    }

    // MARK: - Upcoming Support Tests

    func testWhenNoUpcomingVersionThenNoWarning() {
        // Given
        let mockFeatureFlagger = FeatureFlaggerMock()
        let checker = SupportedOSChecker(
            featureFlagger: mockFeatureFlagger,
            currentOSVersionOverride: Self.bigSurVersion,
            minSupportedOSVersionOverride: Self.bigSurVersion,
            upcomingMinSupportedOSVersionOverride: nil)

        // When
        let warning = checker.supportWarning

        // Then
        XCTAssertNil(warning)
    }

    func testWhenCurrentVersionIsLowerThanUpcomingVersionThenShowsWarning() {
        // Given
        let mockFeatureFlagger = FeatureFlaggerMock()
        let checker = SupportedOSChecker(
            featureFlagger: mockFeatureFlagger,
            currentOSVersionOverride: Self.bigSurVersion,
            minSupportedOSVersionOverride: Self.bigSurVersion,
            upcomingMinSupportedOSVersionOverride: Self.montereyVersion)

        // When
        let warning = checker.supportWarning

        // Then
        guard case .willDropSupportSoon(let version) = warning else {
            XCTFail("Expected will drop support soon warning")
            return
        }
        XCTAssertEqual(version, "12.3")
    }

    func testWhenCurrentVersionIsHigherThanUpcomingVersionThenNoWarning() {
        // Given
        let mockFeatureFlagger = FeatureFlaggerMock()
        let checker = SupportedOSChecker(
            featureFlagger: mockFeatureFlagger,
            currentOSVersionOverride: Self.venturaVersion,
            minSupportedOSVersionOverride: Self.bigSurVersion,
            upcomingMinSupportedOSVersionOverride: Self.montereyVersion)

        // When
        let warning = checker.supportWarning

        // Then
        XCTAssertNil(warning)
    }

    func testWhenCurrentVersionEqualsUpcomingVersionThenNoWarning() {
        // Given
        let mockFeatureFlagger = FeatureFlaggerMock()
        let checker = SupportedOSChecker(
            featureFlagger: mockFeatureFlagger,
            currentOSVersionOverride: Self.montereyVersion,
            minSupportedOSVersionOverride: Self.bigSurVersion,
            upcomingMinSupportedOSVersionOverride: Self.montereyVersion)

        // When
        let warning = checker.supportWarning

        // Then
        XCTAssertNil(warning)
    }

    // MARK: - Feature Flag Tests

    func testWhenForceUnsupportedMessageFeatureFlagIsOnThenShowsUnsupportedWarning() {
        // Given
        let mockFeatureFlagger = FeatureFlaggerMock()
        mockFeatureFlagger.enabledFeatureFlags = [.osSupportForceUnsupportedMessage]
        let checker = SupportedOSChecker(
            featureFlagger: mockFeatureFlagger,
            currentOSVersionOverride: Self.bigSurVersion,
            minSupportedOSVersionOverride: Self.bigSurVersion,
            upcomingMinSupportedOSVersionOverride: Self.montereyVersion)

        // When
        let warning = checker.supportWarning

        // Then
        guard case .unsupported(let version) = warning else {
            XCTFail("Expected unsupported warning")
            return
        }
        XCTAssertEqual(version, "11.4")
    }

    func testWhenForceWillSoonDropSupportMessageFeatureFlagIsOnThenShowsUpcomingWarning() {
        // Given
        let mockFeatureFlagger = FeatureFlaggerMock()
        mockFeatureFlagger.enabledFeatureFlags = [.osSupportForceWillSoonDropSupportMessage]
        let checker = SupportedOSChecker(
            featureFlagger: mockFeatureFlagger,
            currentOSVersionOverride: Self.bigSurVersion,
            minSupportedOSVersionOverride: Self.bigSurVersion,
            upcomingMinSupportedOSVersionOverride: Self.montereyVersion)

        // When
        let warning = checker.supportWarning

        // Then
        guard case .willDropSupportSoon(let version) = warning else {
            XCTFail("Expected will drop support soon warning")
            return
        }
        XCTAssertEqual(version, "12.3")
    }

    func testWhenWillSoonDropBigSurSupportFeatureFlagIsOnThenShowsUpcomingWarning() {
        // Given
        let mockFeatureFlagger = FeatureFlaggerMock()
        mockFeatureFlagger.enabledFeatureFlags = [.willSoonDropBigSurSupport]
        let checker = SupportedOSChecker(
            featureFlagger: mockFeatureFlagger,
            currentOSVersionOverride: Self.bigSurVersion,
            minSupportedOSVersionOverride: Self.bigSurVersion,
            upcomingMinSupportedOSVersionOverride: Self.montereyVersion)

        // When
        let warning = checker.supportWarning

        // Then
        guard case .willDropSupportSoon(let version) = warning else {
            XCTFail("Expected will drop support soon warning")
            return
        }
        XCTAssertEqual(version, "12.3")
    }
}
