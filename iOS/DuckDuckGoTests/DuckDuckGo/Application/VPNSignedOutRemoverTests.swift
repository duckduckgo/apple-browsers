//
//  VPNSignedOutRemoverTests.swift
//  DuckDuckGo
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
@_spi(Testing) import Networking
import SubscriptionTestingUtilities
@testable import DuckDuckGo

final class VPNSignedOutRemoverTests: XCTestCase {

    private var subscriptionManager: SubscriptionManagerMock!
    private var isVPNInstalled = true
    private var removeCallCount = 0

    override func setUp() {
        super.setUp()
        subscriptionManager = SubscriptionManagerMock()
        isVPNInstalled = true
        removeCallCount = 0
    }

    override func tearDown() {
        subscriptionManager = nil
        super.tearDown()
    }

    private func makeRemover() -> VPNSignedOutRemover {
        VPNSignedOutRemover(subscriptionManager: subscriptionManager,
                            isVPNInstalled: { [unowned self] in self.isVPNInstalled },
                            stopAndRemoveVPN: { [unowned self] in self.removeCallCount += 1 })
    }

    func testWhenMissingTokenIsRestoredFromBackupThenVPNIsKept() async {
        subscriptionManager.resultTokenContainer = nil
        subscriptionManager.restoreMissingTokenIfPossibleHandler = { [unowned self] in
            self.subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        }

        await makeRemover().removeVPNIfSignedOut()

        XCTAssertEqual(subscriptionManager.restoreMissingTokenIfPossibleCallCount, 1)
        XCTAssertEqual(removeCallCount, 0)
    }

    func testWhenMissingTokenCantBeRestoredThenVPNIsRemoved() async {
        subscriptionManager.resultTokenContainer = nil

        await makeRemover().removeVPNIfSignedOut()

        XCTAssertEqual(subscriptionManager.restoreMissingTokenIfPossibleCallCount, 1)
        XCTAssertEqual(removeCallCount, 1)
    }

    func testWhenSignedOutThenVPNIsRemovedOnlyAfterTheRestoreFinishes() async {
        subscriptionManager.resultTokenContainer = nil
        var events: [String] = []
        subscriptionManager.restoreMissingTokenIfPossibleHandler = { events.append("restore") }
        let remover = VPNSignedOutRemover(subscriptionManager: subscriptionManager,
                                          isVPNInstalled: { true },
                                          stopAndRemoveVPN: { events.append("remove") })

        await remover.removeVPNIfSignedOut()

        XCTAssertEqual(events, ["restore", "remove"])
    }

    func testWhenSignedInThenVPNIsKept() async {
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        await makeRemover().removeVPNIfSignedOut()

        XCTAssertEqual(removeCallCount, 0)
    }

    func testWhenSignedOutAndVPNIsNotInstalledThenNothingIsRemoved() async {
        subscriptionManager.resultTokenContainer = nil
        isVPNInstalled = false

        await makeRemover().removeVPNIfSignedOut()

        XCTAssertEqual(removeCallCount, 0)
    }
}
