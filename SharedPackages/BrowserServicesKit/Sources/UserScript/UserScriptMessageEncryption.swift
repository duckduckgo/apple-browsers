//
//  UserScriptMessageEncryption.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import WebKit

public protocol UserScriptMessageEncryption {

    typealias MessageReplyHandler = (String?) -> Void
    typealias MessageHandler = (UserScriptMessage, @escaping MessageReplyHandler) -> Void

    var encrypter: UserScriptEncrypter { get }
    var generatedSecret: String { get }

    func messageHandlerFor(_ messageName: String) -> MessageHandler?
    func processEncryptedMessage(_ message: UserScriptMessage, from userContentController: WKUserContentController)
}

extension UserScriptMessageEncryption {

    public func processEncryptedMessage(_ message: UserScriptMessage, from userContentController: WKUserContentController) {

        guard let messageHandler = messageHandlerFor(message.messageName) else {
            // Unsupported message fail silently
            return
        }

        guard let body = message.messageBody as? [String: Any],
              let messageHandling = body["messageHandling"] as? [String: Any],
              let secret = messageHandling["secret"] as? String,
              // If this does not match the page is playing shenanigans.
              secret == generatedSecret
        else { return }

        messageHandler(message) { reply in
            guard let reply = reply,
                  let messageHandling = body["messageHandling"] as? [String: Any],
                  let key = messageHandling["key"] as? [UInt8],
                  let iv = messageHandling["iv"] as? [UInt8],
                  let methodName = messageHandling["methodName"] as? String,
                  let encryption = try? self.encrypter.encryptReply(reply, key: key, iv: iv) else { return }

            let ciphertext = encryption.ciphertext.withUnsafeBytes { bytes in
                return bytes.map { String($0) }
            }.joined(separator: ",")

            let tag = encryption.tag.withUnsafeBytes { bytes in
                return bytes.map { String($0) }
            }.joined(separator: ",")

            let script = """
            (() => {
                window.\(methodName) && window.\(methodName)({
                    ciphertext: [\(ciphertext)],
                    tag: [\(tag)]
                });
            })();
            """

            assert(message.messageWebView != nil)
            dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
            message.messageWebView?.evaluateJavaScript(script)
        }
    }
}
