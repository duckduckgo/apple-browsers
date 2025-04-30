//
//  FeatureDiscoveryTests.swift
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
@testable import Core
import PersistenceTestingUtils

final class DefaultFeatureDiscoveryTests: XCTestCase {

    var featureDiscovery: DefaultFeatureDiscovery!
    var mockStorage: MockKeyValueStore!

    override func setUp() {
        super.setUp()
        mockStorage = MockKeyValueStore()
        featureDiscovery = DefaultFeatureDiscovery(wasUsedBeforeStorage: mockStorage)
    }

    override func tearDown() {
        featureDiscovery = nil
        mockStorage = nil
        super.tearDown()
    }

    func testSetWasUsedBefore() {
        featureDiscovery.setWasUsedBefore(.aiChat)
        XCTAssertTrue(mockStorage.object(forKey: WasUsedBeforeFeature.aiChat.storageKey) as? Bool ?? false)
    }

    func testWasUsedBeforeWhenSet() {
        mockStorage.set(true, forKey: WasUsedBeforeFeature.duckPlayer.storageKey)
        XCTAssertTrue(featureDiscovery.wasUsedBefore(.duckPlayer))
    }

    func testWasUsedBeforeWhenNotSet() {
        XCTAssertFalse(featureDiscovery.wasUsedBefore(.vpn))
    }

    func testAddToParamsWhenUsedBefore() {
        mockStorage.set(true, forKey: WasUsedBeforeFeature.privacyDashboard.storageKey)
        let params = featureDiscovery.addToParams(["key": "value"], forFeature: .privacyDashboard)
        XCTAssertEqual(params["was_used_before"], "1")
    }

    func testAddToParamsWhenNotUsedBefore() {
        let params = featureDiscovery.addToParams(["key": "value"], forFeature: .privacyDashboard)
        XCTAssertEqual(params["was_used_before"], "0")
    }
}
