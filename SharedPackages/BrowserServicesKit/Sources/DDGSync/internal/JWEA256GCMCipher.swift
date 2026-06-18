//
//  JWEA256GCMCipher.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import CryptoKit
import Foundation
import Security

enum JWEA256GCMCipherError: Error, Equatable {
    case randomBytesGenerationFailed(OSStatus)
    case aesGCMEncryptionFailed
    case aesGCMDecryptionFailed
}

enum JWEA256GCMCipher {

    static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw JWEA256GCMCipherError.randomBytesGenerationFailed(status)
        }
        return data
    }

    static func aesGCMEncrypt(plaintext: Data,
                              contentEncryptionKey: Data,
                              iv: Data,
                              additionalAuthenticatedData: Data) throws -> (ciphertext: Data, authenticationTag: Data) {
        do {
            let symmetricKey = SymmetricKey(data: contentEncryptionKey)
            let nonce = try AES.GCM.Nonce(data: iv)
            let sealedBox = try AES.GCM.seal(plaintext,
                                             using: symmetricKey,
                                             nonce: nonce,
                                             authenticating: additionalAuthenticatedData)
            return (sealedBox.ciphertext, sealedBox.tag)
        } catch {
            throw JWEA256GCMCipherError.aesGCMEncryptionFailed
        }
    }

    static func aesGCMDecrypt(ciphertext: Data,
                              authenticationTag: Data,
                              contentEncryptionKey: Data,
                              iv: Data,
                              additionalAuthenticatedData: Data) throws -> Data {
        do {
            let symmetricKey = SymmetricKey(data: contentEncryptionKey)
            let nonce = try AES.GCM.Nonce(data: iv)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: authenticationTag)
            return try AES.GCM.open(sealedBox, using: symmetricKey, authenticating: additionalAuthenticatedData)
        } catch {
            throw JWEA256GCMCipherError.aesGCMDecryptionFailed
        }
    }
}
