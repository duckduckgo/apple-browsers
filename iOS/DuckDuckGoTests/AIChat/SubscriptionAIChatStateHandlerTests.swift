//
//  SubscriptionAIChatStateHandlerTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

final class SubscriptionAIChatStateHandlerTests: XCTestCase {

    var sut: SubscriptionAIChatStateHandler!

    override func setUp() {
        super.setUp()
        sut = SubscriptionAIChatStateHandler()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState_shouldForceAIChatRefreshIsFalse() {
        XCTAssertFalse(sut.shouldForceAIChatRefresh)
    }

    func testInitialState_onSubscriptionStateChangedIsNil() {
        XCTAssertNil(sut.onSubscriptionStateChanged)
    }

    // MARK: - Subscription Did Change

    func testWhenSubscriptionDidChangeNotificationPosted_shouldForceAIChatRefreshBecomesTrue() {
        let expectation = expectation(description: "flag set")
        sut.onSubscriptionStateChanged = {
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .subscriptionDidChange, object: nil)

        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(sut.shouldForceAIChatRefresh)
    }

    func testWhenSubscriptionDidChangeNotificationPosted_onSubscriptionStateChangedIsCalled() {
        let expectation = expectation(description: "onSubscriptionStateChanged called")
        sut.onSubscriptionStateChanged = {
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .subscriptionDidChange, object: nil)

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Account Did Sign In

    func testWhenAccountDidSignInNotificationPosted_shouldForceAIChatRefreshBecomesTrue() {
        let expectation = expectation(description: "flag set")
        sut.onSubscriptionStateChanged = {
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .accountDidSignIn, object: nil)

        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(sut.shouldForceAIChatRefresh)
    }

    func testWhenAccountDidSignInNotificationPosted_onSubscriptionStateChangedIsCalled() {
        let expectation = expectation(description: "onSubscriptionStateChanged called")
        sut.onSubscriptionStateChanged = {
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .accountDidSignIn, object: nil)

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Account Did Sign Out

    func testWhenAccountDidSignOutNotificationPosted_shouldForceAIChatRefreshBecomesTrue() {
        let expectation = expectation(description: "flag set")
        sut.onSubscriptionStateChanged = {
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .accountDidSignOut, object: nil)

        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(sut.shouldForceAIChatRefresh)
    }

    func testWhenAccountDidSignOutNotificationPosted_onSubscriptionStateChangedIsCalled() {
        let expectation = expectation(description: "onSubscriptionStateChanged called")
        sut.onSubscriptionStateChanged = {
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .accountDidSignOut, object: nil)

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Reset

    func testWhenResetCalled_shouldForceAIChatRefreshBecomesFalse() {
        let expectation = expectation(description: "flag set")
        sut.onSubscriptionStateChanged = {
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .subscriptionDidChange, object: nil)

        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(sut.shouldForceAIChatRefresh)

        sut.reset()

        XCTAssertFalse(sut.shouldForceAIChatRefresh)
    }
}
