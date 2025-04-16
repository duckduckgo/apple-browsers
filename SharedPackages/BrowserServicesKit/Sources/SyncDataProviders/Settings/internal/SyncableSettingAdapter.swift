//
//  SyncableSettingAdapter.swift
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

import BrowserServicesKit
import DDGSync
import Foundation

struct SyncableSettingAdapter {

    let syncable: Syncable

    init(syncable: Syncable) {
        self.syncable = syncable
    }

    var uuid: String? {
        syncable.payload["key"] as? String
    }

    var isDeleted: Bool {
        syncable.isDeleted
    }

    var encryptedValue: String? {
        syncable.payload["value"] as? String
    }
}

extension Syncable {

    init(setting: SettingsProvider.Setting, value: String?, lastModified: Date?, encryptedUsing encrypt: (String) throws -> String) throws {
        var payload: [String: Any] = [:]

        payload["key"] = setting.key

        if let value {
            payload["value"] = try encrypt(value)
        } else {
            payload["deleted"] = ""
        }

        if let lastModified {
            payload["client_last_modified"] = Self.dateFormatter.string(from: lastModified)
        }
        self.init(jsonObject: payload)
    }

    private static var dateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }
}
