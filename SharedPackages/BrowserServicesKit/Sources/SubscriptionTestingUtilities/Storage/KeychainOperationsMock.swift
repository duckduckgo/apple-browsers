//
//  KeychainOperationsMock.swift
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
@testable import Subscription

public final class KeychainOperationsMock: KeychainOperationsProviding {

    private var storage: [String: Data] = [:]
    private let queue = DispatchQueue(label: "mock.keychain.queue", attributes: .concurrent)

    // Control flags for testing error scenarios
    public var shouldFailAdd = false
    public var shouldFailCopyMatching = false
    public var shouldFailUpdate = false
    public var shouldFailDelete = false
    public var addFailureStatus: OSStatus = errSecDuplicateItem
    public var copyMatchingFailureStatus: OSStatus = errSecItemNotFound
    public var updateFailureStatus: OSStatus = errSecItemNotFound
    public var deleteFailureStatus: OSStatus = errSecItemNotFound

    public init(storage: [String: Data] = [:], shouldFailAdd: Bool = false, shouldFailCopyMatching: Bool = false, shouldFailUpdate: Bool = false, shouldFailDelete: Bool = false, addFailureStatus: OSStatus = errSecDuplicateItem, copyMatchingFailureStatus: OSStatus = errSecItemNotFound, updateFailureStatus: OSStatus = errSecItemNotFound, deleteFailureStatus: OSStatus = errSecItemNotFound) {
        self.storage = storage
        self.shouldFailAdd = shouldFailAdd
        self.shouldFailCopyMatching = shouldFailCopyMatching
        self.shouldFailUpdate = shouldFailUpdate
        self.shouldFailDelete = shouldFailDelete
        self.addFailureStatus = addFailureStatus
        self.copyMatchingFailureStatus = copyMatchingFailureStatus
        self.updateFailureStatus = updateFailureStatus
        self.deleteFailureStatus = deleteFailureStatus
    }

    public func reset() {
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
    public func getStoredData(for service: String) -> Data? {
        return queue.sync {
            return storage[service]
        }
    }

    public func setStoredData(_ data: Data, for service: String) {
        queue.sync(flags: .barrier) {
            self.storage[service] = data
        }
    }

    public var storedItemsCount: Int {
        return queue.sync {
            return storage.count
        }
    }
}
