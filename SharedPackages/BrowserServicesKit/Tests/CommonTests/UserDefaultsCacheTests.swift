//
//  UserDefaultsCacheTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
@testable import Common

final class UserDefaultsCacheTests: XCTestCase {

    private var userDefaults: UserDefaults!
    var cache: UserDefaultsCache<TestObject>!
    let testKey = UserDefaultsCacheKey.subscription
    let settings = UserDefaultsCacheSettings(defaultExpirationInterval: 300) // 5 minutes

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: #file)
        userDefaults.removePersistentDomain(forName: #file)
        cache = UserDefaultsCache<TestObject>(userDefaults: userDefaults, key: testKey, settings: settings)
    }

    override func tearDown() {
        // Clean up UserDefaults after tests
        userDefaults.removePersistentDomain(forName: #file)
        super.tearDown()
    }

    func testSetObject() {
        let testObject = TestObject(name: "Test")
        cache.set(testObject)
        let data = userDefaults?.data(forKey: testKey.rawValue)
        XCTAssertNotNil(data, "Data should be stored in UserDefaults")
    }

    func testGetObjectNotExpired() {
        let testObject = TestObject(name: "Test")
        cache.set(testObject)
        let fetchedObject = cache.get()
        XCTAssertNotNil(fetchedObject, "Should retrieve the object as it is not expired")
        XCTAssertEqual(fetchedObject?.name, "Test", "The fetched object should have the correct properties")
    }

    func testGetObjectExpired() {
        let testObject = TestObject(name: "Test")
        // Set with a past expiration date
        cache.set(testObject, expires: Date().addingTimeInterval(-3600))
        let fetchedObject = cache.get()
        XCTAssertNil(fetchedObject, "Should not retrieve the object as it has expired")
    }

    func testReset() {
        let testObject = TestObject(name: "Test")
        cache.set(testObject)
        cache.reset()
        let data = userDefaults?.data(forKey: testKey.rawValue)
        XCTAssertNil(data, "UserDefaults should be empty after reset")
    }
}

struct TestObject: Codable, Equatable {
    let name: String
}
