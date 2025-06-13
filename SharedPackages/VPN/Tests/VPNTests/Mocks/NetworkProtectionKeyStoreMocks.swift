//
//  NetworkProtectionKeyStoreMocks.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
@testable import VPN

final class NetworkProtectionKeyStoreMock: NetworkProtectionKeyStore {

    var keyPair: KeyPair?
    var validityInterval: TimeInterval?

    // MARK: - NetworkProtectionKeyStore

    var currentExpirationDate: Date? {
        Date()
    }

    func currentKeyPair() -> VPN.KeyPair? {
        keyPair
    }

    func newKeyPair() -> VPN.KeyPair {
        return KeyPair(privateKey: PrivateKey(), expirationDate: Date().addingTimeInterval(.day))
    }

    public func updateKeyPair(_ newKeyPair: KeyPair) {
        self.keyPair = newKeyPair
    }

    func updateKeyPairExpirationDate(_ newExpirationDate: Date) -> VPN.KeyPair {
        let keyPair = KeyPair(privateKey: keyPair?.privateKey ?? PrivateKey(), expirationDate: newExpirationDate)
        self.keyPair = keyPair
        return keyPair
    }

    func resetCurrentKeyPair() {
        self.keyPair = nil
    }

    func setValidityInterval(_ validityInterval: TimeInterval?) {
        self.validityInterval = validityInterval
    }

    // MARK: - Storage

    func storedPrivateKey() throws -> PrivateKey? {
        return keyPair?.privateKey
    }
}
