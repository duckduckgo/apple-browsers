//
//  DockCustomizerTests.swift
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

import Combine
import Common
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DockCustomizerTests: XCTestCase {

    private static let keyValueStoreSuiteName = "DockCustomizerTests"

    private var keyValueStore: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        keyValueStore = UserDefaults(suiteName: Self.keyValueStoreSuiteName)
    }

    override func tearDownWithError() throws {
        keyValueStore.removePersistentDomain(forName: Self.keyValueStoreSuiteName)
        keyValueStore = nil
        try super.tearDownWithError()
    }

    func testWhenAppStoreBuildThenAddToDockReturnsFalse() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = true

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            keyValueStore: keyValueStore
        )

        let result = sut.addToDock()

        XCTAssertFalse(result)
    }

    func testWhenAppStoreBuildThenSupportsAddingToDockIsFalse() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = true

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            keyValueStore: keyValueStore
        )

        XCTAssertFalse(sut.supportsAddingToDock)
    }

    func testWhenNotAppStoreBuildThenSupportsAddingToDockIsTrue() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = false

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            keyValueStore: keyValueStore
        )

        XCTAssertTrue(sut.supportsAddingToDock)
    }

    func testWhenAppStoreBuildThenNotificationTimerIsNotStarted() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = true

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            keyValueStore: keyValueStore
        )

        let expectation = expectation(description: "Publisher emits")
        var receivedValue: Bool?
        let cancellable = sut.shouldShowNotificationPublisher
            .first()
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(receivedValue, false)
    }

    /// Without a stored `firstLaunchDate`, `AppDelegate` falls back to a default “old” date so computed dock notification eligibility is `true`,
    /// but the published value must stay `false` until `synchronizeNotificationVisibilityWithFirstLaunchDate()` runs (after real install date is written).
    func testWhenNotAppStoreBuildWithoutSynchronizeThenPublisherDoesNotMirrorStaleFirstLaunchEligibility() {
        UserDefaultsWrapper<Any>.clearAll()
        addTeardownBlock {
            UserDefaultsWrapper<Any>.sharedDefaults
                .set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
        }

        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = false

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            keyValueStore: keyValueStore
        )

        XCTAssertTrue(sut.shouldShowNotification)

        let expectation = expectation(description: "Publisher emits")
        let cancellable = sut.shouldShowNotificationPublisher
            .first()
            .sink { value in
                XCTAssertFalse(value)
                expectation.fulfill()
            }

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testWhenSynchronizedAfterFirstLaunchDateSetToNowThenNotificationMatchesShouldShowNotification() {
        UserDefaultsWrapper<Any>.clearAll()
        addTeardownBlock {
            UserDefaultsWrapper<Any>.sharedDefaults
                .set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
        }

        UserDefaultsWrapper<Any>.sharedDefaults
            .set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)

        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = false

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            keyValueStore: keyValueStore
        )

        XCTAssertFalse(sut.shouldShowNotification)
        sut.synchronizeNotificationVisibilityWithFirstLaunchDate()
        XCTAssertFalse(sut.shouldShowNotification)

        let expectation = expectation(description: "Publisher emits after sync")
        var receivedValue: Bool?
        let cancellable = sut.shouldShowNotificationPublisher
            .first()
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(receivedValue, false)
    }

    func testWhenSynchronizedAfterFirstLaunchDateOlderThanTwoDaysThenNotificationPublisherIsTrue() {
        UserDefaultsWrapper<Any>.clearAll()
        addTeardownBlock {
            UserDefaultsWrapper<Any>.sharedDefaults
                .set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
        }

        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        UserDefaultsWrapper<Any>.sharedDefaults
            .set(threeDaysAgo, forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)

        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = false

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            keyValueStore: keyValueStore
        )

        XCTAssertTrue(sut.shouldShowNotification)

        var receivedValues: [Bool] = []
        let cancellable = sut.shouldShowNotificationPublisher.sink { receivedValues.append($0) }

        sut.synchronizeNotificationVisibilityWithFirstLaunchDate()

        XCTAssertEqual(receivedValues, [false, true])
        cancellable.cancel()
    }

}
