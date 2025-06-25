//
//  AutofillUserScript.swift
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

import Common
import os.log
import UserScript
@preconcurrency import WebKit

var previousIncontextSignupPermanentlyDismissedAt: Double?
var previousEmailSignedIn: Bool?

public class AutofillUserScript: NSObject, UserScript, UserScriptMessageEncryption {
    internal enum MessageName: String, CaseIterable {
        case emailHandlerStoreToken
        case emailHandlerRemoveToken
        case emailHandlerGetAlias
        case emailHandlerGetUserData
        case emailHandlerGetCapabilities
        case emailHandlerRefreshAlias

        case emailHandlerGetAddresses
        case emailHandlerCheckAppSignedInStatus

        case pmHandlerGetAutofillInitData

        case pmHandlerGetAccounts
        case pmHandlerGetAutofillCredentials
        case pmHandlerGetIdentity
        case pmHandlerGetCreditCard

        case pmHandlerOpenManageCreditCards
        case pmHandlerOpenManageIdentities
        case pmHandlerOpenManagePasswords

        case getRuntimeConfiguration
        case getAvailableInputTypes
        case getAutofillData
        case getAutofillDataFocus
        case storeFormData

        case askToUnlockProvider
        case checkCredentialsProviderStatus

        case sendJSPixel

        case setIncontextSignupPermanentlyDismissedAt
        case getIncontextSignupDismissedAt
        case startEmailProtectionSignup
        case closeEmailProtectionTab

        case startCredentialsImportFlow
        case credentialsImportFlowPermanentlyDismissed
    }

    /// Represents if the autofill is loaded into the top autofill context.
    public var isTopAutofillContext: Bool
    /// Serialized JSON string of any format to be passed from child to parent autofill.
    ///  once the user selects a field to open, we store field type and other contextual information to be initialized into the top autofill.
    public var serializedInputContext: String?

    /// Represents whether the webView is part of a burner window
    public var isBurnerWindow: Bool = false

    public var sessionKey: String?
    public var messageSecret: String?

    public weak var emailDelegate: AutofillEmailDelegate?
    public weak var vaultDelegate: AutofillSecureVaultDelegate?
    public weak var passwordImportDelegate: AutofillPasswordImportDelegate?

    internal var scriptSourceProvider: AutofillUserScriptSourceProvider

    internal lazy var autofillDomainNameUrlMatcher: AutofillDomainNameUrlMatcher = {
        return AutofillDomainNameUrlMatcher()
    }()

    public lazy var source: String = {
        var js = scriptSourceProvider.source
        js = js.replacingOccurrences(of: "PLACEHOLDER_SECRET", with: generatedSecret)
        js = js.replacingOccurrences(of: "// INJECT webkitMessageHandlerNames HERE", with: "webkitMessageHandlerNames = \(messageNamesJson);")
        js = js.replacingOccurrences(of: "// INJECT isTopFrame HERE", with: "isTopFrame = \(isTopAutofillContext ? "true" : "false");")
        return js
    }()

    public var injectionTime: WKUserScriptInjectionTime { .atDocumentStart }
    public var forMainFrameOnly: Bool {
        if isTopAutofillContext { return true }
        if #available(iOS 14, macOS 11, *) {
            return false
        }
        // We can't do reply based messaging to frames on versions before the ones mentioned above, so main frame only
        return true
    }

    // Temporary only for Pixel purposes. Do not rely on this for any functional logic
    static var domainOfMostRecentGetAvailableInputsMessage: String?

    public var messageNames: [String] {
        return MessageName.allCases.map(\.rawValue)
    }

    // communicate known message handler names to user scripts.
    public lazy var messageNamesJson: String = {
        // note: this doesn't include the messages from the overlay - only messages that can potentially be execute on macOS 10.x need
        // to be communicated to the JavaScript layer.
        let combinedMessages = MessageName.allCases.map(\.rawValue) + WebsiteAutofillUserScript.WebsiteAutofillMessageName.allCases.map(\.rawValue)
        guard let json = try? JSONEncoder().encode(combinedMessages), let jsonString = String(data: json, encoding: .utf8) else {
            assertionFailure("AutofillUserScript: could not encode message names into JSON")
            return ""
        }
        return jsonString
    }()

    public func messageHandlerFor(_ messageName: String) -> MessageHandler? {
        guard let message = MessageName(rawValue: messageName) else {
            Logger.autofill.error("Failed to parse Autofill User Script message: '\(messageName, privacy: .public)'")
            return nil
        }
        Logger.autofill.debug("AutofillUserScript: received '\(messageName, privacy: .public)'")

        switch message {
        case .emailHandlerStoreToken: return emailStoreToken
        case .emailHandlerRemoveToken: return emailRemoveToken
        case .emailHandlerGetAlias: return emailGetAlias
        case .emailHandlerGetUserData: return emailGetUserData
        case .emailHandlerGetCapabilities: return emailGetDeviceCapabilities
        case .emailHandlerRefreshAlias: return emailRefreshAlias
        case .emailHandlerGetAddresses: return emailGetAddresses
        case .emailHandlerCheckAppSignedInStatus: return emailCheckSignedInStatus

        case .pmHandlerGetAutofillInitData: return pmGetAutoFillInitData

        case .getRuntimeConfiguration: return getRuntimeConfiguration
        case .getAvailableInputTypes: return getAvailableInputTypes
        case .getAutofillData: return getAutofillData
        case .getAutofillDataFocus: return getAutofillDataFocus
        case .storeFormData: return pmStoreData

        case .pmHandlerGetAccounts: return pmGetAccounts
        case .pmHandlerGetAutofillCredentials: return pmGetAutofillCredentials
        case .pmHandlerGetIdentity: return pmGetIdentity
        case .pmHandlerGetCreditCard: return pmGetCreditCard

        case .pmHandlerOpenManageCreditCards: return pmOpenManageCreditCards
        case .pmHandlerOpenManageIdentities: return pmOpenManageIdentities
        case .pmHandlerOpenManagePasswords: return pmOpenManagePasswords

        case .askToUnlockProvider: return askToUnlockProvider
        case .checkCredentialsProviderStatus: return checkCredentialsProviderStatus

        case .sendJSPixel: return sendJSPixel

        case .setIncontextSignupPermanentlyDismissedAt: return setIncontextSignupPermanentlyDismissedAt
        case .getIncontextSignupDismissedAt: return getIncontextSignupDismissedAt
        case .startEmailProtectionSignup: return startEmailProtectionSignup
        case .closeEmailProtectionTab: return closeEmailProtectionTab
        case .startCredentialsImportFlow: return startCredentialsImportFlow
        case .credentialsImportFlowPermanentlyDismissed: return credentialsImportFlowPermanentlyDismissed
        }
    }

    public let encrypter: UserScriptEncrypter
    public let generatedSecret: String = UUID().uuidString
    let replyQueue = PendingRepliesActor()

    let hostProvider: UserScriptHostProvider
    func hostForMessage(_ message: UserScriptMessage) -> String {
        return hostProvider.hostForMessage(message)
    }

    public convenience init(scriptSourceProvider: AutofillUserScriptSourceProvider) {
        self.init(scriptSourceProvider: scriptSourceProvider,
                  encrypter: AESGCMUserScriptEncrypter(),
                  hostProvider: SecurityOriginHostProvider())
    }

    init(scriptSourceProvider: AutofillUserScriptSourceProvider,
         encrypter: UserScriptEncrypter = AESGCMUserScriptEncrypter(),
         hostProvider: UserScriptHostProvider = SecurityOriginHostProvider()) {
        self.scriptSourceProvider = scriptSourceProvider
        self.hostProvider = hostProvider
        self.encrypter = encrypter
        self.isTopAutofillContext = false
    }
}

struct GetSelectedCredentialsResponse: Encodable {
    /// Represents the mode the JS should take, valid values are 'none', 'stop', 'ok'
    var type: String
    /// Key value data passed from the JS to be retuned to the child
    var data: [String: String]?
    var configType: String?
}

/// Represents data after the user clicks to be sent back into the JS child context
struct SelectedDetailsData {
    var data: [String: String]?
    var configType: String?
}

@available(iOS 14, *)
@available(macOS 11, *)
extension AutofillUserScript: WKScriptMessageHandlerWithReply {

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage,
                                      replyHandler: @escaping (Any?, String?) -> Void) {
        guard let messageHandler = messageHandlerFor(message.name) else {
            assertionFailure("Unsupported message")
            return
        }

        messageHandler(message) {
            replyHandler($0, nil)
        }

    }

}

// Fallback for older iOS / macOS version
extension AutofillUserScript: WKScriptMessageHandler {

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        processEncryptedMessage(message, from: userContentController)
    }

}
