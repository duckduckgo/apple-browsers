//
//  ScopedAccessCredentialEnvelope.swift
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

import Foundation

final class ScopedAccessCredentialEnvelope {

    private let jweCompactCodec: JWECompactCodec

    init(jweCompactCodec: JWECompactCodec = JWECompactCodec()) {
        self.jweCompactCodec = jweCompactCodec
    }

    func encryptScopedPassword(_ scopedPassword: Data,
                               using mainKey: Data,
                               kid: String) throws -> String {
        let scopedPasswordBase64URL = Base64URL.encode(scopedPassword)
        return try jweCompactCodec.encryptDirect(payload: Data(scopedPasswordBase64URL.utf8),
                                                 contentEncryptionKey: mainKey,
                                                 kid: kid)
    }

    func decryptScopedPassword(from encryptedCredential: String,
                               using mainKey: Data) throws -> Data {
        do {
            let plaintextBytes = try jweCompactCodec.decryptDirect(token: encryptedCredential,
                                                                   contentEncryptionKey: mainKey)
            guard let plaintextString = String(data: plaintextBytes, encoding: .utf8),
                  let scopedPasswordBytes = Base64URL.decode(plaintextString) else {
                throw SyncError.invalidDataInResponse("3P access credential has invalid encrypted_3party_credential plaintext encoding")
            }
            return scopedPasswordBytes
        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.invalidDataInResponse("3P access credential has invalid encrypted_3party_credential format")
        }
    }
}
