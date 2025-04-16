//
//  MockCryptoProvider.swift
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

public class MockCryptoProvider: SecureStorageCryptoProvider {

    public init() {}

    public var passwordSalt: Data {
        return Data()
    }

    public var keychainServiceName: String {
        return "service"
    }

    public var keychainAccountName: String {
        return "account"
    }

    // swiftlint:disable identifier_name
    public var _derivedKey: Data?
    public var _decryptedData: Data?
    public var _lastDataToDecrypt: Data?
    public var _lastDataToEncrypt: Data?
    public var _lastKey: Data?
    public var hashingSalt: Data?
    // swiftlint:enable identifier_name

    public func generateSecretKey() throws -> Data {
        return Data()
    }

    public func generatePassword() throws -> Data {
        return Data()
    }

    public func deriveKeyFromPassword(_ password: Data) throws -> Data {
        return _derivedKey!
    }

    public func generateNonce() throws -> Data {
        return Data()
    }

    public func encrypt(_ data: Data, withKey key: Data) throws -> Data {
        _lastDataToEncrypt = data
        _lastKey = key
        return data
    }

    public func decrypt(_ data: Data, withKey key: Data) throws -> Data {
        _lastDataToDecrypt = data
        _lastKey = key

        guard let data = _decryptedData else {
            throw SecureStorageError.invalidPassword
        }

        return data
    }

    public func generateSalt() throws -> Data {
        return Data()
    }

    public func hashData(_ data: Data) throws -> String? {
        return ""
    }

    public func hashData(_ data: Data, salt: Data?) throws -> String? {
        return ""
    }

}
