//
//  WebsitePermissionDefaultsTests.swift
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
import FeatureFlags_macOS
@_spi(Testing) import Persistence
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class WebsitePermissionDefaultsTests: XCTestCase {

    private var keyValueStore: MockKeyValueFileStore!
    private var featureFlagger: MockFeatureFlagger!
    private var autoplayPreferences: AutoplayPreferences!
    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        keyValueStore = try MockKeyValueFileStore()
        featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.websitePermissionsSettings.rawValue: true])
        autoplayPreferences = AutoplayPreferences(
            persistor: AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        )
        cancellables = []
    }

    override func tearDown() {
        keyValueStore = nil
        featureFlagger = nil
        autoplayPreferences = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Reading

    func testWhenNothingIsStoredThenEveryCategoryDefaultsToAskEachTime() {
        let sut = makeSUT()

        for category in WebsitePermissionCategory.allCases where category != .autoplay {
            XCTAssertEqual(sut.defaultDecision(for: category), .ask, "\(category) should fall back to .ask")
        }
    }

    func testWhenStoredValueIsNotAnOfferedDefaultThenAskEachTimeIsReturned() throws {
        // "allow" is not an offered default, so both it and an unparseable value can only come from tampering.
        for rawValue in ["nonsense", PersistedPermissionDecision.allow.rawValue] {
            try keyValueStore.set(rawValue, forKey: WebsitePermissionDefaultsUserDefaultsStorage.Key.camera.rawValue)

            XCTAssertEqual(makeSUT().defaultDecision(for: .camera), .ask, "stored \(rawValue) should read back as .ask")
        }
    }

    // MARK: - Writing

    func testWhenDecisionIsSetThenItIsPersistedAndReadBackByANewInstance() {
        makeSUT().setDefaultDecision(.deny, for: .notifications)

        let reloaded = makeSUT()
        XCTAssertEqual(reloaded.defaultDecision(for: .notifications), .deny)
        XCTAssertEqual(reloaded.defaultDecision(for: .camera), .ask, "Other categories should be untouched")

        reloaded.setDefaultDecision(.allow, for: .camera)

        XCTAssertEqual(reloaded.defaultDecision(for: .camera), .ask, "Allow is not an offered default")
        XCTAssertNil(persistedRawValue(for: .camera))
    }

    func testWhenDecisionChangesThenPublisherEmitsOnlyTheRealUpdates() {
        let sut = makeSUT()
        var published: [[WebsitePermissionCategory: PersistedPermissionDecision]] = []
        sut.defaultsPublisher.sink { published.append($0) }.store(in: &cancellables)

        sut.setDefaultDecision(.deny, for: .location)

        XCTAssertEqual(published.count, 2, "Expected the current value plus one update")
        XCTAssertEqual(published.first?[.location], .ask)
        XCTAssertEqual(published.last?[.location], .deny)

        sut.setDefaultDecision(.deny, for: .location)

        XCTAssertEqual(published.count, 2, "Setting the same decision again should publish nothing")
    }

    // MARK: - Feature flag

    func testWhenFeatureFlagIsOffThenReadsReturnAskEachTimeAndWritesAreIgnored() {
        featureFlagger.featuresStub = [FeatureFlag.websitePermissionsSettings.rawValue: false]
        let sut = makeSUT()

        sut.setDefaultDecision(.deny, for: .camera)

        XCTAssertEqual(sut.defaultDecision(for: .camera), .ask)
        XCTAssertNil(persistedRawValue(for: .camera))
    }

    func testWhenFeatureFlagIsTurnedOffThenStoredDecisionsAreIgnoredButPreserved() {
        let sut = makeSUT()
        sut.setDefaultDecision(.deny, for: .camera)

        featureFlagger.featuresStub = [FeatureFlag.websitePermissionsSettings.rawValue: false]
        XCTAssertEqual(sut.defaultDecision(for: .camera), .ask)

        featureFlagger.featuresStub = [FeatureFlag.websitePermissionsSettings.rawValue: true]
        XCTAssertEqual(sut.defaultDecision(for: .camera), .deny, "Re-enabling the flag should restore the stored default")
    }

    func testWhenFeatureFlagFlipsThenPublisherEmitsTheEffectiveDecisions() {
        let sut = makeSUT()
        sut.setDefaultDecision(.deny, for: .camera)

        var published: [[WebsitePermissionCategory: PersistedPermissionDecision]] = []
        sut.defaultsPublisher.dropFirst().sink { published.append($0) }.store(in: &cancellables)

        featureFlagger.featuresStub = [FeatureFlag.websitePermissionsSettings.rawValue: false]
        featureFlagger.triggerUpdate()

        XCTAssertEqual(published.last?[.camera], .ask)
    }

    // MARK: - Autoplay

    func testWhenAutoplayDefaultIsReadThenItMirrorsTheAllSitesBlockingMode() {
        let sut = makeSUT()
        XCTAssertEqual(sut.defaultDecision(for: .autoplay), .ask, "Block audio is the middle state")

        autoplayPreferences.autoplayBlockingMode = .allowAll
        XCTAssertEqual(sut.defaultDecision(for: .autoplay), .allow)

        autoplayPreferences.autoplayBlockingMode = .blockAll
        XCTAssertEqual(sut.defaultDecision(for: .autoplay), .deny)
    }

    func testWhenAutoplayDefaultIsSetThenTheAllSitesBlockingModeChanges() {
        let sut = makeSUT()

        sut.setDefaultDecision(.allow, for: .autoplay)

        XCTAssertEqual(autoplayPreferences.autoplayBlockingMode, .allowAll)
        XCTAssertEqual(sut.defaultDecision(for: .autoplay), .allow)
        XCTAssertNil(persistedRawValue(for: .autoplay), "Autoplay has no default of its own to store")
    }

    func testWhenAutoplayDefaultIsSetThenOtherCategoriesStillRejectAllow() {
        let sut = makeSUT()

        sut.setDefaultDecision(.allow, for: .camera)

        XCTAssertEqual(sut.defaultDecision(for: .camera), .ask)
    }

    func testWhenBlockingModeChangesElsewhereThenPublisherEmitsTheNewAutoplayDefault() {
        let sut = makeSUT()
        var published: [[WebsitePermissionCategory: PersistedPermissionDecision]] = []
        sut.defaultsPublisher.sink { published.append($0) }.store(in: &cancellables)

        autoplayPreferences.autoplayBlockingMode = .blockAll

        XCTAssertEqual(published.first?[.autoplay], .ask)
        XCTAssertEqual(published.last?[.autoplay], .deny)
    }

    func testWhenFeatureFlagIsOffThenAutoplayWritesAreIgnored() {
        featureFlagger.featuresStub = [FeatureFlag.websitePermissionsSettings.rawValue: false]
        let sut = makeSUT()

        sut.setDefaultDecision(.deny, for: .autoplay)

        XCTAssertEqual(autoplayPreferences.autoplayBlockingMode, .blockAudio)
        XCTAssertEqual(sut.defaultDecision(for: .autoplay), .ask)
    }

    // MARK: - Helpers

    private func makeSUT() -> WebsitePermissionDefaults {
        WebsitePermissionDefaults(
            storage: WebsitePermissionDefaultsUserDefaultsStorage(keyValueStore: keyValueStore),
            featureFlagger: featureFlagger,
            autoplayPreferences: autoplayPreferences
        )
    }

    private func persistedRawValue(for category: WebsitePermissionCategory) -> String? {
        guard let key = WebsitePermissionDefaultsUserDefaultsStorage.Key(category: category) else { return nil }
        return try? keyValueStore.object(forKey: key.rawValue) as? String
    }
}
