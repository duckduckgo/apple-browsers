//
//  AutofillUserScript+Email.swift
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

import WebKit
import UserScript

public protocol AutofillEmailDelegate: AnyObject {

    func autofillUserScript(_: AutofillUserScript,
                            didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                            shouldConsumeAliasIfProvided: Bool,
                            completionHandler: @escaping AliasAutosaveCompletion)
    func autofillUserScriptDidRequestRefreshAlias(_: AutofillUserScript)
    func autofillUserScript(_: AutofillUserScript, didRequestStoreToken token: String, username: String, cohort: String?)
    func autofillUserScriptDidRequestUsernameAndAlias(_: AutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion)
    func autofillUserScriptDidRequestUserData(_: AutofillUserScript, completionHandler: @escaping UserDataCompletion)
    func autofillUserScriptDidRequestSignOut(_: AutofillUserScript)
    func autofillUserScriptDidRequestSignedInStatus(_: AutofillUserScript) -> Bool
    func autofillUserScript(_: AutofillUserScript, didRequestSetInContextPromptValue value: Double)
    func autofillUserScriptDidRequestInContextPromptValue(_: AutofillUserScript) -> Double?
    func autofillUserScriptDidRequestInContextSignup(_: AutofillUserScript, completionHandler: @escaping SignUpCompletion)
    func autofillUserScriptDidCompleteInContextSignup(_: AutofillUserScript)
}

extension AutofillUserScript {

    func emailCheckSignedInStatus(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        let signedIn = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self) ?? false
        let signedInString = String(signedIn)
        replyHandler("""
            { "isAppSignedIn": \(signedInString) }
        """)
    }

    func emailStoreToken(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let token = dict["token"] as? String,
              let username = dict["username"] as? String else { return }
        let cohort = dict["cohort"] as? String
        emailDelegate?.autofillUserScript(self, didRequestStoreToken: token, username: username, cohort: cohort)
        replyHandler(nil)
    }

    func emailRemoveToken(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestSignOut(self)
        replyHandler(nil)
    }

    func emailGetAlias(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let requiresUserPermission = dict["requiresUserPermission"] as? Bool,
              let shouldConsumeAliasIfProvided = dict["shouldConsumeAliasIfProvided"] as? Bool,
              let isIncontextSignupAvailable = dict["isIncontextSignupAvailable"] as? Bool else { return }

        guard isIncontextSignupAvailable, let signedIn = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self), !signedIn else {
            requestAlias(message,
                         requiresUserPermission: requiresUserPermission,
                         shouldConsumeAliasIfProvided: shouldConsumeAliasIfProvided) { reply in
                replyHandler(reply)
            }
            return
        }

        emailDelegate?.autofillUserScriptDidRequestInContextSignup(self) { [weak self] success, _ in
            if success {
                self?.requestAlias(message, requiresUserPermission: requiresUserPermission,
                                   shouldConsumeAliasIfProvided: shouldConsumeAliasIfProvided) { reply in
                    replyHandler(reply)
                }
            } else {
                replyHandler(nil)
            }
        }
    }

    private func requestAlias(_ message: UserScriptMessage,
                              requiresUserPermission: Bool,
                              shouldConsumeAliasIfProvided: Bool,
                              _ replyHandler: @escaping MessageReplyHandler) {
        emailDelegate?.autofillUserScript(self,
                                          didRequestAliasAndRequiresUserPermission: requiresUserPermission,
                                          shouldConsumeAliasIfProvided: shouldConsumeAliasIfProvided) { alias, autosave, _  in
            guard let alias = alias else { return }
            let domain = self.hostProvider.hostForMessage(message)

            //  Fetch the data in order to validate whether the alias is the personal email address or not
            self.emailDelegate?.autofillUserScriptDidRequestUserData(self) { username, _, _, _ in
                if let username = username {
                    let autogenerated = alias != username && autosave // Only consider private emails as autogenerated
                    let credentials = AutofillUserScript.IncomingCredentials(username: "\(alias)@\(EmailManager.emailDomain)",
                                                                             password: nil,
                                                                             autogenerated: autogenerated)
                    let data = DetectedAutofillData(identity: nil, credentials: credentials, creditCard: nil, trigger: .emailProtection)
                    self.vaultDelegate?.autofillUserScript(self, didRequestStoreDataForDomain: domain, data: data)

                    replyHandler("""
                    {
                        "alias": "\(alias)"
                    }
                    """)
                }
            }
        }
    }

    func emailRefreshAlias(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestRefreshAlias(self)
        replyHandler(nil)
    }

    func emailGetAddresses(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestUsernameAndAlias(self) { username, alias, _ in
            let addresses: String
            if let username = username, let alias = alias {
                addresses = """
                {
                    "personalAddress": "\(username)",
                    "privateAddress": "\(alias)"
                }
                """
            } else {
                addresses = "null"
            }

            replyHandler("""
            {
                "addresses": \(addresses)
            }
            """)
        }
    }

    private struct UserData: Encodable {
        public let userName: String
        public let nextAlias: String
        public let token: String
    }

    func emailGetUserData(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestUserData(self) { username, alias, token, _ in
            if let username = username, let alias = alias, let token = token {

                let userData = UserData(userName: username, nextAlias: alias, token: token)
                if let json = try? JSONEncoder().encode(userData), let jsonString = String(data: json, encoding: .utf8) {
                    replyHandler(jsonString)
                } else {
                    replyHandler(nil)
                }

            } else {
                replyHandler(nil)
            }
        }
    }

    private struct DeviceEmailCapabilities: Encodable {
        public let addUserData: Bool
        public let getUserData: Bool
        public let removeUserData: Bool
    }

    func emailGetDeviceCapabilities(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        let capabilities = DeviceEmailCapabilities(addUserData: true, getUserData: true, removeUserData: true)
        if let json = try? JSONEncoder().encode(capabilities), let jsonString = String(data: json, encoding: .utf8) {
            replyHandler(jsonString)
        } else {
            replyHandler(nil)
        }
    }

    // MARK: In Context Email Protection

    func setIncontextSignupPermanentlyDismissedAt(_ message: UserScriptMessage, replyHandler: @escaping MessageReplyHandler) {
        guard let body = message.messageBody as? [String: Any],
              let value = body["value"] as? Double else {
            return
        }
        emailDelegate?.autofillUserScript(self, didRequestSetInContextPromptValue: value)
        replyHandler(nil)
    }

    func getIncontextSignupDismissedAt(_ message: UserScriptMessage, replyHandler: @escaping MessageReplyHandler) {
        let inContextEmailSignupPromptDismissedPermanentlyAt: Double? = emailDelegate?.autofillUserScriptDidRequestInContextPromptValue(self)
        let inContextSignupDismissedAt = IncontextSignupDismissedAt(
            permanentlyDismissedAt: inContextEmailSignupPromptDismissedPermanentlyAt
        )
        let response = GetIncontextSignupDismissedAtResponse(success: inContextSignupDismissedAt)

        if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
            replyHandler(jsonString)
        }
    }

    func startEmailProtectionSignup(_ message: UserScriptMessage, replyHandler: @escaping MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestInContextSignup(self) { _, _  in }
        replyHandler(nil)
    }

    func closeEmailProtectionTab(_ message: UserScriptMessage, replyHandler: @escaping MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidCompleteInContextSignup(self)
        replyHandler(nil)
    }

}
