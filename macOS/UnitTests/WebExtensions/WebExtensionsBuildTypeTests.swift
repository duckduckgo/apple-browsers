//
//  WebExtensionsBuildTypeTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

final class WebExtensionsBuildTypeTests: XCTestCase {
    private final class SimulationMock: AppStoreBuildSimulationProtocol {
        var isEnabled: Bool

        init(isEnabled: Bool) {
            self.isEnabled = isEnabled
        }
    }

    func testWhenSimulationIsOnThenDirectDownloadBuildActsAsAppStoreBuild() {
        let base = directDownloadReviewBuild()

        let buildType = WebExtensionsBuildType(base: base, simulation: SimulationMock(isEnabled: true))

        XCTAssertTrue(buildType.isAppStoreBuild)
        XCTAssertFalse(buildType.isSparkleBuild)
        XCTAssertTrue(buildType.isReviewBuild)
    }

    func testWhenSimulationIsOffThenBuildTypeIsUnchanged() {
        let directDownload = directDownloadReviewBuild()
        let appStore = ApplicationBuildTypeMock()
        appStore.isAppStoreBuild = true

        let simulatedDirectDownload = WebExtensionsBuildType(base: directDownload, simulation: SimulationMock(isEnabled: false))
        let simulatedAppStore = WebExtensionsBuildType(base: appStore, simulation: SimulationMock(isEnabled: false))

        XCTAssertFalse(simulatedDirectDownload.isAppStoreBuild)
        XCTAssertTrue(simulatedDirectDownload.isSparkleBuild)
        XCTAssertTrue(simulatedAppStore.isAppStoreBuild)
        XCTAssertFalse(simulatedAppStore.isSparkleBuild)
    }

    func testSimulationIsSavedInUserDefaults() throws {
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: #function) }

        AppStoreBuildSimulation(userDefaults: userDefaults).isEnabled = true

        XCTAssertTrue(AppStoreBuildSimulation(userDefaults: userDefaults).isEnabled)
    }

    private func directDownloadReviewBuild() -> ApplicationBuildTypeMock {
        let buildType = ApplicationBuildTypeMock()
        buildType.isSparkleBuild = true
        buildType.isReviewBuild = true
        return buildType
    }
}
