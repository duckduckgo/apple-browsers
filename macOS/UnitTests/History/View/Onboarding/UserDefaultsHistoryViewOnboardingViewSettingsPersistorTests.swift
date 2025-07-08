//
//  UserDefaultsHistoryViewOnboardingViewSettingsPersistorTests.swift
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

import PersistenceTestingUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class UserDefaultsHistoryViewOnboardingViewSettingsPersistorTests: XCTestCase {
    var keyValueStore: MockKeyValueStore!
    var persistor: UserDefaultsHistoryViewOnboardingViewSettingsPersistor!

    override func setUp() async throws {
        keyValueStore = MockKeyValueStore()
        persistor = UserDefaultsHistoryViewOnboardingViewSettingsPersistor(keyValueStore)
    }

    override func tearDown() {
        keyValueStore = nil
        persistor = nil
    }

    func testWhenDidShowOnboardingViewIsNotPersistedThenItIsFalseByDefault() {
        keyValueStore.store = [:]
        XCTAssertFalse(persistor.didShowOnboardingView)
    }

    func testWhenDidShowOnboardingViewIsPersistedAsFalseThenPersistorReturnsFalse() {
        keyValueStore.store = [UserDefaultsHistoryViewOnboardingViewSettingsPersistor.Keys.didShowOnboardingView: false]
        XCTAssertFalse(persistor.didShowOnboardingView)
    }

    func testWhenDidShowOnboardingViewIsPersistedAsTrueThenPersistorReturnsTrue() {
        keyValueStore.store = [UserDefaultsHistoryViewOnboardingViewSettingsPersistor.Keys.didShowOnboardingView: true]
        XCTAssertTrue(persistor.didShowOnboardingView)
    }
}
