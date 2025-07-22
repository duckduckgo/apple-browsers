//
//  CreditCardImport.swift
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
import SecureStorage

public struct ImportedCreditCard: Equatable {

    let title: String?
    let cardNumber: String
    let cardholderName: String?
    let cardSecurityCode: String?
    let expirationMonth: Int?
    let expirationYear: Int?
    let lastUsedTime: Date?

    public init(title: String?,
                cardNumber: String,
                cardholderName: String?,
                cardSecurityCode: String?,
                expirationMonth: Int?,
                expirationYear: Int?,
                lastUsedTime: Date? = nil) {
        self.title = title
        self.cardNumber = cardNumber
        self.cardholderName = cardholderName
        self.cardSecurityCode = cardSecurityCode
        self.expirationMonth = expirationMonth
        self.expirationYear = expirationYear
        self.lastUsedTime = lastUsedTime
    }

    // Helper to get microseconds as Int64 if needed
    var lastUsedTimeMicroseconds: Int64? {
        guard let lastUsedTime = lastUsedTime else { return nil }
        return Int64(lastUsedTime.timeIntervalSince1970 * 1_000_000)
    }
}

public protocol CreditCardImporter {
    func importCreditCards(_ cards: [ImportedCreditCard],
                           vault: (any AutofillSecureVault)?,
                           completion: @escaping (Int) throws -> Void) throws -> DataImport.DataTypeSummary
}
