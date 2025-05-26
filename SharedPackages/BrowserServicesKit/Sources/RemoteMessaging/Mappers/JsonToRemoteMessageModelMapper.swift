//
//  JsonToRemoteMessageModelMapper.swift
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

private enum AttributesKey: String, CaseIterable {
    case locale
    case osApi
    case formFactor
    case isInternalUser
    case appId
    case appVersion
    case atb
    case appAtb
    case searchAtb
    case expVariant
    case emailEnabled
    case widgetAdded
    case bookmarks
    case favorites
    case appTheme
    case daysSinceInstalled
    case daysSinceNetPEnabled
    case pproEligible
    case pproSubscriber
    case pproDaysSinceSubscribed
    case pproDaysUntilExpiryOrRenewal
    case pproPurchasePlatform
    case pproSubscriptionStatus
    case interactedWithMessage
    case interactedWithDeprecatedMacRemoteMessage
    case installedMacAppStore
    case pinnedTabs
    case customHomePage
    case duckPlayerOnboarded
    case duckPlayerEnabled
    case messageShown
    case isCurrentFreemiumPIRUser
    case allFeatureFlagsEnabled

    func matchingAttribute(jsonMatchingAttribute: AnyDecodable) -> MatchingAttribute {
        switch self {
        case .locale: return LocaleMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .osApi: return OSMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .formFactor: return FormFactorMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .isInternalUser: return IsInternalUserMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .appId: return AppIdMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .appVersion: return AppVersionMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .atb: return AtbMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .appAtb: return AppAtbMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .searchAtb: return SearchAtbMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .expVariant: return ExpVariantMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .emailEnabled: return EmailEnabledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .widgetAdded: return WidgetAddedMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .bookmarks: return BookmarksMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .favorites: return FavoritesMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .appTheme: return AppThemeMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .daysSinceInstalled: return DaysSinceInstalledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .daysSinceNetPEnabled: return DaysSinceNetPEnabledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproEligible: return IsPrivacyProEligibleUserMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproSubscriber: return IsPrivacyProSubscriberUserMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproDaysSinceSubscribed: return PrivacyProDaysSinceSubscribedMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproDaysUntilExpiryOrRenewal: return PrivacyProDaysUntilExpiryMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproPurchasePlatform: return PrivacyProPurchasePlatformMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproSubscriptionStatus: return PrivacyProSubscriptionStatusMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .interactedWithMessage: return InteractedWithMessageMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .interactedWithDeprecatedMacRemoteMessage: return InteractedWithDeprecatedMacRemoteMessageMatchingAttribute(
            jsonMatchingAttribute: jsonMatchingAttribute
        )
        case .installedMacAppStore: return IsInstalledMacAppStoreMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pinnedTabs: return PinnedTabsMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .customHomePage: return CustomHomePageMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .duckPlayerOnboarded: return DuckPlayerOnboardedMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .duckPlayerEnabled: return DuckPlayerEnabledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .messageShown: return MessageShownMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .isCurrentFreemiumPIRUser: return FreemiumPIRCurrentUserMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .allFeatureFlagsEnabled: return AllFeatureFlagsEnabledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        }
    }
}

struct JsonToRemoteMessageModelMapper {

    static func maps(jsonRemoteMessages: [RemoteMessageResponse.JsonRemoteMessage],
                     surveyActionMapper: RemoteMessagingSurveyActionMapping) -> [RemoteMessageModel] {
        var remoteMessages: [RemoteMessageModel] = []
        jsonRemoteMessages.forEach { message in
            guard let content = mapToContent( content: message.content, surveyActionMapper: surveyActionMapper) else {
                return
            }

            var remoteMessage = RemoteMessageModel(
                id: message.id,
                content: content,
                matchingRules: message.matchingRules ?? [],
                exclusionRules: message.exclusionRules ?? [],
                isMetricsEnabled: message.isMetricsEnabled
            )

            if let translation = getTranslation(from: message.translations, for: Locale.current) {
                remoteMessage.localizeContent(translation: translation)
            }

            remoteMessages.append(remoteMessage)
        }
        return remoteMessages
    }

    static func mapToContent(content: RemoteMessageResponse.JsonContent,
                             surveyActionMapper: RemoteMessagingSurveyActionMapping) -> RemoteMessageModelType? {
        switch RemoteMessageResponse.JsonMessageType(rawValue: content.messageType) {
        case .small:
            guard !content.titleText.isEmpty, !content.descriptionText.isEmpty else {
                return nil
            }

            return .small(titleText: content.titleText,
                          descriptionText: content.descriptionText)
        case .medium:
            guard !content.titleText.isEmpty, !content.descriptionText.isEmpty else {
                return nil
            }

            return .medium(titleText: content.titleText,
                           descriptionText: content.descriptionText,
                           placeholder: mapToPlaceholder(content.placeholder))
        case .bigSingleAction:
            guard let primaryActionText = content.primaryActionText,
                  !primaryActionText.isEmpty,
                  let action = mapToAction(content.primaryAction, surveyActionMapper: surveyActionMapper)
            else {
                return nil
            }

            return .bigSingleAction(titleText: content.titleText,
                                    descriptionText: content.descriptionText,
                                    placeholder: mapToPlaceholder(content.placeholder),
                                    primaryActionText: primaryActionText,
                                    primaryAction: action)
        case .bigTwoAction:
            guard let primaryActionText = content.primaryActionText,
                  !primaryActionText.isEmpty,
                  let primaryAction = mapToAction(content.primaryAction, surveyActionMapper: surveyActionMapper),
                  let secondaryActionText = content.secondaryActionText,
                  !secondaryActionText.isEmpty,
                  let secondaryAction = mapToAction(content.secondaryAction, surveyActionMapper: surveyActionMapper)
            else {
                return nil
            }

            return .bigTwoAction(titleText: content.titleText,
                                 descriptionText: content.descriptionText,
                                 placeholder: mapToPlaceholder(content.placeholder),
                                 primaryActionText: primaryActionText,
                                 primaryAction: primaryAction,
                                 secondaryActionText: secondaryActionText,
                                 secondaryAction: secondaryAction)
        case .promoSingleAction:
            guard let actionText = content.actionText,
                  !actionText.isEmpty,
                  let action = mapToAction(content.action, surveyActionMapper: surveyActionMapper)
            else {
                return nil
            }

            return .promoSingleAction(titleText: content.titleText,
                                      descriptionText: content.descriptionText,
                                      placeholder: mapToPlaceholder(content.placeholder),
                                      actionText: actionText,
                                      action: action)

        case .none:
            return nil
        }
    }

    static func mapToAction(_ jsonAction: RemoteMessageResponse.JsonMessageAction?,
                            surveyActionMapper: RemoteMessagingSurveyActionMapping) -> RemoteAction? {
        guard let jsonAction = jsonAction else {
            return nil
        }

        switch RemoteMessageResponse.JsonActionType(rawValue: jsonAction.type) {
        case .share:
            return .share(value: jsonAction.value, title: jsonAction.additionalParameters?["title"])
        case .url:
            return .url(value: jsonAction.value)
        case .survey:
            if let queryParamsString = jsonAction.additionalParameters?["queryParams"] as? String {
                let queryParams = queryParamsString.components(separatedBy: ";")
                let mappedQueryParams = queryParams.compactMap { param in
                    return RemoteMessagingSurveyActionParameter(rawValue: param)
                }

                if mappedQueryParams.count == queryParams.count, let surveyURL = URL(string: jsonAction.value) {
                    let updatedURL = surveyActionMapper.add(parameters: mappedQueryParams, to: surveyURL)
                    return .survey(value: updatedURL.absoluteString)
                } else {
                    // The message requires a parameter that isn't supported
                    return nil
                }
            } else {
                return .survey(value: jsonAction.value)
            }
        case .appStore:
            return .appStore
        case .dismiss:
            return .dismiss
        case .navigation:
            if let value = NavigationTarget(rawValue: jsonAction.value) {
                return .navigation(value: value)
            } else {
                return nil
            }
        case .none:
            return nil
        }
    }

    static func mapToPlaceholder(_ jsonPlaceholder: String?) -> RemotePlaceholder {
        guard let jsonPlaceholder = jsonPlaceholder else {
            return .announce
        }

        switch RemoteMessageResponse.JsonPlaceholder(rawValue: jsonPlaceholder) {
        case .announce:
            return .announce
        case .appUpdate:
            return .appUpdate
        case .ddgAnnounce:
            return .ddgAnnounce
        case .criticalUpdate:
            return .criticalUpdate
        case .macComputer:
            return .macComputer
        case .newForMacAndWindows:
            return .newForMacAndWindows
        case .privacyShield:
            return .privacyShield
        case .aiChat:
            return .aiChat
        case .visualDesignUpdate:
            return .visualDesignUpdate
        case .none:
            return .announce
        }
    }

    static func maps(jsonRemoteRules: [RemoteMessageResponse.JsonMatchingRule]) -> [RemoteConfigRule] {
        return jsonRemoteRules.map { jsonRule in
            let mappedAttributes = jsonRule.attributes.map { attribute in
                if let key = AttributesKey(rawValue: attribute.key) {
                    return key.matchingAttribute(jsonMatchingAttribute: attribute.value)
                } else {
                    Logger.remoteMessaging.debug("Unknown attribute key \(attribute.key, privacy: .public)")
                    return UnknownMatchingAttribute(jsonMatchingAttribute: attribute.value)
                }
            }

            var mappedTargetPercentile: RemoteConfigTargetPercentile?

            if let jsonTargetPercentile = jsonRule.targetPercentile {
                mappedTargetPercentile = .init(before: jsonTargetPercentile.before)
            }

            return RemoteConfigRule(
                id: jsonRule.id,
                targetPercentile: mappedTargetPercentile,
                attributes: mappedAttributes
            )
        }
    }

    static func getTranslation(from translations: [String: RemoteMessageResponse.JsonContentTranslation]?,
                               for locale: Locale) -> RemoteMessageResponse.JsonContentTranslation? {
        guard let translations = translations else {
            return nil
        }

        if let translation = translations[LocaleMatchingAttribute.localeIdentifierAsJsonFormat(locale.identifier)] {
            return translation
        }

        return nil
    }
}
