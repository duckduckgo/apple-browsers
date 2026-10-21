//
//  SyncableCreditCardsExtension.swift
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

    static func creditCard(
        _ title: String? = nil,
        uuid: String,
        cardholderName: String? = nil,
        cardNumber: String? = nil,
        cardSecurityCode: String? = nil,
        expirationMonth: String? = nil,
        expirationYear: String? = nil,
        nullifyOtherFields: Bool = false,
        lastModified: String? = nil,
        isDeleted: Bool = false
    ) -> Syncable {

        let defaultValue: Any = (nullifyOtherFields ? nil : uuid) as Any

        var json: [String: Any] = [
            "id": uuid,
            "title": title ?? defaultValue,
            "cardholder_name": cardholderName ?? defaultValue,
            "card_number": cardNumber ?? defaultValue,
            "card_security_code": cardSecurityCode ?? defaultValue,
            "expiration_month": expirationMonth ?? defaultValue,
            "expiration_year": expirationYear ?? defaultValue,
            "client_last_modified": lastModified ?? "1234"
        ]

        if isDeleted {
            json["deleted"] = ""
        }

        return .init(jsonObject: json)
    }
}
