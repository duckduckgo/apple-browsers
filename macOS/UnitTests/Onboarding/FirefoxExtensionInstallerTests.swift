//
//  FirefoxExtensionInstallerTests.swift
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

import Foundation
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class FirefoxExtensionInstallerTests: XCTestCase {

    func testWhenFirefoxIsNotInstalledThenCanInstallIsFalse() {
        let installer = makeSUT(firefoxApplicationURL: nil)

        XCTAssertFalse(installer.canInstallDDGExtension)
    }

    func testWhenFirefoxIsInstalledThenCanInstallIsTrue() {
        let installer = makeSUT(firefoxApplicationURL: URL(fileURLWithPath: "/Applications/Firefox.app"))

        XCTAssertTrue(installer.canInstallDDGExtension)
    }

    func testWhenFirefoxIsNotInstalledThenInstallReturnsFalseAndDoesNotLaunch() {
        var launchCalls: [(URL, URL)] = []
        let installer = makeSUT(firefoxApplicationURL: nil, launch: { launchCalls.append(($0, $1)) })

        XCTAssertFalse(installer.installDDGExtension())
        XCTAssertTrue(launchCalls.isEmpty)
    }

    func testWhenFirefoxIsInstalledThenInstallLaunchesFirefoxAtInstallURL() {
        let firefoxAppURL = URL(fileURLWithPath: "/Applications/Firefox.app")
        let installURL = URL(string: "https://example.com/extension.xpi")!
        var launchCalls: [(URL, URL)] = []
        let installer = makeSUT(installURL: installURL,
                                firefoxApplicationURL: firefoxAppURL,
                                launch: { launchCalls.append(($0, $1)) })

        XCTAssertTrue(installer.installDDGExtension())
        XCTAssertEqual(launchCalls.count, 1)
        XCTAssertEqual(launchCalls.first?.0, installURL)
        XCTAssertEqual(launchCalls.first?.1, firefoxAppURL)
    }

    func testDefaultDirectXPIInstallURLIsWellFormed() {
        XCTAssertEqual(
            FirefoxExtensionInstaller.InstallURL.directXPI.absoluteString,
            "https://addons.mozilla.org/firefox/downloads/latest/duckduckgo-for-firefox/latest.xpi"
        )
    }

    // MARK: - Helpers

    private func makeSUT(
        installURL: URL = FirefoxExtensionInstaller.InstallURL.directXPI,
        firefoxApplicationURL: URL? = URL(fileURLWithPath: "/Applications/Firefox.app"),
        launch: @escaping (URL, URL) -> Void = { _, _ in }
    ) -> FirefoxExtensionInstaller {
        FirefoxExtensionInstaller(
            installURL: installURL,
            firefoxApplicationURL: { firefoxApplicationURL },
            launch: launch
        )
    }
}
