//
//  PrivacyUserDefaults.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

public class PrivacyUserDefaults: PrivacyStore {

    public enum Notifications {
        public static let authenticationEnabledChanged = Notification.Name("com.duckduckgo.privacy.authenticationEnabledChanged")
    }

    private struct Keys {
        static let authentication = "com.duckduckgo.privacy.authentication"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .app) {
        self.userDefaults = userDefaults
    }

    public var authenticationEnabled: Bool {
        get {
            return userDefaults.bool(forKey: Keys.authentication, defaultValue: false)
        }
        set(newValue) {
            let oldValue = authenticationEnabled
            userDefaults.set(newValue, forKey: Keys.authentication)
            guard oldValue != newValue else { return }
            NotificationCenter.default.post(name: Notifications.authenticationEnabledChanged, object: newValue)
        }
    }
}
