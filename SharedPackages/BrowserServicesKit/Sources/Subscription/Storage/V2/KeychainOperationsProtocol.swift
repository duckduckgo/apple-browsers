//
//  KeychainOperationsProtocol.swift
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
import Security

// MARK: - Keychain Operations Protocol

public protocol KeychainOperationsProtocol {
    func add(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

// MARK: - Real Keychain Operations

public final class RealKeychainOperations: KeychainOperationsProtocol {

    public init() {}

    public func add(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        return SecItemAdd(query, result)
    }

    public func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        return SecItemCopyMatching(query, result)
    }

    public func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        return SecItemUpdate(query, attributesToUpdate)
    }

    public func delete(_ query: CFDictionary) -> OSStatus {
        return SecItemDelete(query)
    }
}

// MARK: - Mock Keychain Operations

public final class MockKeychainOperations: KeychainOperationsProtocol {
    private var storage: [String: Data] = [:]
    private let queue = DispatchQueue(label: "mock.keychain.queue", attributes: .concurrent)

    // Control flags for testing error scenarios
    var shouldFailAdd = false
    var shouldFailCopyMatching = false
    var shouldFailUpdate = false
    var shouldFailDelete = false
    var addFailureStatus: OSStatus = errSecDuplicateItem
    var copyMatchingFailureStatus: OSStatus = errSecItemNotFound
    var updateFailureStatus: OSStatus = errSecItemNotFound
    var deleteFailureStatus: OSStatus = errSecItemNotFound

    func reset() {
        queue.sync(flags: .barrier) {
            self.storage.removeAll()
            self.shouldFailAdd = false
            self.shouldFailCopyMatching = false
            self.shouldFailUpdate = false
            self.shouldFailDelete = false
        }
    }

    public func add(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        return queue.sync(flags: .barrier) {
            guard !shouldFailAdd else {
                return addFailureStatus
            }
            let queryDict = query as NSDictionary
            guard let service = queryDict[kSecAttrService] as? String,
                  let data = queryDict[kSecValueData] as? Data else {
                return errSecParam
            }

            if storage[service] != nil {
                return errSecDuplicateItem
            }

            storage[service] = data
            return errSecSuccess
        }
    }

    public func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        return queue.sync(flags: .barrier) {
            guard !shouldFailCopyMatching else {
                return copyMatchingFailureStatus
            }
            let queryDict = query as NSDictionary
            guard let service = queryDict[kSecAttrService] as? String else {
                return errSecParam
            }

            guard let data = storage[service] else {
                return errSecItemNotFound
            }

            if let returnData = queryDict[kSecReturnData] as? Bool, returnData {
                result?.pointee = data as CFTypeRef
            }

            return errSecSuccess
        }
    }

    public func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        return queue.sync(flags: .barrier) {
            guard !shouldFailUpdate else { return updateFailureStatus }
            let queryDict = query as NSDictionary
            guard let service = queryDict[kSecAttrService] as? String else {
                return errSecParam
            }

            guard storage[service] != nil else {
                return errSecItemNotFound
            }

            let updateDict = attributesToUpdate as NSDictionary
            if let newData = updateDict[kSecValueData] as? Data {
                storage[service] = newData
            }

            return errSecSuccess
        }
    }

    public func delete(_ query: CFDictionary) -> OSStatus {
        return queue.sync(flags: .barrier) {
            guard !shouldFailDelete else { return deleteFailureStatus }
            let queryDict = query as NSDictionary
            guard let service = queryDict[kSecAttrService] as? String else {
                return errSecParam
            }

            guard storage[service] != nil else {
                return errSecItemNotFound
            }

            storage.removeValue(forKey: service)
            return errSecSuccess
        }
    }

    // Helper methods for testing
    func getStoredData(for service: String) -> Data? {
        return queue.sync {
            return storage[service]
        }
    }

    func setStoredData(_ data: Data, for service: String) {
        queue.sync(flags: .barrier) {
            self.storage[service] = data
        }
    }

    var storedItemsCount: Int {
        return queue.sync {
            return storage.count
        }
    }
}
