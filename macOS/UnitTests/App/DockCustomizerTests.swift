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

import AppKitExtensions

import Combine
import Common
import FeatureFlags_macOS
import FoundationExtensions
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DockCustomizerTests: XCTestCase {

    private static let keyValueStoreSuiteName = "DockCustomizerTests"

    private var keyValueStore: UserDefaults!
    private var dockMembershipProvider: MockDockMembershipProvider!
    private var featureFlagger: MockFeatureFlagger!

    override func setUpWithError() throws {
        try super.setUpWithError()
        keyValueStore = UserDefaults(suiteName: Self.keyValueStoreSuiteName)
        dockMembershipProvider = MockDockMembershipProvider()
        featureFlagger = MockFeatureFlagger()
    }

    override func tearDownWithError() throws {
        keyValueStore.removePersistentDomain(forName: Self.keyValueStoreSuiteName)
        keyValueStore = nil
        dockMembershipProvider = nil
        featureFlagger = nil
        try super.tearDownWithError()
    }

    func testWhenAppStoreBuildThenAddToDockReturnsFalse() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = true

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            dockMembershipProvider: dockMembershipProvider
        )

        let result = sut.addToDock()

        XCTAssertFalse(result)
    }

    func testWhenAppStoreBuildThenSupportsAddingToDockIsFalse() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = true

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore
        )

        XCTAssertFalse(sut.supportsAddingToDock)
    }

    func testWhenNotAppStoreBuildThenSupportsAddingToDockIsTrue() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = false

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore
        )

        XCTAssertTrue(sut.supportsAddingToDock)
    }

    func testWhenAppStoreBuildWithFlagOnIsSynchronizedThenNotificationPublisherIsTrue() {
        UserDefaultsWrapper<Any>.clearAll()
        addTeardownBlock {
            UserDefaultsWrapper<Any>.sharedDefaults
                .set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
        }
        UserDefaultsWrapper<Any>.sharedDefaults
            .set(Date().addingTimeInterval(.days(-3)), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)

        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = true
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = true
        let sut = DockCustomizer(
            applicationBuildType: buildType,
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            dockMembershipProvider: dockMembershipProvider
        )
        var receivedValues: [Bool] = []
        let cancellable = sut.shouldShowNotificationPublisher.sink { receivedValues.append($0) }

        sut.synchronizeNotificationVisibilityWithFirstLaunchDate()

        XCTAssertEqual(receivedValues.last, true)
        cancellable.cancel()
    }

    func testWhenAppStoreBuildWithFlagOffIsSynchronizedThenNotificationPublisherStaysFalse() {
        UserDefaultsWrapper<Any>.clearAll()
        addTeardownBlock {
            UserDefaultsWrapper<Any>.sharedDefaults
                .set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
        }
        UserDefaultsWrapper<Any>.sharedDefaults
            .set(Date().addingTimeInterval(.days(-3)), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)

        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = true
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = false
        let sut = DockCustomizer(
            applicationBuildType: buildType,
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            dockMembershipProvider: dockMembershipProvider
        )
        var receivedValues: [Bool] = []
        let cancellable = sut.shouldShowNotificationPublisher.sink { receivedValues.append($0) }

        sut.synchronizeNotificationVisibilityWithFirstLaunchDate()

        XCTAssertEqual(receivedValues.last, false)
        cancellable.cancel()
    }

    func testWhenAppStoreFlagTurnsOffWhileRunningThenShouldShowNotificationIsFalse() {
        UserDefaultsWrapper<Any>.clearAll()
        addTeardownBlock {
            UserDefaultsWrapper<Any>.sharedDefaults
                .set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
        }
        UserDefaultsWrapper<Any>.sharedDefaults
            .set(Date().addingTimeInterval(.days(-3)), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)

        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = true
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = true
        let sut = DockCustomizer(
            applicationBuildType: buildType,
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            dockMembershipProvider: dockMembershipProvider
        )
        XCTAssertTrue(sut.shouldShowNotification)

        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = false

        XCTAssertFalse(sut.shouldShowNotification)
    }

    func testWhenAppStoreBuildHasDirectDownloadDotKeySavedThenNotificationIsStillShown() {
        setFirstLaunchDateThreeDaysAgo()
        keyValueStore.set(true, forKey: DockCustomizer.Keys.wasNotificationShownToUser)
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = true
        let sut = makeSUT(isAppStoreBuild: true)

        XCTAssertTrue(sut.shouldShowNotification)
    }

    func testWhenNotAppStoreBuildHasDotKeySavedThenNotificationIsNotShown() {
        setFirstLaunchDateThreeDaysAgo()
        keyValueStore.set(true, forKey: DockCustomizer.Keys.wasNotificationShownToUser)
        let sut = makeSUT(isAppStoreBuild: false)

        XCTAssertFalse(sut.shouldShowNotification)
    }

    func testWhenMoreOptionsMenuClosesWithoutDotThenDotIsShownWhenFlagTurnsOn() {
        setFirstLaunchDateThreeDaysAgo()
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = false
        let sut = makeSUT(isAppStoreBuild: true)
        sut.synchronizeNotificationVisibilityWithFirstLaunchDate()

        sut.didCloseMoreOptionsMenu()
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = true

        XCTAssertTrue(sut.shouldShowNotification)
    }

    func testWhenItemDotShowsBeforeButtonDotRefreshesThenClosingMenuHidesDot() {
        setFirstLaunchDateThreeDaysAgo()
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = false
        let sut = makeSUT(isAppStoreBuild: true)
        sut.synchronizeNotificationVisibilityWithFirstLaunchDate()
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = true

        sut.didCloseMoreOptionsMenu()

        XCTAssertFalse(sut.shouldShowNotification)
    }

    func testWhenMoreOptionsMenuClosesWithDotThenDotIsHidden() {
        setFirstLaunchDateThreeDaysAgo()
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = true
        let sut = makeSUT(isAppStoreBuild: true)
        var receivedValues: [Bool] = []
        let cancellable = sut.shouldShowNotificationPublisher.sink { receivedValues.append($0) }
        sut.synchronizeNotificationVisibilityWithFirstLaunchDate()

        sut.didCloseMoreOptionsMenu()

        XCTAssertEqual(receivedValues.last, false)
        XCTAssertFalse(sut.shouldShowNotification)
        cancellable.cancel()
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
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            dockMembershipProvider: dockMembershipProvider
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
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            dockMembershipProvider: dockMembershipProvider
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

        let threeDaysAgo = Date().addingTimeInterval(.days(-3))
        UserDefaultsWrapper<Any>.sharedDefaults
            .set(threeDaysAgo, forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)

        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = false

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            dockMembershipProvider: dockMembershipProvider
        )

        XCTAssertTrue(sut.shouldShowNotification)

        var receivedValues: [Bool] = []
        let cancellable = sut.shouldShowNotificationPublisher.sink { receivedValues.append($0) }

        sut.synchronizeNotificationVisibilityWithFirstLaunchDate()

        XCTAssertEqual(receivedValues.last, true)
        cancellable.cancel()
    }

    func testWhenAppAlreadyInDockThenShouldShowNotificationIsFalseEvenWhenTwoDaysPassed() {
        UserDefaultsWrapper<Any>.clearAll()
        addTeardownBlock {
            UserDefaults(suiteName: "\(Bundle.main.bundleIdentifier!).\(AppVersion.runType)")!
                .set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
        }

        let defaults = UserDefaults(suiteName: "\(Bundle.main.bundleIdentifier!).\(AppVersion.runType)")!
        let threeDaysAgo = Date().addingTimeInterval(.days(-3))
        defaults.set(threeDaysAgo, forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)

        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = false

        let sut = DockCustomizer(
            applicationBuildType: buildType,
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            dockMembershipProvider: MockDockMembershipProvider(isInDock: true)
        )

        XCTAssertFalse(sut.shouldShowNotification)

        var receivedValues: [Bool] = []
        let cancellable = sut.shouldShowNotificationPublisher.sink { receivedValues.append($0) }

        sut.synchronizeNotificationVisibilityWithFirstLaunchDate()

        XCTAssertEqual(receivedValues.last, false)
        cancellable.cancel()
    }

    private func setFirstLaunchDateThreeDaysAgo() {
        UserDefaultsWrapper<Any>.clearAll()
        addTeardownBlock {
            UserDefaultsWrapper<Any>.sharedDefaults
                .set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
        }
        UserDefaultsWrapper<Any>.sharedDefaults
            .set(Date().addingTimeInterval(.days(-3)), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
    }

    private func makeSUT(isAppStoreBuild: Bool) -> DockCustomizer {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = isAppStoreBuild
        return DockCustomizer(
            applicationBuildType: buildType,
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            dockMembershipProvider: dockMembershipProvider
        )
    }

}

/// Fixed Dock membership so notification eligibility tests do not depend on the test host being pinned in the real Dock.
private final class MockDockMembershipProvider: DockMembershipProviding {
    var isInDock: Bool

    init(isInDock: Bool = false) {
        self.isInDock = isInDock
    }

    func isBundleIdentifierInDock(_ bundleIdentifier: String?) -> Bool {
        isInDock
    }
}
