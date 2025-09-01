//
//  UpdateControllerTests.swift
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
import BrowserServicesKit

final class UpdateControllerTests: XCTestCase {

    func testSparkleUpdaterErrorReason() {
        let updateController = UpdateController(
            internalUserDecider: MockInternalUserDecider(),
            featureFlagger: MockFeatureFlagger(),
            updateCheckState: UpdateCheckState()
        )

        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Package installer failed to launch."), "Package installer failed to launch." )
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Guided package installer failed to launch"), "Guided package installer failed to launch")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "An error occurred while running the updater. Please try again later."), "An error occurred while running the updater.")

        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Guided package installer failed to launch with additional error details"), "Guided package installer failed to launch")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Failed to move the new app from /path/to/source to /path/to/destination"), "Failed to move the new app")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Guided package installer returned non-zero exit status (1)"), "Guided package installer returned non-zero exit status")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Found regular application update but expected 'version=1.0' from appcast"), "Found regular application update")

        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Some completely unknown error message"), "unknown")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: ""), "unknown")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Unexpected installer error format"), "unknown")
    }

}
