//
//  UserScriptEncrypterTests.swift
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
import XCTest
import CryptoKit
@testable import UserScript

class UserScriptEncrypterTests: XCTestCase {

    func testWhenMessageIsEncrypted_ThenCanBeDecryptedUsingAuthenticationData() throws {
        let key: [UInt8] = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
        let iv: [UInt8] = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }

        let encrypter = AESGCMUserScriptEncrypter()
        let encrypted = try encrypter.encryptReply("test", key: key, iv: iv)

        XCTAssertEqual(encrypted.ciphertext.count, "test".data(using: .utf8)?.count)

        let nonce = try AES.GCM.Nonce(data: iv)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: encrypted.ciphertext, tag: encrypted.tag)

        let symmetricKey = SymmetricKey(data: key)

        let result = try AES.GCM.open(box, using: symmetricKey)
        XCTAssertEqual("test", String(data: result, encoding: .utf8))
    }

}
