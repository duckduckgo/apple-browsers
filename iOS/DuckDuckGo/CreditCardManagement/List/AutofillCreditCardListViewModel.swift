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
import Combine
import Core

protocol AutofillCreditCardListViewModelDelegate: AnyObject {
    func autofillCreditCardListViewModelDidSelectCard(_ viewModel: AutofillCreditCardListViewModel, card: SecureVaultModels.CreditCard)
}

protocol CreditCardListViewModelProtocol: ObservableObject {
    func cardSelected(_ cardViewModel: CreditCardViewModel)
    func refreshData()
    func deleteCard(_ creditCard: SecureVaultModels.CreditCard)
    func lockUI()
    func authenticate(completion: @escaping (UserAuthenticator.AuthError?) -> Void)
}

final class AutofillCreditCardListViewModel: CreditCardListViewModelProtocol {
    
    enum ViewState {
        case authLocked
        case noAuthAvailable
        case empty
        case showItems
    }
    
    @Published var cards: [CreditCardViewModel] = []
    @Published var showingModal: Bool = false
    @Published private(set) var viewState: AutofillCreditCardListViewModel.ViewState = .authLocked
    
    weak var delegate: AutofillCreditCardListViewModelDelegate?
    
    let authenticator: AutofillLoginListAuthenticator = AutofillLoginListAuthenticator(
        reason: UserText.autofillCreditCardAuthenticationReason,
        cancelTitle: UserText.autofillLoginListAuthenticationCancelButton
    )
    
    var authenticationNotRequired = false
    
    var hasCardsSaved: Bool {
        return !cards.isEmpty
    }
    
    private var secureVault: (any AutofillSecureVault)?
    private var cachedDeletedCreditCard: SecureVaultModels.CreditCard?
    private var cancellables: Set<AnyCancellable> = []
    
    static fileprivate let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/yy"
        return dateFormatter
    }()
    
    init(secureVault: (any AutofillSecureVault)? = nil) {
        self.secureVault = secureVault
        
        if let count = try? secureVault?.creditCardsCount() {
            authenticationNotRequired = count == 0
        }
        refreshData()
        setupCancellables()
    }
    
    func cardSelected(_ cardViewModel: CreditCardViewModel) {
        delegate?.autofillCreditCardListViewModelDidSelectCard(self, card: cardViewModel.card)
    }
    
    func refreshData() {
        fetchCreditCards()
    }
    
    func deleteCard(_ creditCard: SecureVaultModels.CreditCard) {
        guard let cardId = creditCard.id else {
            return
        }
        
        do {
            cachedDeletedCreditCard = creditCard
            try secureVault?.deleteCreditCardFor(cardId: cardId)
            fetchCreditCards()
            presentDeleteConfirmation()
        } catch {
            Pixel.fire(pixel: .secureVaultError, error: error)
        }
    }
    
    func lockUI() {
        authenticationNotRequired = !hasCardsSaved
        authenticator.logOut()
    }
    
    func authenticate(completion: @escaping (AutofillLoginListAuthenticator.AuthError?) -> Void) {
        if !authenticator.canAuthenticate() {
            viewState = .noAuthAvailable
            completion(.noAuthAvailable)
            return
        }
        
        if viewState != .authLocked {
            completion(nil)
            return
        }
        
        authenticator.authenticate(completion: completion)
    }
    
    // MARK: - Private methods
    
    private func setupCancellables() {
        authenticator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateViewState()
            }
            .store(in: &cancellables)
    }
    
    private func updateViewState() {
        var newViewState: AutofillCreditCardListViewModel.ViewState
        
        if !authenticator.canAuthenticate() {
            newViewState = .noAuthAvailable
        } else if authenticator.state == .loggedOut && !authenticationNotRequired {
            newViewState = .authLocked
        } else {
            newViewState = cards.count > 0 ? .showItems : .empty
        }
        
        // Avoid unnecessary updates
        if newViewState != viewState {
            viewState = newViewState
        }
    }
    
    private func fetchCreditCards() {
        do {
            let creditCards = try self.secureVault?.creditCards() ?? []
            cards = creditCards.asCardViewModels
            updateViewState()
        } catch {
            Logger.autofill.error("Failed to fetch credit cards from vault: \(error)")
        }
    }
    
    private func undoLastDelete() {
        guard let cachedDeletedCreditCard = cachedDeletedCreditCard else {
            return
        }
        undelete(cachedDeletedCreditCard)
    }
    
    private func undelete(_ account: SecureVaultModels.CreditCard) {
        guard let secureVault = secureVault,
              var cachedDeletedCreditCard = cachedDeletedCreditCard else {
            return
        }
        do {
            let oldCard = cachedDeletedCreditCard
            let newCard = SecureVaultModels.CreditCard(
                title: oldCard.title,
                cardNumber: oldCard.cardNumber,
                cardholderName: oldCard.cardholderName,
                cardSecurityCode: oldCard.cardSecurityCode,
                expirationMonth: oldCard.expirationMonth,
                expirationYear: oldCard.expirationYear)
            cachedDeletedCreditCard = newCard
            try secureVault.storeCreditCard(cachedDeletedCreditCard)
            clearUndoCache()
            fetchCreditCards()
        } catch {
            Pixel.fire(pixel: .secureVaultError, error: error)
        }
    }
    
    private func clearUndoCache() {
        cachedDeletedCreditCard = nil
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

struct CreditCardViewModel: Identifiable, Hashable {
    
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
    
    static func == (lhs: CreditCardViewModel, rhs: CreditCardViewModel) -> Bool {
        return lhs.id == rhs.id
    }
    
}

private extension Array where Element == SecureVaultModels.CreditCard {
    var asCardViewModels: [CreditCardViewModel] {
        self.map { CreditCardViewModel(card: $0) }
    }
}
