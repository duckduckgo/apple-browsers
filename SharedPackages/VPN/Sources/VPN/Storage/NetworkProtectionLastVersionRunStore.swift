//
//  NetworkProtectionLastVersionRunStore.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public final class NetworkProtectionLastVersionRunStore {
    private let userDefaults: UserDefaults

    private static let lastAgentVersionRunKey = "com.duckduckgo.network-protection.NetworkProtectionVersionStore.lastAgentVersionRunKey"
    private static let lastExtensionVersionRunKey = "com.duckduckgo.network-protection.NetworkProtectionVersionStore.lastExtensionVersionRunKey"

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    @available(macOS 11.0, *)
    public var lastAgentVersionRun: String? {
        get {
            userDefaults.string(forKey: Self.lastAgentVersionRunKey)
        }

        set {
            userDefaults.set(newValue, forKey: Self.lastAgentVersionRunKey)
        }
    }

    public var lastExtensionVersionRun: String? {
        get {
            userDefaults.string(forKey: Self.lastExtensionVersionRunKey)
        }

        set {
            userDefaults.set(newValue, forKey: Self.lastExtensionVersionRunKey)
        }
    }
}
