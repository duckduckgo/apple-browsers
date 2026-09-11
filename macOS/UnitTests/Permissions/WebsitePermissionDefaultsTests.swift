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
    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        keyValueStore = try MockKeyValueFileStore()
        featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.websitePermissionsSettings.rawValue: true])
        cancellables = []
    }

    override func tearDown() {
        keyValueStore = nil
        featureFlagger = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Reading

    func testWhenNothingIsStoredThenEveryCategoryDefaultsToAskEachTime() {
        let sut = makeSUT()

        for category in WebsitePermissionCategory.allCases {
            XCTAssertEqual(sut.defaultDecision(for: category), .ask, "\(category) should fall back to .ask")
        }
    }

    func testWhenStoredValueIsUnrecognisedThenAskEachTimeIsReturned() throws {
        try keyValueStore.set("nonsense", forKey: WebsitePermissionDefaultsUserDefaultsPersistor.Key.camera.rawValue)

        XCTAssertEqual(makeSUT().defaultDecision(for: .camera), .ask)
    }

    func testWhenStoredValueIsAllowThenAskEachTimeIsReturned() throws {
        // "Always allow" is not an offered default; a value like this can only come from tampering.
        try keyValueStore.set(PersistedPermissionDecision.allow.rawValue,
                              forKey: WebsitePermissionDefaultsUserDefaultsPersistor.Key.camera.rawValue)

        XCTAssertEqual(makeSUT().defaultDecision(for: .camera), .ask)
    }

    // MARK: - Writing

    func testWhenDecisionIsSetThenItIsPersistedAndReadBackByANewInstance() {
        makeSUT().setDefaultDecision(.deny, for: .notifications)

        let reloaded = makeSUT()
        XCTAssertEqual(reloaded.defaultDecision(for: .notifications), .deny)
        XCTAssertEqual(reloaded.defaultDecision(for: .camera), .ask, "Other categories should be untouched")
    }

    func testWhenAllowIsSetThenItIsIgnored() {
        let sut = makeSUT()

        sut.setDefaultDecision(.allow, for: .camera)

        XCTAssertEqual(sut.defaultDecision(for: .camera), .ask)
        XCTAssertNil(persistedRawValue(for: .camera))
    }

    func testWhenSameDecisionIsSetAgainThenNothingIsPublished() {
        let sut = makeSUT()
        sut.setDefaultDecision(.deny, for: .popups)

        var publishedCount = 0
        sut.defaultsPublisher.dropFirst().sink { _ in publishedCount += 1 }.store(in: &cancellables)

        sut.setDefaultDecision(.deny, for: .popups)

        XCTAssertEqual(publishedCount, 0)
    }

    func testWhenDecisionChangesThenPublisherEmitsTheUpdatedMap() {
        let sut = makeSUT()
        var published: [[WebsitePermissionCategory: PersistedPermissionDecision]] = []
        sut.defaultsPublisher.sink { published.append($0) }.store(in: &cancellables)

        sut.setDefaultDecision(.deny, for: .location)

        XCTAssertEqual(published.count, 2, "Expected the current value plus one update")
        XCTAssertEqual(published.first?[.location], .ask)
        XCTAssertEqual(published.last?[.location], .deny)
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

    // MARK: - Helpers

    private func makeSUT() -> WebsitePermissionDefaults {
        WebsitePermissionDefaults(
            persistor: WebsitePermissionDefaultsUserDefaultsPersistor(keyValueStore: keyValueStore),
            featureFlagger: featureFlagger
        )
    }

    private func persistedRawValue(for category: WebsitePermissionCategory) -> String? {
        try? keyValueStore.object(forKey: WebsitePermissionDefaultsUserDefaultsPersistor.Key(category: category).rawValue) as? String
    }
}
