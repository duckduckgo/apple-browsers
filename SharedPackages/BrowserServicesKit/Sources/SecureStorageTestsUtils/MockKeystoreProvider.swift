//
//  MockKeystoreProvider.swift
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
import SecureStorage

public final class MockKeychainService: KeychainService {

    public enum Mode {
        case nothingFound
        case v4Found
        case v3Found
        case v2Found
        case v1Found
    }

    public var latestAddQuery: [String: Any] = [:]
    public var latestItemMatchingQuery: [String: Any] = [:]
    public var itemMatchingCallCount = 0
    public var addCallCount = 0

    public var mode: Mode = .nothingFound

    public init() {}

    public func itemMatching(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        itemMatchingCallCount += 1
        latestItemMatchingQuery = query

        func setResult() {
            let originalString = "Mock Keychain data!"
            let data = originalString.data(using: .utf8)!
            let encodedString = data.base64EncodedString()
            let mockResult = encodedString.data(using: .utf8)! as CFData

            if let result = result {
                result.pointee = mockResult
            }
        }

        switch mode {
        case .nothingFound:
            return errSecItemNotFound
        case .v4Found:
            setResult()
            return errSecSuccess
        case .v3Found:
#if os(iOS)
            if itemMatchingCallCount == 2 {
                setResult()
                return errSecSuccess
            } else {
                return errSecItemNotFound
            }
#else
            setResult()
            return errSecSuccess
#endif
        case .v2Found:
            if itemMatchingCallCount == 2 {
                setResult()
                return errSecSuccess
            } else {
                return errSecItemNotFound
            }
        case .v1Found:
            if itemMatchingCallCount == 3 {
                setResult()
                return errSecSuccess
            } else {
                return errSecItemNotFound
            }
        }
    }

    public func add(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        latestAddQuery = query
        addCallCount += 1
        return errSecSuccess
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        return errSecSuccess
    }
}

public class MockKeystoreProvider: SecureStorageKeyStoreProvider {

    public init() {}

    // swiftlint:disable identifier_name
    public let keychainService: SecureStorage.KeychainService = MockKeychainService()
    public var _l1Key: Data?
    public var _encryptedL2Key: Data?
    public var _generatedPassword: Data?
    public var _generatedPasswordCleared = false
    public var _lastEncryptedL2Key: Data?
    // swiftlint:enable identifier_name

    public var generatedPasswordEntryName: String {
        return ""
    }

    public var l1KeyEntryName: String {
        return ""
    }

    public var l2KeyEntryName: String {
        return ""
    }

    public var keychainServiceName: String {
        return ""
    }

    public func attributesForEntry(named: String, serviceName: String) -> [String: Any] {
        return [:]
    }

    public func storeGeneratedPassword(_ password: Data) throws {
    }

    public func generatedPassword() throws -> Data? {
        return _generatedPassword
    }

    public func clearGeneratedPassword() throws {
        _generatedPasswordCleared = true
    }

    public func storeL1Key(_ data: Data) throws {
    }

    public func l1Key() throws -> Data? {
        return _l1Key
    }

    public func storeEncryptedL2Key(_ data: Data) throws {
        _lastEncryptedL2Key = data
    }

    public func encryptedL2Key() throws -> Data? {
        return _encryptedL2Key
    }

}
