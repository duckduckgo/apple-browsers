//
//  RemoteMessagingPercentileUserDefaultsStoreTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PersistenceTestingUtils
@testable import RemoteMessaging

class RemoteMessagingPercentileUserDefaultsStoreTests: XCTestCase {

    private var keyValueStore: MockKeyValueStore!

    override func setUp() {
        super.setUp()
        keyValueStore = MockKeyValueStore()
    }

    func testWhenFetchingPercentileForFirstTime_ThenPercentileIsCreatedAndStored() {
        let store = RemoteMessagingPercentileUserDefaultsStore(keyValueStore: keyValueStore)
        let percentile = store.percentile(forMessageId: "message-1")

        XCTAssert(percentile >= 0.0)
        XCTAssert(percentile <= 1.0)
    }

    func testWhenFetchingPercentileMultipleTimes_ThenAllPercentileFetchesReturnSameValue() {
        let store = RemoteMessagingPercentileUserDefaultsStore(keyValueStore: keyValueStore)
        let percentile1 = store.percentile(forMessageId: "message-1")
        let percentile2 = store.percentile(forMessageId: "message-1")
        let percentile3 = store.percentile(forMessageId: "message-1")

        XCTAssertEqual(percentile1, percentile2)
        XCTAssertEqual(percentile2, percentile3)
    }

    func testWhenFetchingPercentileForMultipleMessages_ThenEachMessageHasIndependentPercentile() {
        let store = RemoteMessagingPercentileUserDefaultsStore(keyValueStore: keyValueStore)
        _ = store.percentile(forMessageId: "message-1")
        _ = store.percentile(forMessageId: "message-2")
        _ = store.percentile(forMessageId: "message-3")

        let key = RemoteMessagingPercentileUserDefaultsStore.Constants.remoteMessagingPercentileMapping

        let percentileDictionary = keyValueStore.object(forKey: key) as? [String: Float]

        XCTAssertEqual(percentileDictionary?.count, 3)
    }

}
