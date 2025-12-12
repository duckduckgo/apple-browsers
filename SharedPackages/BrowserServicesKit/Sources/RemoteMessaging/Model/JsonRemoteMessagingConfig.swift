//
//  JsonRemoteMessagingConfig.swift
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

public enum RemoteMessageResponse {

    public struct JsonRemoteMessagingConfig: Decodable {
        let version: Int64
        let messages: [JsonRemoteMessage]
        let rules: [JsonMatchingRule]
    }

    struct JsonRemoteMessage: Decodable, Equatable {
        let id: String
        let surfaces: [String]?
        let content: JsonContent
        let translations: [String: JsonContentTranslation]?
        let matchingRules, exclusionRules: [Int]?
        let metrics: JsonMetrics?

        static func == (lhs: JsonRemoteMessage, rhs: JsonRemoteMessage) -> Bool {
            return lhs.id == rhs.id
        }

        var isMetricsEnabled: Bool {
            metrics?.state.flatMap(JsonMetrics.MetricsState.init) != .disabled
        }
    }

    struct JsonMetrics: Decodable {
        let state: String?

        enum MetricsState: String, Decodable {
            case disabled
            case enabled
        }
    }

    package struct JsonContent: Decodable {
        let messageType: String
        let titleText: String
        let descriptionText: String
        let listItems: [JsonListItem]?
        let placeholder: String?
        let actionText: String?
        let action: JsonMessageAction?
        let primaryActionText: String?
        let primaryAction: JsonMessageAction?
        let secondaryActionText: String?
        let secondaryAction: JsonMessageAction?
    }

    struct JsonListItem: Decodable {
        let id: String
        let type: String
        let titleText: String
        let descriptionText: String?
        let placeholder: String?
        let primaryAction: JsonMessageAction?
        let matchingRules: [Int]?
        let exclusionRules: [Int]?
    }

    enum JsonListItemType: String, CaseIterable {
       case twoLinesItem = "two_line_list_item"
    }

    enum JsonSurface: String, CaseIterable {
        case newTabPage = "new_tab_page"
        case modal
        // Used for 'What's New' (macOS)
        case dedicatedTab = "dedicated_tab"
    }

    struct JsonMessageAction: Decodable {
        let type: String
        let value: String
        let additionalParameters: [String: String]?
    }

    struct JsonContentTranslation: Decodable {
        let messageType: String?
        let titleText: String?
        let descriptionText: String?
        let primaryActionText: String?
        let secondaryActionText: String?
        let listItems: [String: JsonListItemTranslation]?
    }

    struct JsonListItemTranslation: Decodable {
        let titleText: String?
        let descriptionText: String?
    }

    struct JsonTargetPercentile: Decodable {
        let before: Float?
    }

    struct JsonMatchingRule: Decodable {
        let id: Int
        let targetPercentile: JsonTargetPercentile?
        let attributes: [String: AnyDecodable]
    }

    enum JsonMessageType: String, CaseIterable {
        case small
        case medium
        case bigSingleAction = "big_single_action"
        case bigTwoAction = "big_two_action"
        case promoSingleAction = "promo_single_action"
        case cardsList = "cards_list"
    }

    enum JsonActionType: String, CaseIterable {
        case share
        case url
        case urlInContext = "url_in_context"
        case appStore = "appstore"
        case dismiss
        case survey = "survey"
        case navigation
    }

    enum JsonPlaceholder: String, CaseIterable {
        case announce = "Announce"
        case ddgAnnounce = "DDGAnnounce"
        case criticalUpdate = "CriticalUpdate"
        case appUpdate = "AppUpdate"
        case macComputer = "MacComputer"
        case newForMacAndWindows = "NewForMacAndWindows"
        case privacyShield = "PrivacyShield"
        case aiChat = "Duck.ai"
        case visualDesignUpdate = "VisualDesignUpdate"
        case imageAI = "ImageAI"
        case radar = "Radar"
        case keyImport = "KeyImport"
        case mobileCustomization = "MobileCustomization"
    }

    public enum StatusError: Error {
        case noData
        case parsingFailed
    }
}
