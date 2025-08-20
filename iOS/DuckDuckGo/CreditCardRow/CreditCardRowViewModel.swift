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

    private var iconAssetName: String {
        switch type {
        case .amex:
            "Credit-Card-Bank-Amex-Color-32"
        case .dinersClub:
            "Credit-Card-Bank-Diners-Club-Color-32"
        case .discover:
            "Credit-Card-Bank-Discover-Color-32"
        case .mastercard:
            "Credit-Card-Bank-Mastercard-Color-32"
        case .jcb:
            "Credit-Card-Bank-JCB-Color-32"
        case .unionPay:
            "Credit-Card-Bank-Unionpay-Color-32"
        case .visa:
            "Credit-Card-Bank-Visa-Color-32"
        case .unknown:
            "Credit-Card-Color-32"
        }
    }

    var icon: Image {
        Image(iconAssetName)
    }
    
    var uiImageIcon: UIImage? {
        UIImage(named: iconAssetName)
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
