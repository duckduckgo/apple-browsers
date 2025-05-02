//
//  AutofillCreditCardDetailsViewModel.swift
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

protocol AutofillCreditCardDetailsViewModelDelegate: AnyObject {
    func autofillCreditCardDetailsViewModelDidSave()
    func autofillCreditCardDetailsViewModelDelete(card: SecureVaultModels.CreditCard)
    func autofillCreditCardDetailsViewModelDismiss()
}

final class AutofillCreditCardDetailsViewModel: ObservableObject {
    
    enum ViewMode {
        case edit
        case view
        case new
    }
    
    enum PasteboardCopyAction {
        case cardNumber
        case expirationDate
        case cardSecurityCode
        case cardholderName
    }
    
    weak var delegate: AutofillCreditCardDetailsViewModelDelegate?
    
    @Published var cardNumber = ""
    @Published var formattedCardNumber: String = ""
    @Published var isCardValid: Bool = false
    
    @Published var expirationMonth: Int?
    @Published var expirationYear: Int?
    @Published var formattedExpiration = ""
    
    @Published var cardSecurityCode = ""
    @Published var isSecurityCodeHidden = true
    
    @Published var cardholderName = ""
    @Published var cardTitle = ""
    @Published var selectedCell: UUID?
    @Published var authenticationRequired: Bool = false
    @Published var viewMode: ViewMode = .view {
        didSet {
            selectedCell = nil
            
            if viewMode == .edit && cardSecurityCode.isEmpty {
                isSecurityCodeHidden = false
            } else {
                isSecurityCodeHidden = true
            }
        }
    }
    
    var creditCard: SecureVaultModels.CreditCard?
    
    var navigationTitle: String {
        switch viewMode {
        case .edit:
            return UserText.autofillCreditCardDetailsEditTitle
        case .view:
            guard let creditCard else {
                return UserText.autofillCreditCardDetailsDefaultTitle
            }
            return creditCard.title.isEmpty ? type.displayName : creditCard.title
        case .new:
            return UserText.autofillCreditCardDetailsNewTitle
        }
    }
    
    var userVisibleCardSecurityCode: String {
        let textMasker = TextMasker(text: cardSecurityCode)
        return isSecurityCodeHidden ? textMasker.maskedText : textMasker.originalText
    }
    
    var canSave: Bool {
        return isCardValid
    }
    
    private var type: CreditCardValidation.CardType {
        guard let creditCard else {
            return .unknown
        }
        return CreditCardValidation.type(for: creditCard.cardNumber)
    }
    
    private static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM / yy"
        return dateFormatter
    }()
    
    private let authenticator: UserAuthenticator
    private var secureVault: (any AutofillSecureVault)?
    private var cancellables = Set<AnyCancellable>()
    
    internal init(authenticator: UserAuthenticator, secureVault: (any AutofillSecureVault)? = nil, creditCard: SecureVaultModels.CreditCard? = nil) {
        self.authenticator = authenticator
        self.secureVault = secureVault
        self.creditCard = creditCard
        if let creditCard = creditCard {
            self.updateData(with: creditCard)
        } else {
            viewMode = .new
        }
    }
    
    func toggleEditMode() {
        withAnimation {
            if viewMode == .edit {
                viewMode = .view
                if let creditCard = creditCard {
                    updateData(with: creditCard)
                }
            } else {
                viewMode = .edit
            }
        }
    }
    
    func lockUI() {
        authenticationRequired = true
        authenticator.logOut()
    }
    
    func authenticate(completion: @escaping (AutofillLoginListAuthenticator.AuthError?) -> Void) {
        if cancellables.isEmpty {
            setupCancellables()
        }
        
        if !authenticator.canAuthenticate() || !authenticationRequired {
            completion(nil)
            return
        }
        
        authenticator.authenticate(completion: completion)
    }
    
    func copyToPasteboard(_ action: PasteboardCopyAction) {
        var message = ""
        switch action {
        case .cardNumber:
            message = UserText.autofillCreditCardCopyToastCopiedCardNumber
            UIPasteboard.general.string = cardNumber
        case .expirationDate:
            message = UserText.autofillCreditCardCopyToastCopiedExpirationDate
            UIPasteboard.general.string = formattedExpiration
        case .cardSecurityCode:
            message = UserText.autofillCreditCardCopyToastCopiedCVV
            UIPasteboard.general.string = cardSecurityCode
        case .cardholderName:
            message = UserText.autofillCreditCardCopyToastCopiedCardName
            UIPasteboard.general.string = cardholderName
        }
        
        presentCopyConfirmation(message: message)
    }
    
    func save() {
        if secureVault == nil {
            secureVault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
        }
        
        guard let vault = secureVault else {
            assertionFailure("Failed to create secure vault")
            return
        }
        
        switch viewMode {
        case .edit:
            guard let cardId = creditCard?.id else {
                assertionFailure("Trying to save edited card, but the card doesn't exist")
                return
            }
            
            do {
                if var creditCard = try vault.creditCardFor(id: cardId) {
                    creditCard.cardNumberData = cardNumber.filter { !$0.isWhitespace }.data(using: .utf8)!
                    creditCard.expirationMonth = expirationMonth
                    creditCard.expirationYear = expirationYear
                    creditCard.cardSecurityCode = cardSecurityCode
                    creditCard.cardholderName = cardholderName
                    creditCard.title = cardTitle
                    
                    _ = try vault.storeCreditCard(creditCard)
                    delegate?.autofillCreditCardDetailsViewModelDidSave()
                    
                    if let newCard = try vault.creditCardFor(id: cardId) {
                        self.updateData(with: newCard)
                    }
                    
                    viewMode = .view
                }
                
            } catch let error {
                handleSecureVaultError(error)
            }
        case .view:
            break
        case .new:
            let creditCard = SecureVaultModels.CreditCard(
                title: cardTitle,
                cardNumber: cardNumber.filter { !$0.isWhitespace },
                cardholderName: cardholderName,
                cardSecurityCode: cardSecurityCode,
                expirationMonth: expirationMonth,
                expirationYear: expirationYear
            )
            
            do {
                let cardId = try vault.storeCreditCard(creditCard)
                delegate?.autofillCreditCardDetailsViewModelDidSave()
                
                if let newCard = try vault.creditCardFor(id: cardId) {
                    self.updateData(with: newCard)
                }
            } catch let error {
                handleSecureVaultError(error)
            }
        }
    }
    
    func delete() {
        guard let creditCard = creditCard else {
            assertionFailure("Trying to delete creditCard, but the creditCard doesn't exist")
            return
        }
        
        delegate?.autofillCreditCardDetailsViewModelDelete(card: creditCard)
    }
    
    func expirationDateString() -> String {
        guard let month = expirationMonth,
              let year = expirationYear,
              let date = DateComponents(calendar: Calendar.current, year: year, month: month).date else {
            return ""
        }
        return AutofillCreditCardDetailsViewModel.dateFormatter.string(from: date)
    }
    
    // MARK: Private methods

    private func setupCancellables() {
        authenticator.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateAuthViews()
                }
                .store(in: &cancellables)
    }

    private func updateAuthViews() {
        switch authenticator.state {
        case .loggedOut, .notAvailable:
            self.authenticationRequired = true
        case .loggedIn:
            self.authenticationRequired = false
        }
    }

    private func updateData(with creditCard: SecureVaultModels.CreditCard) {
        self.creditCard = creditCard
        cardNumber = creditCard.cardNumber
        formattedCardNumber = CreditCardValidation.formattedCardNumber(self.cardNumber)
        isCardValid = CreditCardValidation.isValidCardNumber(self.cardNumber)
        
        expirationMonth = creditCard.expirationMonth
        expirationYear = creditCard.expirationYear
        formattedExpiration = expirationDateString()
        
        cardSecurityCode = creditCard.cardSecurityCode ?? ""
        cardholderName = creditCard.cardholderName ?? ""
        cardTitle = creditCard.title
    }
    
    private func presentCopyConfirmation(message: String) {
        DispatchQueue.main.async {
            ActionMessageView.present(message: message,
                                      actionTitle: "",
                                      onAction: {})
        }
    }
    
    private func handleSecureVaultError(_ error: Error) {
        Pixel.fire(pixel: .secureVaultError, error: error)
    }
}
