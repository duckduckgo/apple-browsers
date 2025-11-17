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
        let filteredMessages = remoteConfig.messages.filter { !dismissedMessageIds.contains($0.id) }
        let rulesEvaluator = rulesEvaluator(remoteRules: remoteConfig.rules)

        return filteredMessages
            .compactMap { message in
                // Skip message if it fails message-level targeting rules
                guard rulesEvaluator(message.id, message.matchingRules, message.exclusionRules) else { return nil }

                // Messages without items pass as rules for the message have been evaluated and not discarded in the process.
                guard let items = message.content?.listItems else { return message }

                // Filter items by their individual targeting rules
                let filteredItems = items.filter { item in
                    rulesEvaluator(item.id, item.matchingRules, item.exclusionRules)
                }
                // Skip message if no items remain after filtering.
                guard !filteredItems.isEmpty else { return nil }

                // If items have been filtered return new content with items otherwise return the same message.
                return items != filteredItems ? message.withFilteredItems(filteredItems) : message
            }
            .first
    }

    func evaluateMatchingRules(_ matchingRules: [Int], entityID: String, fromRules rules: [RemoteConfigRule]) -> EvaluationResult {
        evaluateRules(matchingRules, entityID: entityID, fromRules: rules, type: .matching)
    }

    func evaluateExclusionRules(_ exclusionRules: [Int], entityID: String, fromRules rules: [RemoteConfigRule]) -> EvaluationResult {
        evaluateRules(exclusionRules, entityID: entityID, fromRules: rules, type: .exclusion)
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

private extension RemoteMessagingConfigMatcher {

    enum RuleType {
        case matching
        case exclusion

        var defaultResult: EvaluationResult {
            switch self {
            case .matching: return .match
            case .exclusion: return .fail
            }
        }

        var percentileFailMessage: String {
            switch self {
            case .matching: return "Matching rule percentile check failed"
            case .exclusion: return "Exclusion rule percentile check failed"
            }
        }

        var attributeFailMessage: String {
            switch self {
            case .matching: return "First failing matching attribute"
            case .exclusion: return "First failing exclusion attribute"
            }
        }
    }

    func evaluateRules(
        _ rules: [Int],
        entityID: String,
        fromRules configRules: [RemoteConfigRule],
        type: RuleType
    ) -> EvaluationResult {
        var result: EvaluationResult = type.defaultResult

        for rule in rules {
            guard let matchingRule = configRules.first(where: { $0.id == rule }) else {
                return .nextMessage
            }

            if let percentile = matchingRule.targetPercentile, let messagePercentile = percentile.before {
                let userPercentile = percentileStore.percentile(forEntityId: entityID)

                if userPercentile > messagePercentile {
                    Logger.remoteMessaging.info("\(type.percentileFailMessage) for entity with ID \(entityID, privacy: .public)")
                    return .fail
                }
            }

            result = type.defaultResult

            for attribute in matchingRule.attributes {
                result = evaluateAttribute(matchingAttribute: attribute)
                if result == .fail || result == .nextMessage {
                    Logger.remoteMessaging.info("\(type.attributeFailMessage) \(String(describing: attribute), privacy: .public)")
                    break
                }
            }

            if result == .nextMessage || result == .match {
                return result
            }
        }

        return result
    }
}

private extension RemoteMessagingConfigMatcher {

    func rulesEvaluator(remoteRules: [RemoteConfigRule]) -> (String, [Int], [Int]) -> Bool {
        return { id, matchingRules, exclusionRules in
            // Handle empty rules case (auto-match like messages do)
            if matchingRules.isEmpty && exclusionRules.isEmpty {
                return true
            }

            let matchingResult = self.evaluateMatchingRules(matchingRules, entityID: id, fromRules: remoteRules)
            let exclusionResult = self.evaluateExclusionRules(exclusionRules, entityID: id, fromRules: remoteRules)
            return matchingResult == .match && exclusionResult == .fail
        }
    }

}

private extension RemoteMessageModel {

    func withFilteredItems(_ items: [RemoteMessageModelType.ListItem]) -> RemoteMessageModel {
        RemoteMessageModel(
            id: self.id,
            surfaces: self.surfaces,
            content: content?.withFilteredItems(items),
            matchingRules: self.matchingRules,
            exclusionRules: self.exclusionRules,
            isMetricsEnabled: self.isMetricsEnabled
        )
    }

}

private extension RemoteMessageModelType {

    func withFilteredItems(_ items: [ListItem]) -> Self {
        switch self {
        case .small, .medium, .bigSingleAction, .bigTwoAction, .promoSingleAction:
            return self
        case let .cardsList(titleText, placeholder, _, primaryActionText, primaryAction):
            return .cardsList(titleText: titleText, placeholder: placeholder, items: items, primaryActionText: primaryActionText, primaryAction: primaryAction)
        }
    }

}
