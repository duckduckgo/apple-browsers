//
//  DataBrokerProtectionBundleExtension.swift
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

public extension UserDefaults {
    static let dbp = UserDefaults(suiteName: Bundle.main.dbpAppGroup)!
    static let config = UserDefaults(suiteName: Bundle.main.configAppGroup)!
    static let netP = UserDefaults(suiteName: Bundle.main.netPAppGroup)!
}

extension Bundle {

    static let dbpAppGroupName = "DBP_APP_GROUP"
    static let configAppGroupName = "APP_CONFIGURATION_APP_GROUP"
    static let netPAppGroupName = "NETP_APP_GROUP"

    public var appGroupName: String {
        guard let appGroup = object(forInfoDictionaryKey: Bundle.dbpAppGroupName) as? String else {
            fatalError("Info.plist is missing \(Bundle.dbpAppGroupName)")
        }
        return appGroup
    }

    var configAppGroupName: String {
        guard let appGroup = object(forInfoDictionaryKey: Bundle.configAppGroupName) as? String else {
            fatalError("Info.plist is missing \(Bundle.configAppGroupName)")
        }
        return appGroup
    }

    var dbpAppGroup: String {
        guard let appGroup = object(forInfoDictionaryKey: Bundle.dbpAppGroupName) as? String else {
            fatalError("Info.plist is missing \(Bundle.dbpAppGroupName)")
        }
        return appGroup
    }

    var configAppGroup: String {
        guard let appGroup = object(forInfoDictionaryKey: Bundle.configAppGroupName) as? String else {
            fatalError("Info.plist is missing \(Bundle.configAppGroupName)")
        }
        return appGroup
    }

    var netPAppGroup: String {
        guard let appGroup = object(forInfoDictionaryKey: Bundle.netPAppGroupName) as? String else {
            fatalError("Info.plist is missing \(Bundle.netPAppGroupName)")
        }
        return appGroup
    }
}
