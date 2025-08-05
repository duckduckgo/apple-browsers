//
//  KeychainManager.swift
//  BrowserServicesKit
//
//  Created by Federico Cappelli on 05/08/2025.
//

import Foundation
import os.log
import Common

public struct KeychainManager {

    public typealias KeychainAttributes = [CFString: Any]
    private let keychainOperations: KeychainOperationsProtocol
    private let attributes: KeychainAttributes
    private var writingBacklog: [String: Data] = [:]

    public init(keychainOperations: KeychainOperationsProtocol = DefaultKeychainOperations(), attributes: KeychainAttributes) {
        self.keychainOperations = keychainOperations
        self.attributes = attributes
    }

    func retrieveData(forKey key: String) throws -> Data? {
        var query = attributes
        query[kSecAttrService] = key
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true

        var item: CFTypeRef?
        let status = keychainOperations.copyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            if let existingItem = item as? Data {
                return existingItem
            } else {
                throw AccountKeychainAccessError.failedToDecodeKeychainData
            }
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw AccountKeychainAccessError.keychainLookupFailure(status)
        }
    }

    mutating func store(data: Data, forKey key: String) throws {

        writingBacklog[key] = nil // Removing the data from the writing backlog if present

        var query = attributes
        query[kSecAttrService] = key
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData] = data

        let status = keychainOperations.add(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            Logger.subscriptionKeychain.debug("Successfully added keychain item for \(key)")
            return
        case errSecDuplicateItem:
            Logger.subscriptionKeychain.debug("Keychain item exists, updating for \(key)")
            let updateStatus = updateData(data, forKey: key)
            guard updateStatus == errSecSuccess else {
                Logger.subscriptionKeychain.error("Failed to update keychain item: \(updateStatus)")
                throw AccountKeychainAccessError.keychainSaveFailure(updateStatus)
            }
            Logger.subscriptionKeychain.debug("Successfully updated keychain item for \(key)")
        case errSecNotAvailable:
            Logger.subscriptionKeychain.error("Failed to add keychain item: \(status.humanReadableDescription), adding data to writing queue")
            writingBacklog[key] = data
        default:
            Logger.subscriptionKeychain.error("Failed to add keychain item: \(status.humanReadableDescription)")
            throw AccountKeychainAccessError.keychainSaveFailure(status)
        }
    }

    mutating private func updateData(_ data: Data, forKey key: String) -> OSStatus {

        writingBacklog[key] = nil // Removing the data from the writing backlog if present

        var query = attributes
        query[kSecAttrService] = key

        let newAttributes = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as [CFString: Any]

        let status = keychainOperations.update(query as CFDictionary, newAttributes as CFDictionary)

        if status != errSecSuccess {
            Logger.subscriptionKeychain.error("SecItemUpdate failed with status: \(status.humanReadableDescription) for field: \(key)")
        }

        return status
    }

    mutating func deleteItem(forKey key: String) throws {

        writingBacklog[key] = nil // Removing the data from the writing backlog if present

        var query = attributes
        query[kSecAttrService] = key

        let status = keychainOperations.delete(query as CFDictionary)

        if status == errSecSuccess {
            Logger.subscriptionKeychain.debug("Successfully deleted keychain item for \(key)")
        } else if status == errSecItemNotFound {
            Logger.subscriptionKeychain.debug("Keychain item not found for deletion: \(key)")
        } else {
            Logger.subscriptionKeychain.error("Failed to delete keychain item: \(status.humanReadableDescription)")
            throw AccountKeychainAccessError.keychainDeleteFailure(status)
        }
    }
}
