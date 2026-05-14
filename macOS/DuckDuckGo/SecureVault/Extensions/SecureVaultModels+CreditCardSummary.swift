//
//  SecureVaultModels+CreditCardSummary.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit

extension SecureVaultModels.CreditCard {

    /// Returns the display title for the credit card.
    /// If the card has a custom title, it returns that; otherwise, it returns the card type's display name.
    var displayTitle: String {
        return title.isEmpty ? CreditCardValidation.type(for: cardNumber).displayName : title
    }

    /// Returns a formatted summary string for the credit card suitable for display in lists.
    /// Format: "••••(last 4 digits) Expires: MM/yyyy" (if expiration is available)
    ///         "••••(last 4 digits)" (if expiration is not available)
    var cardSummary: String {
        var summary = "•••• \(cardSuffix)"

        if let expirationMonth = expirationMonth, let expirationYear = expirationYear {
            let formattedDate = String(format: "%02d/%d", expirationMonth, expirationYear)
            summary += " \(String(format: UserText.pmCardExpiresFormat, formattedDate))"
        }

        return summary
    }
}
