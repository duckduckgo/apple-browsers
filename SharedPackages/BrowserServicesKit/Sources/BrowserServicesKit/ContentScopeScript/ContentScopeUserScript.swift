//
//  ContentScopeUserScript.swift
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

import Combine
import Common
import ContentScopeScripts
import Foundation
import PrivacyConfig
import UserScript
import WebKit

public protocol ContentScopeUserScriptDelegate: AnyObject {
    func contentScopeUserScript(_ script: ContentScopeUserScript, didReceiveDebugFlag debugFlag: String)
}

public protocol UserScriptWithContentScope: UserScript {
    var delegate: ContentScopeUserScriptDelegate? { get set }
}

public struct ContentScopeExperimentData: Encodable, Equatable {
    public let feature: String
    public let subfeature: String
    public let cohort: String

    public init(feature: String, subfeature: String, cohort: String) {
        self.feature = feature
        self.subfeature = subfeature
        self.cohort = cohort
    }
}

public enum ContentScopeScriptContext {
    case contentScope
    case contentScopeIsolated
    case aiChatDataClearing

    public var isIsolated: Bool {
        switch self {
        case .contentScope, .aiChatDataClearing:
            return false
        case .contentScopeIsolated:
            return true
        }
    }

    var fileName: String {
        switch self {
        case .contentScope:
            return "contentScope"
        case .contentScopeIsolated:
            return "contentScopeIsolated"
        case .aiChatDataClearing:
            return "duckAiDataClearing"
        }
    }

    var messagingContextName: String {
        switch self {
        case .contentScope:
            return "contentScopeScripts"
        case .aiChatDataClearing:
            return "duckAiDataClearing"
        case .contentScopeIsolated:
            return "contentScopeScriptsIsolated"
        }
    }
}

public final class ContentScopeProperties: Encodable {
    public let globalPrivacyControlValue: Bool
    public let debug: Bool
    public let sessionKey: String
    public let messageSecret: String
    public let languageCode: String
    public let platform: ContentScopePlatform
    public let features: [String: ContentScopeFeature]
    public var currentCohorts: [ContentScopeExperimentData]

    public init(gpcEnabled: Bool,
                sessionKey: String,
                messageSecret: String,
                isInternalUser: Bool = false,
                debug: Bool = false,
                featureToggles: ContentScopeFeatureToggles,
                currentCohorts: [ContentScopeExperimentData] = []) {
        self.globalPrivacyControlValue = gpcEnabled
        self.debug = debug
        self.sessionKey = sessionKey
        self.messageSecret = messageSecret
        self.platform = ContentScopePlatform(isInternal: isInternalUser, version: AppVersion.shared.versionNumber)
        languageCode = Locale.current.languageCode ?? "en"
        features = [
            "autofill": ContentScopeFeature(featureToggles: featureToggles)
        ]
        self.currentCohorts = currentCohorts
    }

    enum CodingKeys: String, CodingKey {
        // Rename 'languageCode' to 'language' to conform to autofill.js's interface.
        case languageCode = "language"

        case globalPrivacyControlValue
        case debug
        case sessionKey
        case messageSecret
        case platform
        case features
        case currentCohorts

    }

}

public struct ContentScopeFeature: Encodable {

    public let settings: [String: ContentScopeFeatureToggles]

    public init(featureToggles: ContentScopeFeatureToggles) {
        self.settings = ["featureToggles": featureToggles]
    }
}

public struct ContentScopeFeatureToggles: Encodable {

    public let emailProtection: Bool
    public let emailProtectionIncontextSignup: Bool

    public let credentialsAutofill: Bool
    public let identitiesAutofill: Bool
    public let creditCardsAutofill: Bool

    public let credentialsSaving: Bool

    public var passwordGeneration: Bool

    public let inlineIconCredentials: Bool
    public let thirdPartyCredentialsProvider: Bool

    public let unknownUsernameCategorization: Bool

    public let partialFormSaves: Bool

    public let passwordVariantCategorization: Bool

    public let inputFocusApi: Bool

    public let autocompleteAttributeSupport: Bool

    // Explicitly defined memberwise init only so it can be public
    public init(emailProtection: Bool,
                emailProtectionIncontextSignup: Bool,
                credentialsAutofill: Bool,
                identitiesAutofill: Bool,
                creditCardsAutofill: Bool,
                credentialsSaving: Bool,
                passwordGeneration: Bool,
                inlineIconCredentials: Bool,
                thirdPartyCredentialsProvider: Bool,
                unknownUsernameCategorization: Bool,
                partialFormSaves: Bool,
                passwordVariantCategorization: Bool,
                inputFocusApi: Bool,
                autocompleteAttributeSupport: Bool) {

        self.emailProtection = emailProtection
        self.emailProtectionIncontextSignup = emailProtectionIncontextSignup
        self.credentialsAutofill = credentialsAutofill
        self.identitiesAutofill = identitiesAutofill
        self.creditCardsAutofill = creditCardsAutofill
        self.credentialsSaving = credentialsSaving
        self.passwordGeneration = passwordGeneration
        self.inlineIconCredentials = inlineIconCredentials
        self.thirdPartyCredentialsProvider = thirdPartyCredentialsProvider
        self.unknownUsernameCategorization = unknownUsernameCategorization
        self.partialFormSaves = partialFormSaves
        self.passwordVariantCategorization = passwordVariantCategorization
        self.inputFocusApi = inputFocusApi
        self.autocompleteAttributeSupport = autocompleteAttributeSupport
    }

    enum CodingKeys: String, CodingKey {
        case emailProtection = "emailProtection"
        case emailProtectionIncontextSignup = "emailProtection_incontext_signup"

        case credentialsAutofill = "inputType_credentials"
        case identitiesAutofill = "inputType_identities"
        case creditCardsAutofill = "inputType_creditCards"

        case credentialsSaving = "credentials_saving"

        case passwordGeneration = "password_generation"

        case inlineIconCredentials = "inlineIcon_credentials"
        case thirdPartyCredentialsProvider = "third_party_credentials_provider"
        case unknownUsernameCategorization = "unknown_username_categorization"
        case partialFormSaves = "partial_form_saves"
        case passwordVariantCategorization = "password_variant_categorization"
        case inputFocusApi = "input_focus_api"
        case autocompleteAttributeSupport = "autocomplete_attribute_support"
    }
}

public struct ContentScopePlatform: Encodable {
    #if os(macOS)
    let name = "macos"
    #elseif os(iOS)
    let name = "ios"
    #else
    let name = "unknown"
    #endif

    let `internal`: Bool
    let version: String

    init(isInternal: Bool = false, version: String = "") {
        self.internal = isInternal
        self.version = version
    }
}

public final class ContentScopeUserScript: NSObject, UserScript, UserScriptMessaging, UserScriptWithContentScope {

    public var broker: UserScriptMessageBroker
    public let scriptContext: ContentScopeScriptContext
    public let allowedNonisolatedFeatures: [String]
    public var messageNames: [String] = []
    public weak var delegate: ContentScopeUserScriptDelegate?

    public init(_ privacyConfigManager: PrivacyConfigurationManaging,
                properties: ContentScopeProperties,
                scriptContext: ContentScopeScriptContext = .contentScope,
                allowedNonisolatedFeatures: [String] = [],
                privacyConfigurationJSONGenerator: CustomisedPrivacyConfigurationJSONGenerating?,
                surrogatesText: String? = nil
    ) throws {
        self.scriptContext = scriptContext
        self.allowedNonisolatedFeatures = allowedNonisolatedFeatures

        broker = UserScriptMessageBroker(context: scriptContext.messagingContextName, requiresRunInPageContentWorld: !scriptContext.isIsolated)

        messageNames = [scriptContext.messagingContextName]

        source = try ContentScopeUserScript.generateSource(
            privacyConfigManager,
            properties: properties,
            scriptContext: scriptContext,
            config: broker.messagingConfig(),
            privacyConfigurationJSONGenerator: privacyConfigurationJSONGenerator,
            surrogatesText: surrogatesText
        )
    }

    public static func generateSource(_ privacyConfigurationManager: PrivacyConfigurationManaging,
                                      properties: ContentScopeProperties,
                                      scriptContext: ContentScopeScriptContext,
                                      config: WebkitMessagingConfig,
                                      privacyConfigurationJSONGenerator: CustomisedPrivacyConfigurationJSONGenerating?,
                                      surrogatesText: String? = nil
    ) throws -> String {
        let privacyConfigJsonData = privacyConfigurationJSONGenerator?.privacyConfiguration ?? privacyConfigurationManager.currentConfig
        guard let privacyConfigJson = String(data: privacyConfigJsonData, encoding: .utf8),
              let userUnprotectedDomains = try? JSONEncoder().encode(privacyConfigurationManager.privacyConfig.userUnprotectedDomains),
              let userUnprotectedDomainsString = String(data: userUnprotectedDomains, encoding: .utf8),
              let jsonPropertiesString = try? encodeProperties(properties, messagingContextName: scriptContext.messagingContextName),
              let jsonConfig = try? JSONEncoder().encode(config),
              let jsonConfigString = String(data: jsonConfig, encoding: .utf8)
        else {
            return ""
        }

        // Convert surrogates.txt to JS object literal with function values
        let surrogatesJS = surrogatesText.map { createSurrogateFunctions($0) } ?? "{}"

        return try loadJS(scriptContext.fileName, from: ContentScopeScripts.Bundle, withReplacements: [
            "$CONTENT_SCOPE$": privacyConfigJson,
            "$USER_UNPROTECTED_DOMAINS$": userUnprotectedDomainsString,
            "$USER_PREFERENCES$": jsonPropertiesString,
            "$WEBKIT_MESSAGING_CONFIG$": jsonConfigString,
            "$SURROGATES$": surrogatesJS
        ])
    }

    /// Converts raw surrogates.txt format into a JavaScript object literal with function values.
    ///
    /// Input format (surrogates.txt):
    /// ```
    /// googlesyndication.com/adsbygoogle.js application/javascript
    /// (() => { window.adsbygoogle = { loaded: true }; })();
    /// ```
    ///
    /// Output format (JS object literal):
    /// ```javascript
    /// { 'adsbygoogle.js': function() { ... } }
    /// ```
    private static func createSurrogateFunctions(_ surrogates: String) -> String {
        // Remove comment lines
        let commentlessSurrogates = surrogates
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { !$0.starts(with: "#") }
            .joined(separator: "\n")

        // Split into individual surrogate blocks (separated by blank lines)
        let surrogateScripts = commentlessSurrogates.components(separatedBy: "\n\n")

        // Convert each block into a function definition
        var functions: [String] = []
        for surrogate in surrogateScripts {
            var codeLines = surrogate.split(separator: "\n", omittingEmptySubsequences: false)
            if codeLines.isEmpty { continue }

            // First line contains path and content-type: "domain.com/script.js application/javascript"
            let instructionsRow = codeLines.removeFirst()
            guard let path = instructionsRow.split(separator: " ").first,
                  let pattern = path.split(separator: "/").last else {
                continue
            }

            // Remaining lines are the function body
            let functionBody = codeLines.joined(separator: "\n")
            if functionBody.isEmpty { continue }

            // Escape the pattern for use as object key and wrap code in function
            let escapedPattern = pattern.replacingOccurrences(of: "'", with: "\\'")
            functions.append("'\(escapedPattern)': function() { \(functionBody) }")
        }

        // Return as a JavaScript object literal
        return "{ \(functions.joined(separator: ", ")) }"
    }

    private static func encodeProperties(_ properties: ContentScopeProperties, messagingContextName: String) throws -> String {
        let jsonProperties = try JSONEncoder().encode(properties)
        var dict = try JSONSerialization.jsonObject(with: jsonProperties, options: []) as? [String: Any] ?? [:]
        dict["messagingContextName"] = messagingContextName

        let encoded = try JSONSerialization.data(withJSONObject: dict, options: [])
        guard let result = String(data: encoded, encoding: .utf8) else {
            throw EncodingError.invalidValue(properties, EncodingError.Context(codingPath: [], debugDescription: "Failed to convert ContentScopeProperties to dictionary" ))
        }
        return result
    }

    public let source: String
    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly: Bool = false
    public var requiresRunInPageContentWorld: Bool { !self.scriptContext.isIsolated }
}

@available(macOS 11.0, iOS 14.0, *)
extension ContentScopeUserScript: WKScriptMessageHandlerWithReply {
    @MainActor
    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) async -> (Any?, String?) {
        propagateDebugFlag(message)

        // Don't propagate the message for ContentScopeScript non isolated context
        if !scriptContext.isIsolated && !isAllowedNonisolatedFeature(message) {
            return (nil, nil)
        }
        // Propagate the message for ContentScopeScriptIsolated and other context like "dbpui"
        let action = broker.messageHandlerFor(message)
        do {
            let json = try await broker.execute(action: action, original: message)
            return (json, nil)
        } catch {
            // forward uncaught errors to the client
            return (nil, error.localizedDescription)
        }
    }

    private func isAllowedNonisolatedFeature(_ message: WKScriptMessage) -> Bool {
        guard !allowedNonisolatedFeatures.isEmpty else {
            return false
        }
        guard let featureName = (message.messageBody as? [String: Any])?["featureName"] as? String else {
            return false
        }
        return allowedNonisolatedFeatures.contains(featureName)
    }

    @MainActor
    private func propagateDebugFlag(_ message: WKScriptMessage) {
        if let messageDictionary = message.body as? [String: Any],
           let parameters = messageDictionary["params"] as? [String: String],
           let flag = parameters["flag"] {
            delegate?.contentScopeUserScript(self, didReceiveDebugFlag: flag)
        }
    }
}

// MARK: - Fallback for macOS 10.15
extension ContentScopeUserScript: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // unsupported
    }
}
