//
//  SyncableSettingsExtension.swift
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

import Bookmarks
import BrowserServicesKit
import DDGSync
import Foundation
@testable import SyncDataProviders

extension Syncable {

    static func settings(_ key: SettingsProvider.Setting, value: String? = nil, lastModified: String? = nil, isDeleted: Bool = false) -> Syncable {
        var json: [String: Any] = [
            "key": key.key,
            "value": value as Any,
            "client_last_modified": "1234"
        ]
        if isDeleted {
            json["deleted"] = ""
        }
        return .init(jsonObject: json)
    }

    static func emailProtection(username: String, token: String, lastModified: String? = nil, isDeleted: Bool = false) -> Syncable {
        let payload = EmailProtectionSyncHandler.Payload(username: username, personalAccessToken: token)
        let data = try! JSONEncoder.snakeCaseKeys.encode(payload)
        let value = "encrypted_\(String(data: data, encoding: .utf8)!)"
        return Self.settings(SettingsProvider.Setting.emailProtectionGeneration, value: value, lastModified: lastModified, isDeleted: isDeleted)
    }

    static func emailProtectionDeleted() -> Syncable {
        Self.settings(SettingsProvider.Setting.emailProtectionGeneration, value: nil, isDeleted: true)
    }

    static func testSetting(_ value: String, lastModified: String? = nil, isDeleted: Bool = false) -> Syncable {
        Self.settings(SettingsProvider.Setting.testSetting, value: "encrypted_\(value)", lastModified: lastModified, isDeleted: isDeleted)
    }

    static func testSettingDeleted() -> Syncable {
        Self.settings(SettingsProvider.Setting.testSetting, value: nil, isDeleted: true)
    }
}
