//
//  SecureStorageKeyStoreProvider.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

/// Conforming types provide methods which interact with the system Keychain. Mainly used to enable testing.
public protocol KeychainService {
    func itemMatching(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func add(_ attributes: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], _ attributesToUpdate: [String: Any]) -> OSStatus
}

public extension KeychainService {
    func itemMatching(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query as CFDictionary, result)
    }

    func add(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }

    func update(_ query: [String: Any], _ attributesToUpdate: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
    }
}

public struct DefaultKeychainService: KeychainService {
    public init() {}
}

public enum SecureStorageKeyStoreEvent {
    case l1KeyMigration
    case l2KeyMigration
    case l2KeyPasswordMigration
    case databaseRecreation
}

public protocol SecureStorageKeyStoreProvider {

    var keychainService: KeychainService { get }
    var generatedPasswordEntryName: String { get }
    var l1KeyEntryName: String { get }
    var l2KeyEntryName: String { get }
    var keychainServiceName: String { get }
    var keychainAccessibilityValue: String { get }

    func storeGeneratedPassword(_ password: Data) throws
    func generatedPassword() throws -> Data?
    func clearGeneratedPassword() throws

    func storeL1Key(_ data: Data) throws
    func l1Key() throws -> Data?

    func storeEncryptedL2Key(_ data: Data) throws
    func encryptedL2Key() throws -> Data?

    func readData(named: String, serviceName: String) throws -> Data?
    func writeData(_ data: Data, named name: String, serviceName: String) throws
    func attributesForEntry(named: String, serviceName: String) -> [String: Any]

}

public extension SecureStorageKeyStoreProvider {

    var keychainService: KeychainService {
        DefaultKeychainService()
    }

    var keychainAccessibilityValue: String {
        kSecAttrAccessibleWhenUnlocked as String
    }

    func generatedPassword() throws -> Data? {
        return try readData(named: generatedPasswordEntryName, serviceName: keychainServiceName)
    }

    func l1Key() throws -> Data? {
        return try readData(named: l1KeyEntryName, serviceName: keychainServiceName)
    }

    func encryptedL2Key() throws -> Data? {
        return try readData(named: l2KeyEntryName, serviceName: keychainServiceName)
    }

    func storeGeneratedPassword(_ password: Data) throws {
        try writeData(password, named: generatedPasswordEntryName,
                      serviceName: keychainServiceName)
    }

    func clearGeneratedPassword() throws {
        try deleteEntry(named: generatedPasswordEntryName)
    }

    func storeL1Key(_ data: Data) throws {
        try writeData(data, named: l1KeyEntryName,
                      serviceName: keychainServiceName)
    }

    func storeEncryptedL2Key(_ data: Data) throws {
        try writeData(data, named: l2KeyEntryName,
                      serviceName: keychainServiceName)
    }

    func readData(named name: String, serviceName: String) throws -> Data? {
        var query = attributesForEntry(named: name, serviceName: serviceName)
        query[kSecReturnData as String] = true
        query[kSecAttrService as String] = serviceName

        var item: CFTypeRef?

        let status = keychainService.itemMatching(query, &item)
        switch status {
        case errSecSuccess:
            guard let itemData = item as? Data,
                  let itemString = String(data: itemData, encoding: .utf8),
                  let decodedData = Data(base64Encoded: itemString) else {
                throw SecureStorageError.keystoreError(status: status)
            }
            return decodedData

        case errSecItemNotFound:
            return nil

        default:
            throw SecureStorageError.keystoreError(status: status)
        }
    }

    func writeData(_ data: Data, named name: String, serviceName: String) throws {
        let base64String = data.base64EncodedString()

        guard let base64Data = base64String.data(using: .utf8) else {
            throw SecureStorageError.encodingFailed
        }

        var query = attributesForEntry(named: name, serviceName: serviceName)
        query[kSecAttrService as String] = serviceName
        query[kSecAttrAccessible as String] = keychainAccessibilityValue
        query[kSecValueData as String] = base64Data

        var status = keychainService.add(query, nil)

        if status == errSecDuplicateItem {
            status = keychainService.update(query, [
                kSecAttrAccessible as String: keychainAccessibilityValue,
                kSecValueData as String: base64Data
            ] as [String: Any])
        }

        guard status == errSecSuccess else {
            throw SecureStorageError.keystoreError(status: status)
        }
    }

    // MARK: - Private Helpers

    private func deleteEntry(named name: String) throws {
        let query = attributesForEntry(named: name, serviceName: keychainServiceName)

        let status = keychainService.delete(query)
        switch status {
        case errSecItemNotFound, errSecSuccess: break
        default:
            throw SecureStorageError.keystoreError(status: status)
        }
    }

}
