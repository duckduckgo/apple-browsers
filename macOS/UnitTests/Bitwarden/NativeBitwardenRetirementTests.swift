//
//  NativeBitwardenRetirementTests.swift
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
import WebExtensions
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class NativeBitwardenRetirementTests: XCTestCase {

    private var persistor: AutofillPreferencesPersistorMock!
    private var notificationCenter: NotificationCenter!
    private var isExtensionInstalled = false
    private var disableCallCount = 0
    private var settingsChangeCount = 0
    private var settingsObserver: NSObjectProtocol?
    private var retirement: NativeBitwardenRetirement!

    override func setUp() {
        super.setUp()
        persistor = AutofillPreferencesPersistorMock()
        notificationCenter = NotificationCenter()
        isExtensionInstalled = false
        disableCallCount = 0
        settingsChangeCount = 0
        settingsObserver = notificationCenter.addObserver(forName: .autofillUserSettingsDidChange, object: nil, queue: nil) { [weak self] _ in
            self?.settingsChangeCount += 1
        }
        retirement = NativeBitwardenRetirement(persistor: persistor,
                                               notificationCenter: notificationCenter,
                                               isBitwardenExtensionInstalled: { [unowned self] in isExtensionInstalled },
                                               disableNativeIntegration: { [unowned self] in disableCallCount += 1 })
    }

    override func tearDown() {
        settingsObserver.map(notificationCenter.removeObserver)
        settingsObserver = nil
        retirement = nil
        persistor = nil
        notificationCenter = nil
        super.tearDown()
    }

    func testWhenBitwardenUserHasTheExtensionInstalled_ThenTheyMoveToDuckDuckGo() {
        persistor.passwordManager = .bitwarden
        isExtensionInstalled = true

        retirement.retireIfNeeded()

        XCTAssertEqual(persistor.passwordManager, .duckduckgo)
        XCTAssertEqual(disableCallCount, 1)
        XCTAssertEqual(settingsChangeCount, 1)
    }

    func testWhenTheExtensionIsNotInstalled_ThenBitwardenUserIsLeftAlone() {
        persistor.passwordManager = .bitwarden

        retirement.retireIfNeeded()

        XCTAssertEqual(persistor.passwordManager, .bitwarden)
        XCTAssertEqual(disableCallCount, 0)
        XCTAssertEqual(settingsChangeCount, 0)
    }

    func testWhenUserIsAlreadyOnDuckDuckGo_ThenNothingHappens() {
        isExtensionInstalled = true

        retirement.retireIfNeeded()

        XCTAssertEqual(persistor.passwordManager, .duckduckgo)
        XCTAssertEqual(disableCallCount, 0)
        XCTAssertEqual(settingsChangeCount, 0)
    }

    func testWhenRetiredTwice_ThenTheSecondCallDoesNothing() {
        persistor.passwordManager = .bitwarden
        isExtensionInstalled = true

        retirement.retireIfNeeded()
        retirement.retireIfNeeded()

        XCTAssertEqual(persistor.passwordManager, .duckduckgo)
        XCTAssertEqual(disableCallCount, 1)
        XCTAssertEqual(settingsChangeCount, 1)
    }

    func testWhenAnExtensionIsInstalled_ThenBitwardenUserWithTheExtensionIsRetired() {
        persistor.passwordManager = .bitwarden
        isExtensionInstalled = true

        notificationCenter.post(name: .chromeWebStoreExtensionChanged, object: nil,
                                userInfo: ["extensionId": ChromeWebStoreID.bitwarden.rawValue])

        XCTAssertEqual(persistor.passwordManager, .duckduckgo)
        XCTAssertEqual(disableCallCount, 1)
        XCTAssertEqual(settingsChangeCount, 1)
    }
}
