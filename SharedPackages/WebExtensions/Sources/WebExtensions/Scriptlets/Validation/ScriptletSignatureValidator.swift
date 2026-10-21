//
//  ScriptletSignatureValidator.swift
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

public final class ScriptletSignatureValidator: ScriptletValidating {

    private let publicKey: P256.Signing.PublicKey

    public init(publicKey: P256.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    public func validate(_ fetched: [FetchedScriptlet]) throws {
        for item in fetched {
            guard String(data: item.data, encoding: .utf8) != nil else {
                throw ScriptletError.invalidEncoding(name: item.descriptor.name)
            }

            guard let signatureData = Data(base64Encoded: item.descriptor.signature) else {
                throw ScriptletError.invalidSignatureFormat(name: item.descriptor.name)
            }

            guard let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
                  publicKey.isValidSignature(signature, for: item.data) else {
                throw ScriptletError.signatureVerificationFailed(name: item.descriptor.name)
            }
        }
    }
}
