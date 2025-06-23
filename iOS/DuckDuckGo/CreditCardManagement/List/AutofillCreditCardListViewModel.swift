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
    func autofillCreditCardListViewModelAddCard(_ viewModel: AutofillCreditCardListViewModel)
}

protocol CreditCardListViewModelProtocol: ObservableObject {
    func cardSelected(_ creditCardRow: CreditCardRowViewModel)
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
    
    @Published var cards: [CreditCardRowViewModel] = []
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
    
    init(secureVault: (any AutofillSecureVault)? = nil, source: AutofillSettingsSource) {
        self.secureVault = secureVault
        
        if let count = try? secureVault?.creditCardsCount() {
            authenticationNotRequired = count == 0
            Pixel.fire(pixel: .autofillCardsManagementOpened,
                       withAdditionalParameters: [
                        PixelParameters.source: source.rawValue,
                        "has_cards_saved": "\(count > 0 ? 1 : 0)"
                       ])
        }
        refreshData()
        setupCancellables()
    }
    
    func addCard() {
        delegate?.autofillCreditCardListViewModelAddCard(self)
    }
    
    func cardSelected(_ card: CreditCardRowViewModel) {
        delegate?.autofillCreditCardListViewModelDidSelectCard(self, card: card.creditCard)
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
            cards = creditCards.sorted(by: { $0.created > $1.created }).asCardRowViewModels
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
                expirationYear: oldCard.expirationYear,
                created: oldCard.created)
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
            Pixel.fire(pixel: .autofillCardsManagementDeleteCard)
        })
    }
}
