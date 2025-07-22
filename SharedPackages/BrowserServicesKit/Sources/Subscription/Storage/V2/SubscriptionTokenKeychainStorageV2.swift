//
//  SubscriptionTokenKeychainStorageV2.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import os.log
import Networking
import Common

public enum KeychainErrorSource: String {
    case browser
    case vpn
    case pir
    case shared
}

public enum KeychainErrorAuthVersion: String {
    case v1
    case v2
}

public final class SubscriptionTokenKeychainStorageV2: AuthTokenStoring {

    public struct RetryConfiguration {
        let maxAttempts: Int
        let baseDelay: TimeInterval

        public static let `default` = RetryConfiguration(maxAttempts: 5, baseDelay: 0.2)

        func delay(for attempt: Int) -> TimeInterval {
            baseDelay * log2(Double(attempt + 2))
        }
    }

    private let keychainType: KeychainType
    private let errorEventsHandler: (AccountKeychainAccessType, AccountKeychainAccessError) -> Void
    private let accessQueue = DispatchQueue(label: "keychain.subscription.access", qos: .userInitiated)
    private let keychainOperations: KeychainOperationsProtocol
    private let retryConfig: RetryConfiguration

    public init(keychainType: KeychainType = .dataProtection(.unspecified),
                errorEventsHandler: @escaping (AccountKeychainAccessType, AccountKeychainAccessError) -> Void,
                keychainOperations: KeychainOperationsProtocol = DefaultKeychainOperations(),
                retryConfiguration: RetryConfiguration = RetryConfiguration.default) {
        self.keychainType = keychainType
        self.errorEventsHandler = errorEventsHandler
        self.keychainOperations = keychainOperations
        self.retryConfig = retryConfiguration
    }

    // MARK: - Public Interface

    public func getTokenContainer() throws -> TokenContainer? {
        try executeWithErrorHandling(accessType: .getAuthToken) {
            try retrieveTokenContainer()
        }
    }

    public func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        try executeWithErrorHandling(accessType: .storeAuthToken) {
            try storeTokenContainer(tokenContainer)
        }
    }

    // MARK: - Private Core Operations

    private func retrieveTokenContainer() throws -> TokenContainer? {
        guard let data = try performKeychainOperation(operation: { try retrieveData(forField: .tokenContainer) }) else {
            Logger.subscriptionKeychain.debug("TokenContainer not found")
            return nil
        }

        guard let container: TokenContainer = CodableHelper.decode(jsonData: data) else {
            throw AccountKeychainAccessError.failedToDecodeKeychainData
        }

        return container
    }

    private func storeTokenContainer(_ tokenContainer: TokenContainer?) throws {
        guard let tokenContainer else {
            Logger.subscriptionKeychain.debug("Remove TokenContainer")
            try performKeychainOperation(operation: { try deleteItem(forField: .tokenContainer) })
            return
        }

        guard let data = CodableHelper.encode(tokenContainer) else {
            throw AccountKeychainAccessError.failedToEncodeKeychainData
        }

        try performKeychainOperation(operation: { try store(data: data, forField: .tokenContainer) })
    }

    // MARK: - Error Handling

    private func executeWithErrorHandling<T>(accessType: AccountKeychainAccessType,
                                             operation: () throws -> T) throws -> T {
        do {
            return try accessQueue.sync { try operation() }
        } catch {
            handleError(error, accessType: accessType)
            throw error
        }
    }

    private func handleError(_ error: Error, accessType: AccountKeychainAccessType) {
        let keychainError: AccountKeychainAccessError

        if let accountError = error as? AccountKeychainAccessError {
            keychainError = accountError
        } else {
            keychainError = .internalError
            Logger.subscriptionKeychain.fault("Unexpected error: \(error, privacy: .public)")
        }

        errorEventsHandler(accessType, keychainError)
    }

    // MARK: - Retry Logic

    private func performKeychainOperation<T>(operation: () throws -> T) throws -> T {
        var lastError: Error?

        for attempt in 0..<retryConfig.maxAttempts {
            do {
                return try operation()
            } catch {
                lastError = error

                guard isRetryable(error), attempt < retryConfig.maxAttempts - 1 else {
                    throw error
                }

                let delay = retryConfig.delay(for: attempt)
                Logger.subscriptionKeychain.error("Keychain operation failed (attempt \(attempt + 1)/\(self.retryConfig.maxAttempts)), retrying in \(delay) seconds: \(error)"
                )

                Thread.sleep(forTimeInterval: delay)
            }
        }

        throw lastError ?? AccountKeychainAccessError.internalError
    }

    private func isRetryable(_ error: Error) -> Bool {
        guard let keychainError = error as? AccountKeychainAccessError else { return true }

        switch keychainError {

        case .keychainLookupFailure(let status),
             .keychainSaveFailure(let status),
             .keychainDeleteFailure(let status):
            return status.isRetryable

        default:
            /*
             .failedToDecodeKeychainData,
             .failedToDecodeKeychainValueAsData,
             .failedToDecodeKeychainDataAsString,
             .failedToEncodeKeychainData:
             */
            return false
        }
    }

    // MARK: - Keychain Field Definition

    enum SubscriptionKeychainField: String {
        case tokenContainer = "subscription.v2.tokens"

        var serviceKey: String {
            "com.duckduckgo.\(rawValue)"
        }
    }

    // MARK: - Low-Level Keychain Operations

    private func retrieveData(forField field: SubscriptionKeychainField) throws -> Data? {
        var query = baseQuery()
        query[kSecAttrService] = field.serviceKey
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true

        var item: CFTypeRef?
        let status = keychainOperations.copyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw AccountKeychainAccessError.failedToDecodeKeychainData
            }
            return data

        case errSecItemNotFound:
            return nil

        default:
            throw AccountKeychainAccessError.keychainLookupFailure(status)
        }
    }

    private func store(data: Data, forField field: SubscriptionKeychainField) throws {
        var query = baseQuery()
        query[kSecAttrService] = field.serviceKey
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData] = data

        let status = keychainOperations.add(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            Logger.subscriptionKeychain.debug("Successfully added keychain item for \(field.serviceKey)")

        case errSecDuplicateItem:
            Logger.subscriptionKeychain.debug("Keychain item exists, updating for \(field.serviceKey)")
            try updateItem(data: data, forField: field)

        default:
            Logger.subscriptionKeychain.error("Failed to add keychain item: \(status.humanReadableDescription)")
            throw AccountKeychainAccessError.keychainSaveFailure(status)
        }
    }

    private func updateItem(data: Data, forField field: SubscriptionKeychainField) throws {
        var query = baseQuery()
        query[kSecAttrService] = field.serviceKey

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = keychainOperations.update(query as CFDictionary, attributes as CFDictionary)

        guard status == errSecSuccess else {
            Logger.subscriptionKeychain.error("SecItemUpdate failed with status: \(status.humanReadableDescription) for field: \(field.serviceKey)"
            )
            throw AccountKeychainAccessError.keychainSaveFailure(status)
        }

        Logger.subscriptionKeychain.debug("Successfully updated keychain item for \(field.serviceKey)")
    }

    private func deleteItem(forField field: SubscriptionKeychainField) throws {
        var query = baseQuery()
        query[kSecAttrService] = field.serviceKey

        let status = keychainOperations.delete(query as CFDictionary)

        switch status {
        case errSecSuccess:
            Logger.subscriptionKeychain.debug("Successfully deleted keychain item for \(field.serviceKey)")

        case errSecItemNotFound:
            Logger.subscriptionKeychain.debug("Keychain item not found for deletion: \(field.serviceKey)")

        default:
            Logger.subscriptionKeychain.error("Failed to delete keychain item: \(status.humanReadableDescription)")
            throw AccountKeychainAccessError.keychainDeleteFailure(status)
        }
    }

    private func baseQuery() -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: false
        ]
        query.merge(keychainType.queryAttributes()) { _, new in new }
        return query
    }
}
