//
//  KeychainOperationsProviding.swift
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

public protocol KeychainOperationsProviding {
    func add(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

// MARK: - Real Keychain Operations

public final class DefaultKeychainOperations: KeychainOperationsProviding {

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
