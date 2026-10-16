//
//  WebExtensionIdleStateProviderTests.swift
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

#if os(macOS)

import XCTest
@testable import WebExtensions

final class WebExtensionIdleStateProviderTests: XCTestCase {

    private var secondsSinceLastInput: TimeInterval = 0
    private var notificationCenter: NotificationCenter!
    private var provider: WebExtensionIdleStateProvider!

    override func setUp() {
        super.setUp()
        secondsSinceLastInput = 0
        notificationCenter = NotificationCenter()
        provider = WebExtensionIdleStateProvider(secondsSinceLastInput: { [unowned self] in secondsSinceLastInput },
                                                 notificationCenter: notificationCenter)
    }

    override func tearDown() {
        provider = nil
        notificationCenter = nil
        super.tearDown()
    }

    // MARK: - State

    func testWhenInputIsRecent_ThenTheStateIsActive() {
        secondsSinceLastInput = 14

        XCTAssertEqual(provider.state(detectionInterval: 60), .active)
    }

    func testWhenInputIsAsOldAsTheThreshold_ThenTheStateIsIdle() {
        secondsSinceLastInput = 60

        XCTAssertEqual(provider.state(detectionInterval: 60), .idle)
    }

    func testWhenInputIsOlderThanTheThreshold_ThenTheStateIsIdle() {
        secondsSinceLastInput = 61

        XCTAssertEqual(provider.state(detectionInterval: 60), .idle)
    }

    func testWhenTheThresholdIsBelowTheMinimum_ThenItIsRaisedTo15Seconds() {
        secondsSinceLastInput = 10
        XCTAssertEqual(provider.state(detectionInterval: 1), .active)

        secondsSinceLastInput = 15
        XCTAssertEqual(provider.state(detectionInterval: 1), .idle)
    }

    func testWhenTheThresholdIsNotANumber_ThenTheDefaultIsUsed() {
        secondsSinceLastInput = 59
        XCTAssertEqual(provider.state(detectionInterval: .nan), .active)

        secondsSinceLastInput = 60
        XCTAssertEqual(provider.state(detectionInterval: .nan), .idle)
    }

    // MARK: - Screen Lock

    func testWhenTheScreenIsLocked_ThenTheStateIsLockedEvenIfInputIsOld() {
        secondsSinceLastInput = 600

        notificationCenter.post(name: WebExtensionIdleStateProvider.screenLockedNotification, object: nil)

        XCTAssertEqual(provider.state(detectionInterval: 60), .locked)
    }

    func testWhenTheScreenIsUnlocked_ThenTheStateFollowsInputAgain() {
        notificationCenter.post(name: WebExtensionIdleStateProvider.screenLockedNotification, object: nil)
        notificationCenter.post(name: WebExtensionIdleStateProvider.screenUnlockedNotification, object: nil)

        secondsSinceLastInput = 600
        XCTAssertEqual(provider.state(detectionInterval: 60), .idle)

        secondsSinceLastInput = 1
        XCTAssertEqual(provider.state(detectionInterval: 60), .active)
    }

    func testWhenTheProviderIsReleased_ThenItStopsObserving() {
        weak var weakProvider = provider
        provider = nil

        XCTAssertNil(weakProvider)
        notificationCenter.post(name: WebExtensionIdleStateProvider.screenLockedNotification, object: nil)
    }
}

#endif
