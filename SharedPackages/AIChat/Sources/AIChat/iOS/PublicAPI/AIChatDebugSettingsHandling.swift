//
//  AIChatDebugSettingsHandling.swift
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

#if os(iOS)
import Foundation

public protocol AIChatDebugSettingsHandling {
    var messagePolicyHostname: String? { get set }
    var customURL: String? { get set }
    func reset()
}

public class AIChatDebugSettings: AIChatDebugSettingsHandling {
    private let hostnameUserDefaultsKey = "aichat.debug.messagePolicyHostname"
    private let customURLUserDefaultsKey = "aichat.debug.customURL"
    private let userDefault: UserDefaults

    public init(userDefault: UserDefaults = .standard) {
        self.userDefault = userDefault
    }

    public var messagePolicyHostname: String? {
        get {
            let value = userDefault.string(forKey: hostnameUserDefaultsKey)
            return value?.isEmpty == true ? nil : value
        }
        set {
            if let newValue = newValue, !newValue.isEmpty {
                userDefault.set(newValue, forKey: hostnameUserDefaultsKey)
            } else {
                userDefault.removeObject(forKey: hostnameUserDefaultsKey)
            }
        }
    }

    public var customURL: String? {
        get {
            let value = userDefault.string(forKey: customURLUserDefaultsKey)
            return value?.isEmpty == true ? nil : value
        }
        set {
            if let newValue = newValue, !newValue.isEmpty {
                userDefault.set(newValue, forKey: customURLUserDefaultsKey)
            } else {
                userDefault.removeObject(forKey: customURLUserDefaultsKey)
            }
        }
    }

    public func reset() {
        messagePolicyHostname = nil
        customURL = nil
    }
}
#endif
