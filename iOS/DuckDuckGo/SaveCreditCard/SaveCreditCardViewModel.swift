//
//  SaveCreditCardViewModel.swift
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
import Core

protocol SaveCreditCardViewModelDelegate: AnyObject {
    func saveCreditCardViewModelDidSave(_ viewModel: SaveCreditCardViewModel, creditCard: SecureVaultModels.CreditCard)
    func saveCreditCardViewModelCancel(_ viewModel: SaveCreditCardViewModel)
    func saveCreditCardViewModelConfirmKeepUsing(_ viewModel: SaveCreditCardViewModel)
    func saveCreditCardViewModelDidResizeContent(_ viewModel: SaveCreditCardViewModel, contentHeight: CGFloat)
}

final class SaveCreditCardViewModel {
    
    weak var delegate: SaveCreditCardViewModelDelegate?
    
    var minHeight: CGFloat = AutofillViews.saveLoginMinHeight
    
    var contentHeight: CGFloat = AutofillViews.saveLoginMinHeight {
        didSet {
            guard contentHeight != oldValue else { return }
            delegate?.saveCreditCardViewModelDidResizeContent(self, contentHeight: max(contentHeight, minHeight))
        }
    }
    
    /*
     - The url of the last site where autofill for cards was declined is stored in app memory
     - The count of the number of times autofill has been declined is kept in user defaults
     - If the user has never saved a card and declines to save a card:
     - The count will increment unless the user is declining to fill on the same site as the one which is currently recorded in memory
     - The current site will replace the one stored in memory (if different)
     - If the count reaches 3, we show the prompt to explain that autofill for cards can be disabled
     */
    private let domainLastShownOn: String?
    
    @UserDefaultsWrapper(key: .autofillCreditCardsSaveModalRejectionCount, defaultValue: 0)
    private var autofillCreditCardsSaveModalRejectionCount: Int
    
    @UserDefaultsWrapper(key: .autofillCreditCardsSaveModalDisablePromptShown, defaultValue: false)
    private var autofillCreditCardsSaveModalDisablePromptShown: Bool
    
    @UserDefaultsWrapper(key: .autofillCreditCardsFirstTimeUser, defaultValue: true)
    private var autofillCreditCardsFirstTimeUser: Bool
    
    private let numberOfRejectionsToTurnOffCreditCardAutofill = 2
    
    private let creditCard: SecureVaultModels.CreditCard
    private let accountDomain: String
    private let vault: (any AutofillSecureVault)?
    let card: CreditCardRowViewModel
    
    init(creditCard: SecureVaultModels.CreditCard, accountDomain: String, domainLastShownOn: String? = nil, vault: (any AutofillSecureVault)? = nil) {
        self.creditCard = creditCard
        self.accountDomain = accountDomain
        self.domainLastShownOn = domainLastShownOn
        self.vault = vault
        self.card = CreditCardRowViewModel(creditCard: creditCard)

        Pixel.fire(pixel: .autofillCardsSaveCardInlineDisplayed)
    }
    
    func cancelButtonPressed() {
        updateRejectionCountIfNeeded()
        delegate?.saveCreditCardViewModelCancel(self)
        showDisableAutofillPromptIfNeeded()
        Pixel.fire(pixel: .autofillCardsSaveCardInlineDismissed)
    }
    
    func save() {
        guard let card = try? saveCreditCard(creditCard, with: AutofillSecureVaultFactory) else {
            // ensure prompt is dismissed if card can't be saved
            delegate?.saveCreditCardViewModelCancel(self)
            return
        }
        Pixel.fire(pixel: .autofillCardsSaveCardInlineConfirmed)
        autofillCreditCardsFirstTimeUser = false
        delegate?.saveCreditCardViewModelDidSave(self, creditCard: card)
    }
    
    private func saveCreditCard(_ creditCard: SecureVaultModels.CreditCard, with factory: AutofillVaultFactory) throws -> SecureVaultModels.CreditCard? {
        do {
            let vault = try self.vault ?? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
            guard try vault.existingCardForAutofill(matching: creditCard) == nil else {
                return nil
            }

            let cardId = try vault.storeCreditCard(creditCard)
            if let newCard = try vault.creditCardFor(id: cardId) {
                return newCard
            }
            
            return nil
        } catch {
            throw error
        }
    }
    
    private func shouldShowDisableAutofillPrompt() -> Bool {
        if autofillCreditCardsSaveModalDisablePromptShown || !autofillCreditCardsFirstTimeUser {
            return false
        }
        return autofillCreditCardsSaveModalRejectionCount >= numberOfRejectionsToTurnOffCreditCardAutofill
    }
    
    private func updateRejectionCountIfNeeded() {
        // If the prompt has already been shown on this domain (that we know of), we don't want to increment the rejection count
        if let domainLastShownOn = domainLastShownOn, domainLastShownOn == accountDomain {
            return
        }
        autofillCreditCardsSaveModalRejectionCount += 1
    }
    
    private func showDisableAutofillPromptIfNeeded() {
        if shouldShowDisableAutofillPrompt() {
            delegate?.saveCreditCardViewModelConfirmKeepUsing(self)
            autofillCreditCardsSaveModalDisablePromptShown = true
            autofillCreditCardsFirstTimeUser = false
        }
    }
}
