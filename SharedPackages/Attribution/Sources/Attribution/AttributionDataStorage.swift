//
//  AttributionDataStorage.swift
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

public protocol AttributionDataStoring {

    var installDate: Date? { get set }
    var lastRetentionThreshold: TimePast? { get set }

    var search7Days: RollingArrayInt? { get set }

    func removeAll()
}

class AttributionDataStorage: AttributionDataStoring {

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    enum StorageKey: String, CaseIterable {

        case installDate

        // retention
        case lastRetentionThreshold

        // Searches
        case search7Days
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

    // MARK: - Searches

    var search7Days: RollingArrayInt? {
        set { encode(newValue, to: userDefaults, key: .search7Days) }
        get { return decode(from: userDefaults, key: .search7Days) }
    }
}
