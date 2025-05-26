//
//  UserScriptEncrypter.swift
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
import CryptoKit

public protocol UserScriptEncrypter {

    func encryptReply(_ reply: String, key: [UInt8], iv: [UInt8]) throws -> (ciphertext: Data, tag: Data)

}

public struct AESGCMUserScriptEncrypter: UserScriptEncrypter {

    public enum Error: Swift.Error {
        case encodingReply
    }

    public init() {}

    public func encryptReply(_ reply: String, key: [UInt8], iv: [UInt8]) throws -> (ciphertext: Data, tag: Data) {
        guard let replyData = reply.data(using: .utf8) else {
            throw Error.encodingReply
        }
        let sealed = try AES.GCM.seal(replyData, using: .init(data: key), nonce: .init(data: iv))
        return (ciphertext: sealed.ciphertext, tag: sealed.tag)
    }

}
