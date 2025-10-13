//
//  SyncableIdentitiesExtension.swift
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

import BrowserServicesKit
import DDGSync

extension Syncable {

    static func identity(
        _ title: String? = nil,
        uuid: String,
        firstName: String? = nil,
        middleName: String? = nil,
        lastName: String? = nil,
        birthday: String? = nil,
        phone: String? = nil,
        emailAddress: String? = nil,
        addressStreet: String? = nil,
        addressStreet2: String? = nil,
        addressCity: String? = nil,
        addressProvince: String? = nil,
        addressPostalCode: String? = nil,
        addressCountryCode: String? = nil,
        nullifyOtherFields: Bool = false,
        lastModified: String? = nil,
        isDeleted: Bool = false
    ) -> Syncable {
        let defaultValue: Any = (nullifyOtherFields ? nil : uuid) as Any

        var json: [String: Any] = [
            "id": uuid,
            "title": title ?? defaultValue,
            "first_name": firstName ?? defaultValue,
            "middle_name": middleName ?? defaultValue,
            "last_name": lastName ?? defaultValue,
            "birthday": birthday ?? defaultValue,
            "phone": phone ?? defaultValue,
            "email_address": emailAddress ?? defaultValue,
            "client_last_modified": lastModified ?? "1234"
        ]

        var addressPayload: [String: Any] = [:]
        addressPayload["street"] = addressStreet ?? defaultValue
        addressPayload["street2"] = addressStreet2 ?? defaultValue
        addressPayload["city"] = addressCity ?? defaultValue
        addressPayload["province"] = addressProvince ?? defaultValue
        addressPayload["postal_code"] = addressPostalCode ?? defaultValue
        addressPayload["country_code"] = addressCountryCode ?? defaultValue

        json["address"] = addressPayload

        if isDeleted {
            json["deleted"] = ""
        }

        return .init(jsonObject: json)
    }
}
