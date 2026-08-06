//
//  YouTubeAdBlockingTelemetryConsentRequirementTests.swift
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
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class YouTubeAdBlockingTelemetryConsentRequirementTests: XCTestCase {

    private static let adBlockingEnabledKey = "preferences_youtube-ad-blocking_enabled"
    private static let analyticsEnabledKey = "preferences_youtube-analytics_enabled"

    private var defaults: UserDefaults!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "\(type(of: self))")!
        defaults.removePersistentDomain(forName: "\(type(of: self))")
        cancellables = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "\(type(of: self))")
        defaults = nil
        cancellables = nil
        super.tearDown()
    }

    func testConfigNamesAreStoredVerbatim() {
        let sut = YouTubeAdBlockingTelemetryConsentRequirement(configNames: ["a", "b"], store: defaults)
        XCTAssertEqual(sut.configNames, ["a", "b"])
    }

    func testIsGrantedPublisherEmitsFalseByDefault() {
        let sut = YouTubeAdBlockingTelemetryConsentRequirement(configNames: [], store: defaults)

        var received: [Bool] = []
        sut.isGrantedPublisher.sink { received.append($0) }.store(in: &cancellables)

        XCTAssertEqual(received, [false])
    }

    func testIsGrantedPublisherEmitsCurrentValueOnSubscribe() {
        defaults.set(true, forKey: Self.adBlockingEnabledKey)
        defaults.set(true, forKey: Self.analyticsEnabledKey)
        let sut = YouTubeAdBlockingTelemetryConsentRequirement(configNames: [], store: defaults)

        var received: [Bool] = []
        sut.isGrantedPublisher.sink { received.append($0) }.store(in: &cancellables)

        XCTAssertEqual(received, [true])
    }

    /// Both opt-ins are required, matching the composite check the retired `WebEventsSubfeature` applied.
    /// The two flags are independently writable defaults — nothing at the storage level guarantees that
    /// disabling ad blocking clears the analytics flag — so consent must not be granted on analytics alone.
    func testIsNotGrantedWhenAdBlockingIsOffButAnalyticsIsOn() {
        defaults.set(false, forKey: Self.adBlockingEnabledKey)
        defaults.set(true, forKey: Self.analyticsEnabledKey)
        let sut = YouTubeAdBlockingTelemetryConsentRequirement(configNames: [], store: defaults)

        var received: [Bool] = []
        sut.isGrantedPublisher.sink { received.append($0) }.store(in: &cancellables)

        XCTAssertEqual(received, [false])
    }

    /// The ad-blocking flag being unset (never explicitly chosen) must also withhold consent — the
    /// retired gate read it as `?? false`.
    func testIsNotGrantedWhenAdBlockingIsUnsetButAnalyticsIsOn() {
        defaults.set(true, forKey: Self.analyticsEnabledKey)
        let sut = YouTubeAdBlockingTelemetryConsentRequirement(configNames: [], store: defaults)

        var received: [Bool] = []
        sut.isGrantedPublisher.sink { received.append($0) }.store(in: &cancellables)

        XCTAssertEqual(received, [false])
    }

    func testIsNotGrantedWhenAdBlockingIsOnButAnalyticsIsOff() {
        defaults.set(true, forKey: Self.adBlockingEnabledKey)
        defaults.set(false, forKey: Self.analyticsEnabledKey)
        let sut = YouTubeAdBlockingTelemetryConsentRequirement(configNames: [], store: defaults)

        var received: [Bool] = []
        sut.isGrantedPublisher.sink { received.append($0) }.store(in: &cancellables)

        XCTAssertEqual(received, [false])
    }
}
