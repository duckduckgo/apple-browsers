//
//  SERPSettingsUserScript.swift
//  DuckDuckGo
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

public enum SERPSettingsUserScriptMessages: String, CaseIterable {

    case openNativeSettings

}


// MARK: - Delegate Protocol

protocol SERPSettingsUserScriptDelegate: AnyObject {

    func serpSettingsUserScriptDidRequestToOpenPrivacySettings(_ userScript: SERPSettingsUserScript)
    func serpSettingsUserScriptDidRequestToOpenDuckAISettings(_ userScript: SERPSettingsUserScript)

}

enum SERPSettingsConstants {

    static let returnParameterKey = "return"
    static let privateSearch = "privateSearch"
    static let aiFeatures = "aiFeatures"

}

// MARK: - AIChatUserScript Class

final class SERPSettingsUserScript: NSObject, Subfeature {

    // MARK: - Properties

    weak var delegate: SERPSettingsUserScriptDelegate?
    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?

    private(set) var messageOriginPolicy: MessageOriginPolicy

    let featureName: String = "serpSettings"

    // MARK: - Initialization

    override init() {
        self.messageOriginPolicy = .only(rules: Self.buildMessageOriginRules())
        super.init()
    }

    private static func buildMessageOriginRules() -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []

        if let ddgDomain = URL.ddg.host {
            rules.append(.exact(hostname: ddgDomain))
        }

        return rules
    }

    // MARK: - Subfeature

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let message = SERPSettingsUserScriptMessages(rawValue: methodName) else {
            Logger.aiChat.debug("Unhandled message: \(methodName) in SERPSettingsUserScript")
            return nil
        }

        switch message {
        case .openNativeSettings:
            return openNativeSettings
        }
    }

    @MainActor
    private func openNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let parameters = params as? [String: String] else { return nil }
        if parameters[SERPSettingsConstants.returnParameterKey] == SERPSettingsConstants.privateSearch {
            delegate?.serpSettingsUserScriptDidRequestToOpenPrivacySettings(self)
        } else if parameters[SERPSettingsConstants.returnParameterKey] == SERPSettingsConstants.aiFeatures {
            delegate?.serpSettingsUserScriptDidRequestToOpenDuckAISettings(self)
        }
        return nil
    }

}
