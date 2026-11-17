//
//  SponsorBlockPreferencesTests.swift
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
@_spi(Testing) import Persistence
import XCTest
@testable import BrowserServicesKit

final class SponsorBlockPreferencesTests: XCTestCase {

    private var store: InMemoryKeyValueStore!
    private var notificationCenter: NotificationCenter!
    private var preferences: SponsorBlockPreferences!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        store = InMemoryKeyValueStore()
        notificationCenter = NotificationCenter()
        preferences = SponsorBlockPreferences(store: store, notificationCenter: notificationCenter)
    }

    func testDefaultsAreEnabledAndManual() {
        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(preferences.skipMode, .manual)
    }

    func testValuesPersistAcrossInstancesSharingTheStore() {
        preferences.isEnabled = false
        preferences.skipMode = .auto

        let other = SponsorBlockPreferences(store: store, notificationCenter: notificationCenter)
        XCTAssertFalse(other.isEnabled)
        XCTAssertEqual(other.skipMode, .auto)
    }

    func testEveryWriteEmitsOneUpdate() {
        var updates = 0
        preferences.updates.sink { updates += 1 }.store(in: &cancellables)

        preferences.isEnabled = false
        preferences.skipMode = .auto

        XCTAssertEqual(updates, 2)
    }
}
