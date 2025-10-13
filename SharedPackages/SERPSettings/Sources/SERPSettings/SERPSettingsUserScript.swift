//
//  SERPSettingsUserScript.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import UserScript
import Foundation
import WebKit

// MARK: - UserScript Messages

public enum SERPSettingsUserScriptMessages: String, CaseIterable {

    /// Message that originates from the SERP to navigate to certain settings (Privachy Search, AI Features, etc)
    case openNativeSettings

    /// Message that originates from the SERP when some of his settings are changed
    case updateNativeSettings

    /// Message that originates from the SERP when it gets visited to know the state of SERP settings but Duck.ai
    case getNativeSettings

    /// Message that originates from the native side when the Duck.ai settings is turned on or off
    case nativeDuckAiSettingChanged

    /// Message that originates from the SERP when it gets visited to know the state of Duck.ai
    case isNativeDuckAiEnabled
}

public final class SERPSettingsUserScript: NSObject, Subfeature {

    // MARK: - Properties

    public weak var broker: UserScriptMessageBroker?
    public weak var delegate: SERPSettingsUserScriptDelegate?
    weak var webView: WKWebView?

    public var messageOriginPolicy: MessageOriginPolicy

    public let featureName: String = "serpSettings"

    private let serpSettingsProviding: SERPSettingsProviding

    private let testing = true

    public init(serpSettingsProviding: SERPSettingsProviding) {
        self.serpSettingsProviding = serpSettingsProviding
        self.messageOriginPolicy = .only(rules: serpSettingsProviding.buildMessageOriginRules())
    }

    // MARK: - Subfeature

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let message = SERPSettingsUserScriptMessages(rawValue: methodName) else {
            return nil
        }

        switch message {
        case .openNativeSettings:
            return openNativeSettings
        case .updateNativeSettings:
            return updateNativeSettings
        case .getNativeSettings:
            return getNativeSettings
        case .isNativeDuckAiEnabled:
            return isNativeDuckAiEnabled
        case .nativeDuckAiSettingChanged: // Never called by SERP - returning nil.
            return nil
        }
    }

    // MARK: - SERP to Native communication

    @MainActor
    private func getNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        /// The communication between SERP and Native will be behind a feature flag
        guard serpSettingsProviding.isSERPSettingsFeatureOn() else {
            return nil
        }

        if testing {
            /// Fake settings to test
            let settings: [String: Any] = [
                "theme": "dark",
                "notificationsEnabled": true,
                "volume": 0.8,
                "favorites": ["A", "B", "C"],
                "lastLogin": 1_697_000_000
            ]

            serpSettingsProviding.storeSERPSettings(settings: settings)
        }

        if let blob = serpSettingsProviding.getSERPSettings() as? JSONBlob {
            let jsonString = String(data: blob.data, encoding: .utf8)
            print(jsonString)
        }

        return serpSettingsProviding.getSERPSettings()
    }

    @MainActor
    private func updateNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        /// The communication between SERP and Native will be behind a feature flag
        guard serpSettingsProviding.isSERPSettingsFeatureOn() else {
            return nil
        }

        guard let settings = params as? [String: Any] else { return nil }

        serpSettingsProviding.storeSERPSettings(settings: settings)

        return nil
    }

    @MainActor
    private func openNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let parameters = params as? [String: String] else { return nil }

        if parameters[SERPSettingsConstants.returnParameterKey] == SERPSettingsConstants.privateSearch {
            delegate?.serpSettingsUserScriptDidRequestToCloseTabAndOpenPrivacySettings(self)
        } else if parameters[SERPSettingsConstants.returnParameterKey] == SERPSettingsConstants.aiFeatures {
            delegate?.serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(self)
        } else if parameters[SERPSettingsConstants.screenParameterKey] == SERPSettingsConstants.aiFeatures {
            delegate?.serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(self)
        }
        return nil
    }

    @MainActor
    private func isNativeDuckAiEnabled(params: Any, message: UserScriptMessage) -> Encodable? {
        return serpSettingsProviding.isAIChatEnabled
    }

    // MARK: - Native to SERP communication

    private func nativeDuckAiSettingChanged() {
        guard let webView else {
            return
        }

        broker?.push(method: SERPSettingsUserScriptMessages.nativeDuckAiSettingChanged.rawValue,
                     params: serpSettingsProviding.isAIChatEnabled,
                     for: self,
                     into: webView)
    }
}
