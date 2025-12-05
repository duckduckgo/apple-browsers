//
//  SecureVaultCreditCardImporter.swift
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
import SecureStorage
import os.log

public final class SecureVaultCreditCardImporter: CreditCardImporter {

    private struct ImportError: DataImportError {
        enum OperationType: Int {
            case vaultError
        }

        var action: DataImportAction { .generic }
        let type: OperationType
        let underlyingError: Error?

        var errorType: DataImport.ErrorType {
            switch type {
            case .vaultError:
                return .keychainError
            }
        }
    }

    public init() {}

    public func importCreditCards(_ cards: [ImportedCreditCard],
                                  vault: (any AutofillSecureVault)?,
                                  completion: @escaping (Int) throws -> Void) throws -> DataImport.DataTypeSummary {

        guard let vault else {
            throw ImportError(type: .vaultError, underlyingError: nil)
        }

        var successful = 0
        var duplicateItems: [DataImport.DataImportItem] = []
        var failedItems: [DataImport.DataImportItem] = []

        let sortedCards = cards.sorted(by: { $0.lastUsedTime ?? .distantPast < $1.lastUsedTime ?? .distantPast })

        for (index, importedCard) in sortedCards.enumerated() {
            do {
                let creditCardToImport = SecureVaultModels.CreditCard(
                    title: importedCard.title,
                    cardNumber: importedCard.cardNumber,
                    cardholderName: importedCard.cardholderName,
                    cardSecurityCode: importedCard.cardSecurityCode,
                    expirationMonth: importedCard.expirationMonth,
                    expirationYear: importedCard.expirationYear
                )

                if let existingCard = try vault.existingCardForAutofill(matching: creditCardToImport) {
                    // Check if imported card has newer expiry
                    if hasNewerExpiryDate(existing: existingCard, importing: creditCardToImport) {
                        // Update with all non-empty fields from imported card
                        let updatedCard = updateCardWithImportedData(existing: existingCard, importing: creditCardToImport)
                        try vault.storeCreditCard(updatedCard)
                        successful += 1
                    } else {
                        let maskedNumber = maskCardNumber(importedCard.cardNumber)
                        duplicateItems.append(.creditCard(
                            maskedNumber: maskedNumber,
                            cardholderName: importedCard.cardholderName,
                            errorMessage: nil
                        ))
                    }
                } else {
                    try vault.storeCreditCard(creditCardToImport)
                    successful += 1
                }
            } catch {
                let maskedNumber = maskCardNumber(importedCard.cardNumber)
                let errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failedItems.append(.creditCard(
                    maskedNumber: maskedNumber,
                    cardholderName: importedCard.cardholderName,
                    errorMessage: errorMessage
                ))
                Logger.autofill.debug("Failed to import card: \(error)")
            }

            try completion(index + 1)
        }

        return DataImport.DataTypeSummary(
            successful: successful,
            duplicateItems: duplicateItems,
            failedItems: failedItems
        )
    }

    // MARK: - Helper Functions

    /// Masks all but the final 4 digits of the provided card number
    ///
    private func maskCardNumber(_ cardNumber: String) -> String {
        guard cardNumber.count >= 4 else {
            return "****"
        }
        let last4 = String(cardNumber.suffix(4))
        return "****\(last4)"
    }

    private func hasNewerExpiryDate(existing: SecureVaultModels.CreditCard,
                                    importing: SecureVaultModels.CreditCard) -> Bool {
        guard let importingMonth = importing.expirationMonth,
              let importingYear = importing.expirationYear,
              let existingMonth = existing.expirationMonth,
              let existingYear = existing.expirationYear else {
            return false
        }

        if importingYear > existingYear {
            return true
        } else if importingYear == existingYear && importingMonth > existingMonth {
            return true
        }

        return false
    }

    private func updateCardWithImportedData(existing: SecureVaultModels.CreditCard,
                                            importing: SecureVaultModels.CreditCard) -> SecureVaultModels.CreditCard {
        // Update all fields with imported data (except where importing field is empty)
        return SecureVaultModels.CreditCard(
            id: existing.id,
            title: importing.title.isEmpty == false ? importing.title : existing.title,
            cardNumber: existing.cardNumber, // Should be the same
            cardholderName: importing.cardholderName?.isEmpty == false ? importing.cardholderName : existing.cardholderName,
            cardSecurityCode: importing.cardSecurityCode?.isEmpty == false ? importing.cardSecurityCode : existing.cardSecurityCode,
            expirationMonth: importing.expirationMonth ?? existing.expirationMonth,
            expirationYear: importing.expirationYear ?? existing.expirationYear,
            created: existing.created
        )
    }
}
