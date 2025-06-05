//
//  CreditCardRowViewModel.swift
//  DuckDuckGo
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
import SwiftUI

struct CreditCardRowViewModel: Identifiable, Hashable {
    
    static fileprivate let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/yy"
        return dateFormatter
    }()
    
    let creditCard: SecureVaultModels.CreditCard
    
    var id: String {
        return String(describing: self)
    }
    
    var type: CreditCardValidation.CardType {
        return CreditCardValidation.type(for: creditCard.cardNumber)
    }
    
    var displayTitle: String {
        return creditCard.title.isEmpty ? type.displayName : creditCard.title
    }
    
    var compactDisplayTitle: String {
        if displayTitle.count > 30 {
            let ellipsis = "..."
            return String(displayTitle.prefix(30)) + ellipsis
        }
        return displayTitle
    }
    
    var icon: Image {
        switch type {
        case .amex:
            return Image(.creditCardBankAmexColor32)
        case .dinersClub:
            return Image(.creditCardBankDinersClubColor32)
        case .discover:
            return Image(.creditCardBankDiscoverColor32)
        case .mastercard:
            return Image(.creditCardBankMastercardColor32)
        case .jcb:
            return Image(.creditCardBankJCBColor32)
        case .unionPay:
            return Image(.creditCardBankUnionpayColor32)
        case .visa:
            return Image(.creditCardBankVisaColor32)
        case .unknown:
            return Image(.creditCardColor32)
        }
    }
    
    var uiIcon: UIImage? {
        switch type {
        case .amex:
            return UIImage(named: "Credit-Card-Bank-Amex-Color-32")
        case .dinersClub:
            return UIImage(named: "Credit-Card-Bank-Diners-Club-Color-32")
        case .discover:
            return UIImage(named: "Credit-Card-Bank-Discover-Color-32")
        case .mastercard:
            return UIImage(named: "Credit-Card-Bank-Mastercard-Color-32")
        case .jcb:
            return UIImage(named: "Credit-Card-Bank-JCB-Color-32")
        case .unionPay:
            return UIImage(named: "Credit-Card-Bank-Unionpay-Color-32")
        case .visa:
            return UIImage(named: "Credit-Card-Bank-Visa-Color-32")
        case .unknown:
            return UIImage(named: "Credit-Card-Color-32")
        }
    }

    var lastFourDigits: String {
        return creditCard.cardSuffix
    }
    
    var expirationDate: String {
        guard let month = creditCard.expirationMonth,
              let year = creditCard.expirationYear,
              let date = DateComponents(calendar: Calendar.current, year: year, month: month).date else {
            return ""
        }
        return "  \(UserText.autofillCreditCardItemExpiry) \(Self.dateFormatter.string(from: date))"
    }
    
    var compactExpirationDate: String {
        guard let month = creditCard.expirationMonth,
              let year = creditCard.expirationYear,
              let date = DateComponents(calendar: Calendar.current, year: year, month: month).date else {
            return ""
        }
        return "\(Self.dateFormatter.string(from: date))"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CreditCardRowViewModel, rhs: CreditCardRowViewModel) -> Bool {
        return lhs.id == rhs.id
    }
    
}

extension Array where Element == SecureVaultModels.CreditCard {
    var asCardRowViewModels: [CreditCardRowViewModel] {
        self.map { CreditCardRowViewModel(creditCard: $0) }
    }
}
