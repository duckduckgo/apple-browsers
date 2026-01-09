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
    case subscriptionFreeTrialActive
    case interactedWithMessage
    case interactedWithDeprecatedMacRemoteMessage
    case installedMacAppStore
    case pinnedTabs
    case customHomePage
    case duckPlayerOnboarded
    case duckPlayerEnabled
    case messageShown
    case isCurrentFreemiumPIRUser
    case isCurrentPIRUser
    case allFeatureFlagsEnabled
    case syncEnabled
    case shouldShowWinBackOfferUrgencyMessage
    case daysSinceDuckAiUsed

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
        case .pproEligible: return IsSubscriptionEligibleUserMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproSubscriber: return IsDuckDuckGoSubscriberUserMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproDaysSinceSubscribed: return SubscriptionDaysSinceSubscribedMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproDaysUntilExpiryOrRenewal: return SubscriptionDaysUntilExpiryMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproPurchasePlatform: return SubscriptionPurchasePlatformMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .pproSubscriptionStatus: return SubscriptionStatusMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .subscriptionFreeTrialActive: return SubscriptionFreeTrialActiveMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
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
        case .isCurrentPIRUser: return PIRCurrentUserMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .allFeatureFlagsEnabled: return AllFeatureFlagsEnabledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .syncEnabled: return SyncEnabledMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .shouldShowWinBackOfferUrgencyMessage: return WinBackOfferUrgencyMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        case .daysSinceDuckAiUsed: return DaysSinceDuckAIUsedMatchingAttribute(jsonMatchingAttribute: jsonMatchingAttribute)
        }
    }
}

struct JsonToRemoteMessageModelMapper {

    static func maps(jsonRemoteMessages: [RemoteMessageResponse.JsonRemoteMessage],
                     surveyActionMapper: RemoteMessagingSurveyActionMapping,
                     supportedSurfacesForMessage: @escaping (RemoteMessageModelType) -> RemoteMessageSurfaceType) -> [RemoteMessageModel] {
        var remoteMessages: [RemoteMessageModel] = []
        jsonRemoteMessages.forEach { message in
            guard
                let content = mapToContent(content: message.content, surveyActionMapper: surveyActionMapper),
                let surfaces = mapToSurfaces(jsonSurfaces: message.surfaces, supportedSurfacesForMessage: supportedSurfacesForMessage(content), messageId: message.id )
            else {
                return
            }

            var remoteMessage = RemoteMessageModel(
                id: message.id,
                surfaces: surfaces,
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

    static func mapToSurfaces(jsonSurfaces: [String]?, supportedSurfacesForMessage: RemoteMessageSurfaceType, messageId: String) -> RemoteMessageSurfaceType? {

        func mapJsonSurfaceToDomain(_ jsonSurface: RemoteMessageResponse.JsonSurface) -> RemoteMessageSurfaceType {
            switch jsonSurface {
            case .newTabPage:
                    .newTabPage
            case .modal:
                    .modal
            case .dedicatedTab:
                    .dedicatedTab
            case .tabBar:
                    .tabBar
            }
        }

        func mapToEligibleDomainSurfaces(jsonSurfaces: Set<RemoteMessageResponse.JsonSurface>, supportedSurfacesForMessage: RemoteMessageSurfaceType) -> RemoteMessageSurfaceType {
            jsonSurfaces.reduce(into: RemoteMessageSurfaceType()) { flags, surface in
                let domainSurface = mapJsonSurfaceToDomain(surface)
                if supportedSurfacesForMessage.contains(domainSurface) {
                    flags.insert(domainSurface)
                }
            }
        }

        func logUnsupportedSurfacesIfNeeded(declaredSurfaces: Set<RemoteMessageResponse.JsonSurface>, eligibleSurfaces: RemoteMessageSurfaceType, messageId: String) {
            guard !eligibleSurfaces.isEmpty else {
                Logger.remoteMessaging.debug("No eligible surfaces after validation for message \(messageId, privacy: .public)")
                return
            }

            let droppedSurfaces = declaredSurfaces.filter { surface in
                !eligibleSurfaces.contains(mapJsonSurfaceToDomain(surface))
            }

            if !droppedSurfaces.isEmpty {
                Logger.remoteMessaging.debug("Dropped unsupported surfaces for message \(messageId, privacy: .public): \(droppedSurfaces.map(\.rawValue), privacy: .public)")
            }
        }

        // If surface is not defined then set to supportedSurfacesForMessage for backward compatibility (e.g. `.small` -> `newTabPage`, `promoList` -> `[.modal, .dedicatedTab]`)
        // If the supported surfaces contains `newTabPage` then we return ONLY that, otherwise messages could appear on the tab bar unexpectedly.
        guard let jsonSurfaces else {
            Logger.remoteMessaging.debug("No surfaces declared for message \(messageId, privacy: .public)")
            if supportedSurfacesForMessage.contains(.newTabPage) {
                return .newTabPage
            }
            return supportedSurfacesForMessage
        }

        // Parse JSON surfaces and filter unsupported values
        let declaredJSONSurfaces = Set(jsonSurfaces.compactMap(RemoteMessageResponse.JsonSurface.init(rawValue:)))

        // Filter out the surfaces that are not supported by the message type
        let eligibleSurfaces = mapToEligibleDomainSurfaces(jsonSurfaces: declaredJSONSurfaces, supportedSurfacesForMessage: supportedSurfacesForMessage)

        // Log surfaces that have been dropped
        logUnsupportedSurfacesIfNeeded(declaredSurfaces: declaredJSONSurfaces, eligibleSurfaces: eligibleSurfaces, messageId: messageId)

        // Return nil if none valid (so message gets discarded)
        return eligibleSurfaces.isEmpty ? nil : eligibleSurfaces
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

        case .cardsList:
            do {
                return try mapToCardsList(content, surveyActionMapper: surveyActionMapper)
            } catch {
                Logger.remoteMessaging.debug("\(error.localizedDescription, privacy: .public)")
                return nil
            }
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
        case .urlInContext:
            return .urlInContext(value: jsonAction.value)
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
            return .subscription
        case .aiChat:
            return .aiChat
        case .visualDesignUpdate:
            return .visualDesignUpdate
        case .imageAI:
            return .imageAI
        case .radar:
            return .radar
        case .radarCheckGreen:
            return .radarCheckGreen
        case .radarCheckPurple:
            return .radarCheckPurple
        case .keyImport:
            return .keyImport
        case .mobileCustomization:
            return .mobileCustomization
        case .pir:
            return .pir
        case .subscription:
            return .subscription
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

        if let languageCode = locale.languageCode, let translation = translations[languageCode] {
            return translation
        }

        return nil
    }
}

// MARK: - Cards List Mapping

private extension JsonToRemoteMessageModelMapper {

    static func mapToCardsList(_ jsonContent: RemoteMessageResponse.JsonContent, surveyActionMapper: RemoteMessagingSurveyActionMapping) throws -> RemoteMessageModelType {
        let validator = MappingValidator(root: jsonContent)
        let titleText = try validator.notEmpty(\.titleText)
        // Map to placeholder only if defined, otherwise return nil
        let placeHolderImage: RemotePlaceholder? = if let placeholder = jsonContent.placeholder {
            mapToPlaceholder(placeholder)
        } else {
            nil
        }
        let listItems = try validator.mapRequired(\.listItems) { items throws(MappingError) in
            let mappedItems = try mapToListItems(items, surveyActionMapper: surveyActionMapper)
            return try validator.notEmpty(mappedItems, keyPath: \RemoteMessageResponse.JsonContent.listItems)
        }
        let primaryActionText = try validator.notNilOrEmpty(\.primaryActionText)
        let primaryAction = try validator.mapRequired(\.primaryAction) { action in
            mapToAction(action, surveyActionMapper: surveyActionMapper)
        }
        return .cardsList(titleText: titleText, placeholder: placeHolderImage, items: listItems, primaryActionText: primaryActionText, primaryAction: primaryAction)
    }

    static func mapToListItems(_ jsonListItems: [RemoteMessageResponse.JsonListItem], surveyActionMapper: RemoteMessagingSurveyActionMapping) throws(MappingError) -> [RemoteMessageModelType.ListItem] {

        func mapToListItem(_ jsonListItem: RemoteMessageResponse.JsonListItem, surveyActionMapper: RemoteMessagingSurveyActionMapping) throws(MappingError) -> RemoteMessageModelType.ListItem {
            let validator = MappingValidator(root: jsonListItem)

            let id = try validator.notEmpty(\.id)
            let jsonType = try validator.mapEnum(\.type, to: RemoteMessageResponse.JsonListItemType.self)

            let matchingRules: [Int]
            let exclusionRules: [Int]

            let listItemType: RemoteMessageModelType.ListItem.ListItemType
            switch jsonType {
            case .featuredTwoLinesSingleActionItem:
                let titleText = try validator.notEmpty(\.titleText)
                let descriptionText = try validator.notNilOrEmpty(\.descriptionText)
                let placeHolderImage = mapToPlaceholder(jsonListItem.placeholder)
                let primaryRemoteAction = jsonListItem.primaryAction.flatMap { action in
                    mapToAction(action, surveyActionMapper: surveyActionMapper)
                }
                listItemType = .featuredTwoLinesSingleActionItem(titleText: titleText, descriptionText: descriptionText, placeholderImage: placeHolderImage, primaryActionText: jsonListItem.primaryActionText, primaryAction: primaryRemoteAction)
                matchingRules = jsonListItem.matchingRules ?? []
                exclusionRules = jsonListItem.exclusionRules ?? []
            case .twoLinesItem:
                let titleText = try validator.notEmpty(\.titleText)
                let descriptionText = jsonListItem.descriptionText ?? ""
                let placeHolderImage = mapToPlaceholder(jsonListItem.placeholder)
                let remoteAction = jsonListItem.primaryAction.flatMap { action in
                    mapToAction(action, surveyActionMapper: surveyActionMapper)
                }
                listItemType = .twoLinesItem(titleText: titleText, descriptionText: descriptionText, placeholderImage: placeHolderImage, action: remoteAction)
                matchingRules = jsonListItem.matchingRules ?? []
                exclusionRules = jsonListItem.exclusionRules ?? []
            case .titledSection:
                let titleText = try validator.notEmpty(\.titleText)
                let itemIDs = try validator.notNilOrEmpty(\.itemIDs)
                listItemType = .titledSection(titleText: titleText, itemIDs: itemIDs)
                // Sections don't support matching/exclusion rules
                matchingRules = []
                exclusionRules = []
            }

            return RemoteMessageModelType.ListItem(
                id: id,
                type: listItemType,
                matchingRules: matchingRules,
                exclusionRules: exclusionRules
            )
        }

        var mappedIDs: Set<String> = []
        var items: [RemoteMessageModelType.ListItem] = []

        jsonListItems.forEach { jsonListItem in
            do {
                // Check we have not mapped already an item with the same id and discard it
                guard !mappedIDs.contains(jsonListItem.id) else { throw MappingError.duplicateValue(\RemoteMessageResponse.JsonListItem.id) }
                let item = try mapToListItem(jsonListItem, surveyActionMapper: surveyActionMapper)
                // Check we have not mapped already a featured card (Only one can exist per list).
                if item.type.isFeaturedItem, items.contains(where: \.type.isFeaturedItem) {
                    throw MappingError.duplicateValue(\RemoteMessageResponse.JsonListItem.type)
                }
                // Only insert ID after successful parsing
                mappedIDs.insert(jsonListItem.id)
                items.append(item)
            } catch {
                Logger.remoteMessaging.debug("\(error.localizedDescription, privacy: .public)")
            }
        }
        return items
    }

}

// MARK: - Surfaces Helpers

private extension JsonToRemoteMessageModelMapper {

    static func supportedSurfaces(for messageType: RemoteMessageModelType) -> Set<RemoteMessageResponse.JsonSurface> {
        switch messageType {
        case .small, .medium, .bigSingleAction, .bigTwoAction, .promoSingleAction:
            return [.newTabPage, .tabBar]
        case .cardsList:
            return [.modal, .dedicatedTab]
        }
    }

}
