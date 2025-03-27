//
//  RemoteMessagingConfigMatcher.swift
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
import Common
import os.log

public struct RemoteMessagingConfigMatcher {

    private let appAttributeMatcher: AttributeMatching
    private let deviceAttributeMatcher: AttributeMatching
    private let userAttributeMatcher: AttributeMatching
    private let percentileStore: RemoteMessagingPercentileStoring
    private let dismissedMessageIds: [String]
    let surveyActionMapper: RemoteMessagingSurveyActionMapping

    private let matchers: [AttributeMatching]

    public init(appAttributeMatcher: AttributeMatching,
                deviceAttributeMatcher: AttributeMatching = DeviceAttributeMatcher(),
                userAttributeMatcher: AttributeMatching,
                percentileStore: RemoteMessagingPercentileStoring,
                surveyActionMapper: RemoteMessagingSurveyActionMapping,
                dismissedMessageIds: [String]) {
        self.appAttributeMatcher = appAttributeMatcher
        self.deviceAttributeMatcher = deviceAttributeMatcher
        self.userAttributeMatcher = userAttributeMatcher
        self.percentileStore = percentileStore
        self.surveyActionMapper = surveyActionMapper
        self.dismissedMessageIds = dismissedMessageIds

        matchers = [appAttributeMatcher, deviceAttributeMatcher, userAttributeMatcher]
    }

    func evaluate(remoteConfig: RemoteConfigModel) -> RemoteMessageModel? {
        let rules = remoteConfig.rules
        let filteredMessages = remoteConfig.messages.filter { !dismissedMessageIds.contains($0.id) }

        for message in filteredMessages {
            if message.matchingRules.isEmpty && message.exclusionRules.isEmpty {
                return message
            }

            let matchingResult = evaluateMatchingRules(message.matchingRules, messageID: message.id, fromRules: rules)
            let exclusionResult = evaluateExclusionRules(message.exclusionRules, messageID: message.id, fromRules: rules)

            if matchingResult == .match && exclusionResult == .fail {
                return message
            }
        }

        return nil
    }

    func evaluateMatchingRules(_ matchingRules: [Int], messageID: String, fromRules rules: [RemoteConfigRule]) -> EvaluationResult {
        var result: EvaluationResult = .match

        for rule in matchingRules {
            guard let matchingRule = rules.first(where: { $0.id == rule }) else {
                return .nextMessage
            }

            if let percentile = matchingRule.targetPercentile, let messagePercentile = percentile.before {
                let userPercentile = percentileStore.percentile(forMessageId: messageID)

                if userPercentile > messagePercentile {
                    Logger.remoteMessaging.debug("Matching rule percentile check failed for message with ID \(messageID, privacy: .public)")
                    return .fail
                }
            }

            result = .match

            for attribute in matchingRule.attributes {
                result = evaluateAttribute(matchingAttribute: attribute)
                if result == .fail || result == .nextMessage {
                    Logger.remoteMessaging.debug("First failing matching attribute \(String(describing: attribute), privacy: .public)")
                    break
                }
            }

            if result == .nextMessage || result == .match {
                return result
            }
        }
        return result
    }

    func evaluateExclusionRules(_ exclusionRules: [Int], messageID: String, fromRules rules: [RemoteConfigRule]) -> EvaluationResult {
        var result: EvaluationResult = .fail

        for rule in exclusionRules {
            guard let matchingRule = rules.first(where: { $0.id == rule }) else {
                return .nextMessage
            }

            if let percentile = matchingRule.targetPercentile, let messagePercentile = percentile.before {
                let userPercentile = percentileStore.percentile(forMessageId: messageID)

                if userPercentile > messagePercentile {
                    Logger.remoteMessaging.debug("Exclusion rule percentile check failed for message with ID \(messageID, privacy: .public)")
                    return .fail
                }
            }

            result = .fail

            for attribute in matchingRule.attributes {
                result = evaluateAttribute(matchingAttribute: attribute)
                if result == .fail || result == .nextMessage {
                    Logger.remoteMessaging.debug("First failing exclusion attribute \(String(describing: attribute), privacy: .public)")
                    break
                }
            }

            if result == .nextMessage || result == .match {
                return result
            }
        }
        return result
    }

    func evaluateAttribute(matchingAttribute: MatchingAttribute) -> EvaluationResult {
        if let matchingAttribute = matchingAttribute as? UnknownMatchingAttribute {
            return EvaluationResultModel.result(value: matchingAttribute.fallback)
        }

        for matcher in matchers {
            if let result = matcher.evaluate(matchingAttribute: matchingAttribute) {
                return result
            }
        }

        return .nextMessage
    }
}
