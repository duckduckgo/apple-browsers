//
//  AutofillCreditCardListViewModel.swift
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

import Foundation
import BrowserServicesKit
import SwiftUI
import Core


protocol AutofillCreditCardListViewModelDelegate: AnyObject {
    func autofillCreditCardListViewModelDidSelectCard(_ viewModel: AutofillCreditCardListViewModel, card: SecureVaultModels.CreditCard)
}

final class AutofillCreditCardListViewModel: ObservableObject {

    @Published var creditCards: [CreditCardItem] = []

    weak var delegate: AutofillCreditCardListViewModelDelegate?

    private var secureVault: (any AutofillSecureVault)?
    private var cachedDeletedCard: SecureVaultModels.CreditCard?
    private var cancellables: Set<AnyCancellable> = []

    static fileprivate let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/yy"
        return dateFormatter
    }()
    
    init(secureVault: (any AutofillSecureVault)? = nil) {
        self.secureVault = secureVault
        
        fetchCreditCards()
    }
            
    func cardSelected(_ cardItem: CreditCardItem) {
        delegate?.autofillCreditCardListViewModelDidSelectCard(self, card: cardItem.card)
    }

    func refreshData() {
        fetchCreditCards()
    }

    // MARK: - Private methods
    
    private func fetchCreditCards() {
        do {
            let cards = try self.secureVault?.creditCards() ?? []
            creditCards = cards.asCardItems
        } catch {
            Logger.autofill.error("Failed to fetch credit cards from vault: \(error)")
        }
    }

    private func undoLastDelete() {
        guard let cachedDeletedCard = cachedDeletedCard else {
            return
        }
        undelete(cachedDeletedCard)
    }

    private func undelete(_ account: SecureVaultModels.CreditCard) {
        guard let secureVault = secureVault,
              var cachedDeletedCard = cachedDeletedCard else {
            return
        }
        do {
            let oldCard = cachedDeletedCard
            let newCard = SecureVaultModels.CreditCard(
                title: oldCard.title,
                cardNumber: oldCard.cardNumber,
                cardholderName: oldCard.cardholderName,
                cardSecurityCode: oldCard.cardSecurityCode,
                expirationMonth: oldCard.expirationMonth,
                expirationYear: oldCard.expirationYear)
            cachedDeletedCard = newCard
            try secureVault.storeCreditCard(cachedDeletedCard)
            clearUndoCache()
            fetchCreditCards()
        } catch {
            Pixel.fire(pixel: .secureVaultError, error: error)
        }
    }

    private func clearUndoCache() {
        cachedDeletedCard = nil
    }

    private func presentDeleteConfirmation() {
        ActionMessageView.present(message: UserText.autofillCreditCardDeletedToastMessage,
                                  actionTitle: UserText.actionGenericUndo,
                                  presentationLocation: .withoutBottomBar,
                                  onAction: {
            self.undoLastDelete()
        }, onDidDismiss: {
            self.clearUndoCache()
        })
    }
}

struct CreditCardItem: Identifiable, Hashable {
    
    let card: SecureVaultModels.CreditCard
    
    var id: String {
        return String(describing: self)
    }
    
    var type: CreditCardValidation.CardType {
        return CreditCardValidation.type(for: card.cardNumber)
    }
    
    var displayTitle: String {
        return card.title.isEmpty ? type.displayName : card.title
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
    
    var lastFourDigits: String {
        return card.cardSuffix
    }
    
    var expirationDate: String {
        guard let month = card.expirationMonth,
                let year = card.expirationYear,
              let date = DateComponents(calendar: Calendar.current, year: year, month: month).date else {
            return ""
        }
        return "  \(UserText.autofillCreditCardItemExpiry) \(AutofillCreditCardListViewModel.dateFormatter.string(from: date))"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CreditCardItem, rhs: CreditCardItem) -> Bool {
        return lhs.id == rhs.id
    }
    
}

private extension Array where Element == SecureVaultModels.CreditCard {
    var asCardItems: [CreditCardItem] {
        self.map { CreditCardItem(card: $0) }
    }
}
