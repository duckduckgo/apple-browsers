//
//  PrivacyUserDefaultsTests.swift
//  DuckDuckGo
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

import Foundation
import Testing
@testable import DuckDuckGo

final class PrivacyUserDefaultsTests {

    @Test("Enabling authentication posts authentication-enabled-changed notification")
    func whenAuthenticationChangesFromDisabledToEnabledThenNotificationIsPosted() async throws {
        let suiteName = "PrivacyUserDefaultsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let privacyStore = PrivacyUserDefaults(userDefaults: userDefaults)
        #expect(!privacyStore.authenticationEnabled)

        await confirmation { notificationReceived in
            let observer = NotificationCenter.default.addObserver(
                forName: PrivacyUserDefaults.Notifications.authenticationEnabledChanged,
                object: nil,
                queue: nil) { notification in
                #expect(notification.object as? Bool == true)
                notificationReceived()
            }
            defer {
                NotificationCenter.default.removeObserver(observer)
            }

            privacyStore.authenticationEnabled = true
        }
    }
}
