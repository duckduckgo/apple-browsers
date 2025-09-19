//
//  UserBehaviorDataStorage.swift
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

public protocol UserBehaviorDataStoring {

    var installDate: Date? { get set }
    var lastRetentionThreshold: TimePast? { get set }

    var search8Days: RollingEightDaysInt { get set }
    var adClick8Days: RollingEightDaysInt { get set }
    var duckAIChat8Days: RollingEightDaysInt { get set }

    var subscriptionDate: Date? { get set }

    func removeAll()
}

class UserBehaviorDataStorage: UserBehaviorDataStoring {

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    enum StorageKey: String, CaseIterable {

        case installDate

        // retention
        case lastRetentionThreshold
        case search8Days
        case adClick8Days
        case duckAIChat8Days
        case subscriptionDate
    }

    // MARK: - Utilities

    public func removeAll() {
        for key in StorageKey.allCases {
            userDefaults.removeObject(forKey: key.rawValue)
        }
    }

    // MARK: - Coding

    func encode(_ object: Codable, to userDefaults: UserDefaults, key: StorageKey) {
        guard let data = try? JSONEncoder().encode(object) else { return }
        userDefaults.set(data, forKey: key.rawValue)
    }

    func decode<T: Codable>(from userDefaults: UserDefaults, key: StorageKey) -> T? {
        guard let data = userDefaults.data(forKey: key.rawValue),
              let object = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return object
    }

    // MARK: - Retention

    var installDate: Date? {
        set { encode(newValue, to: userDefaults, key: .installDate) }
        get { return decode(from: userDefaults, key: .installDate) }
    }

    var lastRetentionThreshold: TimePast? {
        set { encode(newValue, to: userDefaults, key: .lastRetentionThreshold) }
        get { return decode(from: userDefaults, key: .lastRetentionThreshold)}
    }

    var search8Days: RollingEightDaysInt {
        set { encode(newValue, to: userDefaults, key: .search8Days) }
        get { return decode(from: userDefaults, key: .search8Days) ?? RollingEightDaysInt() }
    }

    var adClick8Days: RollingEightDaysInt {
        set { encode(newValue, to: userDefaults, key: .adClick8Days) }
        get { return decode(from: userDefaults, key: .adClick8Days) ?? RollingEightDaysInt() }
    }

    var duckAIChat8Days: RollingEightDaysInt {
        set { encode(newValue, to: userDefaults, key: .duckAIChat8Days) }
        get { return decode(from: userDefaults, key: .duckAIChat8Days) ?? RollingEightDaysInt() }
    }

    var subscriptionDate: Date? {
        set { encode(newValue, to: userDefaults, key: .subscriptionDate) }
        get { return decode(from: userDefaults, key: .subscriptionDate) }
    }
}
