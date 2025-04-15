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

protocol SaveCreditCardViewModelDelegate: AnyObject {
    func saveCreditCardViewModelDidSave(_ viewModel: SaveCreditCardViewModel, creditCard: SecureVaultModels.CreditCard)
    func saveCreditCardViewModelCancel(_ viewModel: SaveCreditCardViewModel)
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
    
    private let creditCard: SecureVaultModels.CreditCard
    let card: CreditCardRowViewModel
    
    init(creditCard: SecureVaultModels.CreditCard) {
        self.creditCard = creditCard
        self.card = CreditCardRowViewModel(creditCard: creditCard)
    }
    
    func cancelButtonPressed() {
        delegate?.saveCreditCardViewModelCancel(self)
    }
    
    func save() {
        guard let card = try? saveCreditCard(creditCard, with: AutofillSecureVaultFactory) else {
            return
        }
        delegate?.saveCreditCardViewModelDidSave(self, creditCard: card)
    }
    
    private func saveCreditCard(_ creditCard: SecureVaultModels.CreditCard, with factory: AutofillVaultFactory) throws -> SecureVaultModels.CreditCard? {
        do {
            let vault = try AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
            let cardId = try vault.storeCreditCard(creditCard)
            if let newCard = try vault.creditCardFor(id: cardId) {
                return newCard
            }
            
            return nil
        } catch {
            throw error
        }
    }
}
