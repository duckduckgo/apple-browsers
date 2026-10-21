//
//  DefaultBrowserInfoStoreTests.swift
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

import Foundation
import Core
import Testing
import SetDefaultBrowserCore
@testable import DuckDuckGo

class DefaultBrowserInfoStoreTests {
    private static let userDefaultsKey = "com.duckduckgo.ios.defaultBrowserInfo"

    init() {
        UserDefaults.app.removeObject(forKey: Self.userDefaultsKey)
    }

    @Test
    func testDefaultInfoIsPersisted() throws {
        // GIVEN
        let timeInterval: TimeInterval = 1773122108000 // March 10, 2026
        let defaultBrowserInfo = DefaultBrowserContext(
            isDefaultBrowser: true,
            lastSuccessfulCheckDate: timeInterval,
            lastAttemptedCheckDate: timeInterval,
            numberOfTimesChecked: 10,
            nextRetryAvailableDate: timeInterval
        )
        let sut = DefaultBrowserInfoStore()

        // WHEN
        sut.defaultBrowserContext = defaultBrowserInfo

        // THEN
        let data = try #require(UserDefaults.app.data(forKey: Self.userDefaultsKey))
        let retrievedBrowserInfo = try JSONDecoder().decode(DefaultBrowserContext.self, from: data)
        #expect(retrievedBrowserInfo == defaultBrowserInfo)
    }

}
