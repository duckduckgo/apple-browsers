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
    case updateNativeSettings
    case getNativeSettings
    case nativeSettingsDidChange
}


// MARK: - Delegate Protocol

protocol SERPSettingsUserScriptDelegate: AnyObject {

    func serpSettingsUserScriptDidRequestToOpenPrivacySettings(_ userScript: SERPSettingsUserScript)
    func serpSettingsUserScript(_ userScript: SERPSettingsUserScript, didRequestToOpenAIFeaturesSettingsWithSearchAssistSettingsHidden searchAssistSettingsHidden: Bool)
}

public struct SERPUserSettings: Codable {
    public let duckAI: Bool
    public let allowFollowUpQuestion: Bool?
    
    public init(provider: SERPSettingsProviding) {
        #warning("if needs migration = true, send empty {}/nil/or flag -- to confirm")
        self.duckAI = provider.isDuckAIEnabled
        self.allowFollowUpQuestion = provider.isAllowFollowUpQuestionsEnabled
    }
    
    private enum CodingKeys: String, CodingKey {
        case duckAI = "duckai"
        case allowFollowUpQuestion = "kbg"
    }
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
    private let serpSettingsProvider: SERPSettingsProviding

    // MARK: - Initialization

    init(serpSettingsProvider: SERPSettingsProviding) {
        self.serpSettingsProvider = serpSettingsProvider
        self.messageOriginPolicy = .only(rules: Self.buildMessageOriginRules())
        super.init()
        
        NotificationCenter.default.addObserver(forName: .aiChatSettingsChanged,
                                               object: nil,
                                               queue: .main) { _ in
            self.nativeSettingsDidChange()
        }
    }

    private static func buildMessageOriginRules() -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []

        rules.append(.exact(hostname: "bhall.duck.co"))
        
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
        case .updateNativeSettings:
            return updateNativeSettings
        case .getNativeSettings:
            return getNativeSettings
        case .nativeSettingsDidChange:
            // This method is not called by SERP, return nil in this case.
            return nil
        }
    }
    
    // Step 1
    @MainActor
    func getNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        SERPUserSettings(provider: serpSettingsProvider)
    }

    @MainActor
    private func openNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let parameters = params as? [String: String] else { return nil }
        if parameters[SERPSettingsConstants.returnParameterKey] == SERPSettingsConstants.privateSearch {
            delegate?.serpSettingsUserScriptDidRequestToOpenPrivacySettings(self)
        } else if parameters[SERPSettingsConstants.returnParameterKey] == SERPSettingsConstants.aiFeatures {
            delegate?.serpSettingsUserScript(self, didRequestToOpenAIFeaturesSettingsWithSearchAssistSettingsHidden: false)
        }
#warning("todo, finish implementation")
        /*else if parameters[SERPSettingsConstants.returnParameterKey] == SERPSettingsConstants.aiFeatures {
            #warning("todo, handle Enable Duck.ai in AI Features Settings")
            delegate?.serpSettingsUserScript(self, didRequestToOpenAIFeaturesSettingsWithSearchAssistSettingsHidden: true)
        }*/
        return nil
    }
    
    // step 2, called only during migration
    @MainActor
    private func updateNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let parameters = params as? [String: String] else { return nil }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: parameters),
              let serpSettings = try? JSONDecoder().decode(SERPUserSettings.self, from: jsonData),
              let allowFollowUpQuestionsSetting = serpSettings.allowFollowUpQuestion else {
            return nil
        }
        
        serpSettingsProvider.migrateAllowFollowUpQuestions(enable: allowFollowUpQuestionsSetting)
        
        /// Return nil, as SERP does not need updated settings at this point.
        return nil
    }
    
    // step 3, handling user-interaction
    private func nativeSettingsDidChange() {
        guard let webView else {
            return
        }
        broker?.push(method: SERPSettingsUserScriptMessages.nativeSettingsDidChange.rawValue,
                     params: SERPUserSettings(provider: serpSettingsProvider),
                     for: self,
                     into: webView)
    }
}
