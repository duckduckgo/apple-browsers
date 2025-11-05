//
//  SyncableCreditCardsAdapter.swift
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
import Foundation

struct SyncableCreditCardsAdapter {

    let syncable: Syncable

    init(syncable: Syncable) {
        self.syncable = syncable
    }

    var uuid: String? {
        syncable.payload["id"] as? String
    }

    var isDeleted: Bool {
        syncable.isDeleted
    }

    var encryptedTitle: String? {
        syncable.payload["title"] as? String
    }

    var encryptedCardholderName: String? {
        syncable.payload["cardholder_name"] as? String
    }

    var encryptedCardNumber: String? {
        syncable.payload["card_number"] as? String
    }

    var encryptedCardSecurityCode: String? {
        syncable.payload["card_security_code"] as? String
    }

    var encryptedExpirationMonth: String? {
        syncable.payload["expiration_month"] as? String
    }

    var encryptedExpirationYear: String? {
        syncable.payload["expiration_year"] as? String
    }
}

extension Syncable {

    enum SyncableCreditCardError: Error {
        case validationFailed
    }

    enum CreditCardValidationConstraints {
        static let maxEncryptedTitleLength = 3000
        static let maxEncryptedCardholderNameLength = 1000
        static let maxEncryptedCardNumberLength = 500
        static let maxEncryptedCardSecurityCodeLength = 100
        static let maxEncryptedExpirationMonthLength = 100
        static let maxEncryptedExpirationYearLength = 100
    }

    // swiftlint:disable:next cyclomatic_complexity
    init(syncableCreditCard: SecureVaultModels.SyncableCreditCard, encryptedUsing encrypt: (String) throws -> String) throws {
        var payload: [String: Any] = [:]

        payload["id"] = syncableCreditCard.metadata.uuid

        guard let creditCard = syncableCreditCard.creditCard else {
            payload["deleted"] = ""
            self.init(jsonObject: payload)
            return
        }

        if !creditCard.title.isEmpty {
            let encryptedTitle = try encrypt(creditCard.title)
            guard encryptedTitle.count <= CreditCardValidationConstraints.maxEncryptedTitleLength else {
                throw SyncableCreditCardError.validationFailed
            }
            payload["title"] = encryptedTitle
        }

        if let cardholderName = creditCard.cardholderName {
            let encryptedCardholderName = try encrypt(cardholderName)
            guard encryptedCardholderName.count <= CreditCardValidationConstraints.maxEncryptedCardholderNameLength else {
                throw SyncableCreditCardError.validationFailed
            }
            payload["cardholder_name"] = encryptedCardholderName
        }

        if let cardNumber = String(data: creditCard.cardNumberData, encoding: .utf8) {
            let encryptedCardNumber = try encrypt(cardNumber)
            guard encryptedCardNumber.count <= CreditCardValidationConstraints.maxEncryptedCardNumberLength else {
                throw SyncableCreditCardError.validationFailed
            }
            payload["card_number"] = encryptedCardNumber
        }

        if let cardSecurityCode = creditCard.cardSecurityCode {
            let encryptedCardSecurityCode = try encrypt(cardSecurityCode)
            guard encryptedCardSecurityCode.count <= CreditCardValidationConstraints.maxEncryptedCardSecurityCodeLength else {
                throw SyncableCreditCardError.validationFailed
            }
            payload["card_security_code"] = encryptedCardSecurityCode
        }

        if let expirationMonth = creditCard.expirationMonth {
            let encryptedExpirationMonth = try encrypt(String(expirationMonth))
            guard encryptedExpirationMonth.count <= CreditCardValidationConstraints.maxEncryptedExpirationMonthLength else {
                throw SyncableCreditCardError.validationFailed
            }
            payload["expiration_month"] = encryptedExpirationMonth
        }

        if let expirationYear = creditCard.expirationYear {
            let encryptedExpirationYear = try encrypt(String(expirationYear))
            guard encryptedExpirationYear.count <= CreditCardValidationConstraints.maxEncryptedExpirationYearLength else {
                throw SyncableCreditCardError.validationFailed
            }
            payload["expiration_year"] = encryptedExpirationYear
        }

        if let modifiedAt = syncableCreditCard.metadata.lastModified {
            payload["client_last_modified"] = Self.dateFormatter.string(from: modifiedAt)
        }

        self.init(jsonObject: payload)
    }

    private static var dateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }
}
