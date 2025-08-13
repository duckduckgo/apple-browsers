//
//  AIChatSettingsMigrationTests.swift
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
@testable import Core
@testable import DuckDuckGo
import AIChat
import PersistenceTestingUtils

final class AIChatSettingsMigrationTests: XCTestCase {

    static let allKeys = [
        LegacyAiChatUserDefaultsKeys.isAIChatEnabledKey,
        LegacyAiChatUserDefaultsKeys.showAIChatBrowsingMenuKey,
        LegacyAiChatUserDefaultsKeys.showAIChatAddressBarKey,
        LegacyAiChatUserDefaultsKeys.showAIChatVoiceSearchKey,
        LegacyAiChatUserDefaultsKeys.showAIChatTabSwitcherKey,
        LegacyAiChatUserDefaultsKeys.showAIChatExperimentalSearchInputKey,
    ]


    func testWhenAllKeysArePresentTheyAreAllMigrated() throws {
        let suiteName = UUID().uuidString
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let keys = Self.allKeys
        keys.forEach {
            userDefaults.set(true, forKey: $0)
        }

        keys.forEach {
            XCTAssertNotNil(userDefaults.object(forKey: $0))
        }

        let keyValueStore = MockKeyValueStore()
        AIChatSettingsMigration.migrate(from: userDefaults, to: {
            keyValueStore
        })

        keys.forEach {
            XCTAssertNil(userDefaults.object(forKey: $0))
            XCTAssertEqual(keyValueStore.object(forKey: $0) as? Bool, true)
        }
    }

    func testWhenSubsetOfKeysPresentTheyAreMigratedAndOthersAreNot() throws {
        for key in Self.allKeys {
            let suiteName = UUID().uuidString
            let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer {
                userDefaults.removePersistentDomain(forName: suiteName)
            }
            userDefaults.set(true, forKey: key)

            let keyValueStore = MockKeyValueStore()
            AIChatSettingsMigration.migrate(from: userDefaults, to: {
                keyValueStore
            })

            for checkKey in Self.allKeys {
                if checkKey == key {
                    XCTAssertEqual(keyValueStore.object(forKey: checkKey) as? Bool, true)
                } else {
                    XCTAssertNil(keyValueStore.object(forKey: checkKey))
                }
            }
        }
    }

}
