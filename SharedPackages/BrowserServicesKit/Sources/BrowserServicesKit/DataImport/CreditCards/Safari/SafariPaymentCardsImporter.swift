//
//  SafariPaymentCardsImporter.swift
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

#if os(iOS)
final public class SafariPaymentCardsImporter: DataImporter {

    private struct ImportError: DataImportError {
        enum OperationType: Int {
            case cannotReadFile
            case invalidJSON
            case malformedData
        }

        var action: DataImportAction { .generic }
        let type: OperationType
        let underlyingError: Error?

        var errorType: DataImport.ErrorType {
            switch type {
            case .cannotReadFile, .invalidJSON, .malformedData:
                return .dataCorrupted
            }
        }
    }

    private let fileURL: URL?
    private let jsonContent: String?
    private let creditCardImporter: CreditCardImporter
    private let vault: (any AutofillSecureVault)?

    public init(fileURL: URL?,
                jsonContent: String? = nil,
                creditCardImporter: CreditCardImporter,
                vault: (any AutofillSecureVault)?) {
        self.fileURL = fileURL
        self.jsonContent = jsonContent
        self.creditCardImporter = creditCardImporter
        self.vault = vault
    }

    // MARK: - DataImporter Protocol

    public var importableTypes: [DataImport.DataType] {
        return [.creditCards]
    }

    public func importData(types: Set<DataImport.DataType>) -> DataImportTask {
        .detachedWithProgress { updateProgress in
            do {
                let result = try await self.importCreditCardsSync(updateProgress: updateProgress)
                return [.creditCards: result]
            } catch is CancellationError {
            } catch {
                assertionFailure("Only CancellationError should be thrown here")
            }
            return [:]
        }
    }

    // MARK: - Private Methods

    private func importCreditCardsSync(updateProgress: @escaping DataImportProgressCallback) async throws -> DataImportResult<DataImport.DataTypeSummary> {

        try updateProgress(.importingCreditCards(numberOfCreditCards: nil, fraction: 0.0))

        let fileContents: String
        do {
            if let jsonContent = jsonContent {
                fileContents = jsonContent
            } else if let fileURL = fileURL {
                fileContents = try String(contentsOf: fileURL, encoding: .utf8)
            } else {
                throw ImportError(type: .cannotReadFile, underlyingError: nil)
            }
        } catch {
            return .failure(ImportError(type: .cannotReadFile, underlyingError: error))
        }

        do {
            try updateProgress(.importingCreditCards(numberOfCreditCards: nil, fraction: 0.2))

            let creditCards = try Self.extractCreditCards(from: fileContents)

            try updateProgress(.importingCreditCards(numberOfCreditCards: creditCards.count, fraction: 0.5))

            let summary = try creditCardImporter.importCreditCards(creditCards, vault: vault) { count in
                try updateProgress(.importingCreditCards(numberOfCreditCards: count, fraction: 0.5 + 0.5 * (Double(count) / Double(creditCards.count))))
            }

            try updateProgress(.importingCreditCards(numberOfCreditCards: creditCards.count, fraction: 1.0))

            return .success(summary)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as any DataImportError {
            return .failure(error)
        } catch {
            return .failure(ImportError(type: .malformedData, underlyingError: error))
        }
    }

    // MARK: - Static Methods

    public static func extractCreditCards(from jsonContent: String) throws -> [ImportedCreditCard] {
        guard let data = jsonContent.data(using: .utf8) else {
            throw ImportError(type: .invalidJSON, underlyingError: nil)
        }

        let paymentCardData: SafariPaymentCardJSON

        do {
            paymentCardData = try JSONDecoder().decode(SafariPaymentCardJSON.self, from: data)
        } catch {
            throw ImportError(type: .invalidJSON, underlyingError: error)
        }

        let creditCards = paymentCardData.paymentCards.compactMap { card -> ImportedCreditCard? in
            // Convert microseconds to Date if available
            let lastUsedDate: Date? = card.cardLastUsedTimeUsec.map { usec in
                Date(timeIntervalSince1970: Double(usec) / 1_000_000.0)
            }

            return ImportedCreditCard(
                title: card.cardName,
                cardNumber: card.cardNumber,
                cardholderName: card.cardholderName,
                cardSecurityCode: nil, // Safari export does not include CVC
                expirationMonth: card.cardExpirationMonth,
                expirationYear: card.cardExpirationYear,
                lastUsedTime: lastUsedDate
            )
        }

        return creditCards
    }

    static public func totalValidCreditCards(in fileURL: URL) -> Int {
        guard let fileContents = try? String(contentsOf: fileURL, encoding: .utf8),
              let cards = try? extractCreditCards(from: fileContents) else {
            return 0
        }
        return cards.count
    }

    static public func totalValidCreditCards(in jsonContent: String) -> Int {
        guard let cards = try? extractCreditCards(from: jsonContent) else {
            return 0
        }
        return cards.count
    }
}

// MARK: - SafariPaymentCardJSON

private struct SafariPaymentCardJSON: Codable {
    let paymentCards: [PaymentCard]

    struct PaymentCard: Codable {
        let cardNumber: String
        let cardName: String?
        let cardholderName: String?
        let cardExpirationMonth: Int?
        let cardExpirationYear: Int?
        let cardLastUsedTimeUsec: Double?

        enum CodingKeys: String, CodingKey {
            case cardNumber = "card_number"
            case cardName = "card_name"
            case cardholderName = "cardholder_name"
            case cardExpirationMonth = "card_expiration_month"
            case cardExpirationYear = "card_expiration_year"
            case cardLastUsedTimeUsec = "card_last_used_time_usec"
        }
    }

    enum CodingKeys: String, CodingKey {
        case paymentCards = "payment_cards"
    }
}
#endif
