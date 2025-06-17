//
//  CreditCardPromptViewModel.swift
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

protocol CreditCardPromptViewModelDelegate: AnyObject {
    func creditCardPromptViewModel(_ viewModel: CreditCardPromptViewModel, didSelectCreditCard creditCard: SecureVaultModels.CreditCard)
    func creditCardPromptViewModelCancel(_ viewModel: CreditCardPromptViewModel)
    func creditCardPromptViewModelDidResizeContent(_ viewModel: CreditCardPromptViewModel, contentHeight: CGFloat)
}

final class CreditCardPromptViewModel {
    
    weak var delegate: CreditCardPromptViewModelDelegate?
    
    var minHeight: CGFloat = AutofillViews.loginPromptMinHeight
    
    var contentHeight: CGFloat = AutofillViews.loginPromptMinHeight {
        didSet {
            guard contentHeight != oldValue else { return }
            delegate?.creditCardPromptViewModelDidResizeContent(self, contentHeight: max(contentHeight, minHeight))
        }
    }
    
    let cards: [CreditCardRowViewModel]
    
    init(creditCards: [SecureVaultModels.CreditCard]) {
        self.cards = creditCards.sorted(by: { $0.created > $1.created }).asCardRowViewModels
        Pixel.fire(pixel: .autofillCardsFillCardManualInlineDisplayed)
    }
    
    func selected(card: CreditCardRowViewModel) {
        delegate?.creditCardPromptViewModel(self, didSelectCreditCard: card.creditCard)
        Pixel.fire(pixel: .autofillCardsFillCardManualInlineConfirmed)
    }
    
    func cancelButtonPressed() {
        delegate?.creditCardPromptViewModelCancel(self)
        Pixel.fire(pixel: .autofillCardsFillCardManualInlineDismissed)
    }
}
