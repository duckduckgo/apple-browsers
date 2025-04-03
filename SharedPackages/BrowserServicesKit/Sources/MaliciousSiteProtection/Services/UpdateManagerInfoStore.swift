//
//  UpdateManagerInfoStore.swift
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

import Foundation

protocol MaliciousSiteProtectioUpdateManagerInfoStorage: AnyObject {
    var lastHashPrefixSetsUpdateDate: Date { get set }
    var lastFilterSetsUpdateDate: Date { get set }
}

final class UpdateManagerInfoStore: MaliciousSiteProtectioUpdateManagerInfoStorage {
    enum Keys {
        static let maliciousSiteProtectionLastHashPrefixSetUpdateDate = "com.duckduckgo.ios.maliciousSiteProtection.lastHashPrefixSetRefreshDate"
        static let maliciousSiteProtectionLastFilterSetUpdateDate = "com.duckduckgo.ios.maliciousSiteProtection.lastFilterSetsRefreshDate"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var lastHashPrefixSetsUpdateDate: Date {
        get {
            userDefaults.object(forKey: Keys.maliciousSiteProtectionLastHashPrefixSetUpdateDate) as? Date ?? .distantPast
        }
        set {
            userDefaults.set(newValue, forKey: Keys.maliciousSiteProtectionLastHashPrefixSetUpdateDate)
        }
    }

    var lastFilterSetsUpdateDate: Date {
        get {
            userDefaults.object(forKey: Keys.maliciousSiteProtectionLastFilterSetUpdateDate) as? Date ?? .distantPast
        }
        set {
            userDefaults.set(newValue, forKey: Keys.maliciousSiteProtectionLastFilterSetUpdateDate)
        }
    }
}
