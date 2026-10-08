//
//  SecureVaultModels+CreditCardIcon.swift
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

import AppKit
import BrowserServicesKit
import SwiftUI

extension SecureVaultModels.CreditCard {

    /// Returns the NSImage for the credit card icon based on the card type.
    var iconImage: NSImage {
        let cardType = CreditCardValidation.type(for: cardNumber)

        switch cardType {
        case .amex:
            return NSImage(resource: .creditCardBankAmexColor32)
        case .dinersClub:
            return NSImage(resource: .creditCardBankDinersClubColor32)
        case .discover:
            return NSImage(resource: .creditCardBankDiscoverColor32)
        case .mastercard:
            return NSImage(resource: .creditCardBankMastercardColor32)
        case .jcb:
            return NSImage(resource: .creditCardBankJCBColor32)
        case .unionPay:
            return NSImage(resource: .creditCardBankUnionpayColor32)
        case .visa:
            return NSImage(resource: .creditCardBankVisaColor32)
        case .unknown:
            return NSImage(resource: .card)
        }
    }
}
