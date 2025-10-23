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
import BrowserServicesKit

public enum SERPSettingsUserScriptMessages: String, CaseIterable {
    case openNativeSettings
    case updateNativeSettings
    case getNativeSettings
    case nativeSettingsDidChange
}


// MARK: - Delegate Protocol

protocol SERPSettingsUserScriptDelegate: AnyObject {

    func serpSettingsUserScriptDidRequestToCloseTabAndOpenPrivacySettings(_ userScript: SERPSettingsUserScript)
    func serpSettingsUserScriptDidRequestToCloseTabAndOpenAIFeaturesSettings(_ userScript: SERPSettingsUserScript)
    func serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(_ userScript: SERPSettingsUserScript)

}

public struct SERPSettingsSnapshot: Codable {
    public let aiChat: Bool
    public let allowFollowUpQuestion: Bool?
    
    public init(provider: SERPSettingsProviding) {
        self.aiChat = provider.isAIChatEnabled
        self.allowFollowUpQuestion = provider.isAllowFollowUpQuestionsEnabled
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aiChat, forKey: .aiChat)
        try container.encodeIfPresent(allowFollowUpQuestion, forKey: .allowFollowUpQuestion)
    }
    
    private enum CodingKeys: String, CodingKey {
        case aiChat = "duckai"
        case allowFollowUpQuestion = "kbg"
    }
}

enum SERPSettingsConstants {
    static let returnParameterKey = "return"
    static let screenParameterKey = "screen"
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
    private let featureFlagger: FeatureFlagger

    // MARK: - Initialization

    init(serpSettingsProvider: SERPSettingsProviding,
         featureFlagger: FeatureFlagger) {
        self.serpSettingsProvider = serpSettingsProvider
        messageOriginPolicy = .only(rules: Self.buildMessageOriginRules())
        self.featureFlagger = featureFlagger
        super.init()

        registerForNotifications()
    }

    func registerForNotifications() {
        NotificationCenter.default.addObserver(forName: .serpSettingsChanged,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.nativeSettingsDidChange()
        }
        NotificationCenter.default.addObserver(forName: .aiChatSettingsChanged,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.nativeSettingsDidChange()
        }
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
        case .updateNativeSettings:
            return updateNativeSettings
        case .getNativeSettings:
            return getNativeSettings
        case .nativeSettingsDidChange: // Never called by SERP — returning nil.
            return nil
        }
    }
    
    @MainActor
    func getNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        return SERPSettingsSnapshot(provider: serpSettingsProvider)
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
    private func updateNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let parameters = params as? [String: Any] else { return nil }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: parameters),
              let serpSettingsSnapshot = try? JSONDecoder().decode(SERPSettingsSnapshot.self, from: jsonData),
              let allowFollowUpQuestionsSetting = serpSettingsSnapshot.allowFollowUpQuestion else {
            return nil
        }
        
        serpSettingsProvider.migrateAllowFollowUpQuestions(enable: allowFollowUpQuestionsSetting)
        return nil
    }
    
    private func nativeSettingsDidChange() {
        guard let webView else {
            return
        }
        broker?.push(method: SERPSettingsUserScriptMessages.nativeSettingsDidChange.rawValue,
                     params: SERPSettingsSnapshot(provider: serpSettingsProvider),
                     for: self,
                     into: webView)
    }
}
