//
//  ApplicationUpdateDetectorTests.swift
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

import BrowserServicesKit
import Persistence
import PersistenceTestingUtils
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class ApplicationUpdateDetectorTests: XCTestCase {

    private var settings: (any ThrowingKeyedStoring<UpdateControllerSettings>)!
    private var detector: ApplicationUpdateDetector!

    override func setUp() {
        super.setUp()
        settings = InMemoryThrowingKeyValueStore().throwingKeyedStoring()
        detector = ApplicationUpdateDetector(settings: settings)
    }

    override func tearDown() {
        super.tearDown()
        settings = nil
        detector = nil
    }

    func testWhenVersionAndBuildAreTheSame_ThenStatusIsNoChange() {
        let status = detector.isApplicationUpdated(currentVersion: "1.0.0", currentBuild: "1", previousVersion: "1.0.0", previousBuild: "1")
        XCTAssertEqual(status, .noChange, "Expected noChange when version and build are the same")
    }

    func testWhenVersionIsNewer_ThenStatusIsUpdated() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "2.0.0", currentBuild: "1", previousVersion: "1.0.0", previousBuild: "1")
        XCTAssertEqual(status, .updated, "Expected updated when version is newer")
    }

    func testWhenVersionIsOlder_ThenStatusIsDowngraded() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0.0", currentBuild: "1", previousVersion: "2.0.0", previousBuild: "1")
        XCTAssertEqual(status, .downgraded, "Expected downgraded when version is older")
    }

    func testWhenBuildIsNewer_ThenStatusIsUpdated() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0.0", currentBuild: "2", previousVersion: "1.0.0", previousBuild: "1")
        XCTAssertEqual(status, .updated, "Expected updated when build is newer")
    }

    func testWhenBuildIsOlder_ThenStatusIsDowngraded() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0.0", currentBuild: "1", previousVersion: "1.0.0", previousBuild: "2")
        XCTAssertEqual(status, .downgraded, "Expected downgraded when build is older")
    }

    func testWhenMinorVersionIsNewer_ThenStatusIsUpdated() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.1.0", currentBuild: "1", previousVersion: "1.0.0", previousBuild: "1")
        XCTAssertEqual(status, .updated, "Expected updated when minor version is newer")
    }

    func testWhenMinorVersionIsOlder_ThenStatusIsDowngraded() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0.0", currentBuild: "1", previousVersion: "1.1.0", previousBuild: "1")
        XCTAssertEqual(status, .downgraded, "Expected downgraded when minor version is older")
    }

    func testWhenPatchVersionIsNewer_ThenStatusIsUpdated() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0.1", currentBuild: "1", previousVersion: "1.0.0", previousBuild: "1")
        XCTAssertEqual(status, .updated, "Expected updated when patch version is newer")
    }

    func testWhenPatchVersionIsOlder_ThenStatusIsDowngraded() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0.0", currentBuild: "1", previousVersion: "1.0.1", previousBuild: "1")
        XCTAssertEqual(status, .downgraded, "Expected downgraded when patch version is older")
    }

    func testWhenMajorVersionIsNewerAndBuildIsUpdated_ThenStatusIsUpdated() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.100.0", currentBuild: "235", previousVersion: "1.99.0", previousBuild: "234")
        XCTAssertEqual(status, .updated, "Expected updated when build and version are newer")
    }

    func testWhenMajorVersionIsOlderAndBuildIsDowngraded_ThenStatusIsDowngraded() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.99.0", currentBuild: "234", previousVersion: "1.100.0", previousBuild: "235")
        XCTAssertEqual(status, .downgraded, "Expected downgraded when build is older")
    }

    func testWhenMajorVersionIsNewerButBuildIsOlder_ThenStatusIsUpdated() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "2.0.0", currentBuild: "1", previousVersion: "1.99.99", previousBuild: "100")
        XCTAssertEqual(status, .updated, "Expected updated when major version is newer despite older build")
    }

    func testWhenSameVersionButBuildIsNewer_ThenStatusIsUpdated() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0.0", currentBuild: "2", previousVersion: "1.0.0", previousBuild: "1")
        XCTAssertEqual(status, .updated, "Expected updated when build is newer")
    }

    func testWhenSameVersionButBuildIsOlder_ThenStatusIsDowngraded() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0.0", currentBuild: "1", previousVersion: "1.0.0", previousBuild: "2")
        XCTAssertEqual(status, .downgraded, "Expected downgraded when build is older")
    }

    func testWhenVersionIsOlderButBuildIsNewer_ThenStatusIsDowngraded() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0.0", currentBuild: "2", previousVersion: "1.0.1", previousBuild: "1")
        XCTAssertEqual(status, .downgraded, "Expected downgraded when version is older despite newer build")
    }

    func testWhenVersionIsNewerButFormattedDifferently_ThenStatusIsUpdated() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0.0", currentBuild: "1", previousVersion: "1.0", previousBuild: "1")
        XCTAssertEqual(status, .updated, "Expected updated when current version is more specific (1.0.0 vs 1.0)")
    }

    func testWhenVersionIsOlderButFormattedDifferently_ThenStatusIsDowngraded() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1.0", currentBuild: "1", previousVersion: "1.0.0", previousBuild: "1")
        XCTAssertEqual(status, .downgraded, "Expected downgraded when current version is less specific (1.0 vs 1.0.0)")
    }

    func testWhenMajorVersionIsNewerWithDifferingFormats_ThenStatusIsUpdated() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "2.0.0", currentBuild: "1", previousVersion: "1", previousBuild: "1")
        XCTAssertEqual(status, .updated, "Expected updated when major version is newer (2.0.0 vs 1)")
    }

    func testWhenMajorVersionIsOlderWithDifferingFormats_ThenStatusIsDowngraded() {
        let detector = ApplicationUpdateDetector(settings: settings)
        let status = detector.isApplicationUpdated(currentVersion: "1", currentBuild: "1", previousVersion: "2.0.0", previousBuild: "1")
        XCTAssertEqual(status, .downgraded, "Expected downgraded when major version is older (1 vs 2.0.0)")
    }

}
