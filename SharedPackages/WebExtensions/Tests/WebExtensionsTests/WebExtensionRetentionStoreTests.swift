//
//  WebExtensionRetentionStoreTests.swift
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
@_spi(Testing) import Persistence
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionRetentionStoreTests: XCTestCase {

    private let installDate = Date(timeIntervalSince1970: 1_800_000_000)
    private var store: WebExtensionRetentionStore!

    override func setUp() {
        super.setUp()
        store = WebExtensionRetentionStore(storage: InMemoryKeyValueStore().throwingKeyedStoring())
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    func testWhenFourteenDaysHaveNotPassed_ThenNothingIsDue() {
        store.recordInstallation(of: "bitwarden-id", at: installDate)

        XCTAssertEqual(store.takeDue(at: installDate.addingTimeInterval(WebExtensionRetentionStore.retentionPeriod - 1)), [])
    }

    func testWhenFourteenDaysHavePassed_ThenTheInstallationIsDueOnce() {
        store.recordInstallation(of: "bitwarden-id", at: installDate)
        let checkDate = installDate.addingTimeInterval(WebExtensionRetentionStore.retentionPeriod)

        XCTAssertEqual(store.takeDue(at: checkDate), ["bitwarden-id"])
        XCTAssertEqual(store.takeDue(at: checkDate.addingTimeInterval(60 * 60)), [])
    }

    func testWhenOnlySomeInstallationsAreDue_ThenTheOthersKeepWaiting() {
        store.recordInstallation(of: "old-id", at: installDate)
        store.recordInstallation(of: "new-id", at: installDate.addingTimeInterval(7 * 24 * 60 * 60))
        let firstCheck = installDate.addingTimeInterval(WebExtensionRetentionStore.retentionPeriod)

        XCTAssertEqual(store.takeDue(at: firstCheck), ["old-id"])
        XCTAssertEqual(store.takeDue(at: firstCheck.addingTimeInterval(7 * 24 * 60 * 60)), ["new-id"])
    }

    func testWhenAnExtensionIsInstalledAgain_ThenItsWaitRestarts() {
        store.recordInstallation(of: "bitwarden-id", at: installDate)
        let reinstallDate = installDate.addingTimeInterval(10 * 24 * 60 * 60)
        store.recordInstallation(of: "bitwarden-id", at: reinstallDate)

        XCTAssertEqual(store.takeDue(at: installDate.addingTimeInterval(WebExtensionRetentionStore.retentionPeriod)), [])
        XCTAssertEqual(store.takeDue(at: reinstallDate.addingTimeInterval(WebExtensionRetentionStore.retentionPeriod)), ["bitwarden-id"])
    }
}
