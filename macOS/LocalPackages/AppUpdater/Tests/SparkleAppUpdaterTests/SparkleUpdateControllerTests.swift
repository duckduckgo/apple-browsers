//
//  SparkleUpdateControllerTests.swift
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

import SparkleAppUpdater
import XCTest

final class SparkleUpdateControllerTests: XCTestCase {

    // MARK: - Auto-update paused

    func testResolveAutoDownload_paused_preferenceOn_returnsFalse() {
        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            isAutoUpdatePaused: true,
            userPreference: true
        )

        XCTAssertFalse(result)
    }

    func testResolveAutoDownload_paused_preferenceOff_returnsFalse() {
        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            isAutoUpdatePaused: true,
            userPreference: false
        )

        XCTAssertFalse(result)
    }

    // MARK: - Auto-update not paused

    func testResolveAutoDownload_notPaused_preferenceOn_returnsTrue() {
        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            isAutoUpdatePaused: false,
            userPreference: true
        )

        XCTAssertTrue(result)
    }

    func testResolveAutoDownload_notPaused_preferenceOff_returnsFalse() {
        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            isAutoUpdatePaused: false,
            userPreference: false
        )

        XCTAssertFalse(result)
    }
}
