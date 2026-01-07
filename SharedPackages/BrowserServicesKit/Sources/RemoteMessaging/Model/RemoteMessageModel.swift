//
//  RemoteMessageModel.swift
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

public struct RemoteMessageModel: Equatable, Codable {

    public let id: String
    /// Specify the surface area where the message will be displayed. E.g. new tab page, dedicated tab or modal.
    public let surfaces: RemoteMessageSurfaceType
    public var content: RemoteMessageModelType?
    public let matchingRules: [Int]
    public let exclusionRules: [Int]
    public let isMetricsEnabled: Bool

    public init(id: String, surfaces: RemoteMessageSurfaceType, content: RemoteMessageModelType?, matchingRules: [Int], exclusionRules: [Int], isMetricsEnabled: Bool) {
        self.id = id
        self.surfaces = surfaces
        self.content = content
        self.matchingRules = matchingRules
        self.exclusionRules = exclusionRules
        self.isMetricsEnabled = isMetricsEnabled
    }

    enum CodingKeys: CodingKey {
        case id
        case surfaces
        case content
        case matchingRules
        case exclusionRules
        case isMetricsEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.surfaces = try container.decodeIfPresent(RemoteMessageSurfaceType.self, forKey: .surfaces) ?? .newTabPage
        self.content = try container.decodeIfPresent(RemoteMessageModelType.self, forKey: .content)
        self.matchingRules = try container.decode([Int].self, forKey: .matchingRules)
        self.exclusionRules = try container.decode([Int].self, forKey: .exclusionRules)
        self.isMetricsEnabled = try container.decodeIfPresent(Bool.self, forKey: .isMetricsEnabled) ?? true
    }

    mutating func localizeContent(translation: RemoteMessageResponse.JsonContentTranslation) {
        guard let content = content else {
            return
        }

        switch content {
        case .small(let titleText, let descriptionText):
            self.content = .small(titleText: translation.titleText ?? titleText,
                                  descriptionText: translation.descriptionText ?? descriptionText)
        case .medium(let titleText, let descriptionText, let placeholder):
            self.content = .medium(titleText: translation.titleText ?? titleText,
                                   descriptionText: translation.descriptionText ?? descriptionText,
                                   placeholder: placeholder)
        case .bigSingleAction(let titleText, let descriptionText, let placeholder, let primaryActionText, let primaryAction):
            self.content = .bigSingleAction(titleText: translation.titleText ?? titleText,
                                            descriptionText: translation.descriptionText ?? descriptionText,
                                            placeholder: placeholder,
                                            primaryActionText: translation.primaryActionText ?? primaryActionText,
                                            primaryAction: primaryAction)
        case .bigTwoAction(let titleText, let descriptionText, let placeholder, let primaryActionText, let primaryAction,
                           let secondaryActionText, let secondaryAction):
            self.content = .bigTwoAction(titleText: translation.titleText ?? titleText,
                                         descriptionText: translation.descriptionText ?? descriptionText,
                                         placeholder: placeholder,
                                         primaryActionText: translation.primaryActionText ?? primaryActionText,
                                         primaryAction: primaryAction,
                                         secondaryActionText: translation.secondaryActionText ?? secondaryActionText,
                                         secondaryAction: secondaryAction)
        case .promoSingleAction(let titleText, let descriptionText, let placeholder, let actionText, let action):
            self.content = .promoSingleAction(titleText: translation.titleText ?? titleText,
                                            descriptionText: translation.descriptionText ?? descriptionText,
                                            placeholder: placeholder,
                                            actionText: translation.primaryActionText ?? actionText,
                                            action: action)

        case .cardsList(let titleText, let placeholder, let items, let primaryActionText, let primaryAction):

            let translatedItems: [RemoteMessageModelType.ListItem] = items.map { item in
                guard let translatedItem = translation.listItems?[item.id] else {
                    return item
                }

                let translatedItemType: RemoteMessageModelType.ListItem.ListItemType
                switch item.type {
                case let .twoLinesItem(titleText, descriptionText, placeholderImage, action):
                    translatedItemType = .twoLinesItem(
                        titleText: translatedItem.titleText ?? titleText,
                        descriptionText: translatedItem.descriptionText ?? descriptionText,
                        placeholderImage: placeholderImage,
                        action: action
                    )
                case let .titledSection(titleText, itemIDs):
                    translatedItemType = .titledSection(
                        titleText: translatedItem.titleText ?? titleText,
                        itemIDs: itemIDs
                    )
                }

                return RemoteMessageModelType.ListItem(
                    id: item.id,
                    type: translatedItemType,
                    matchingRules: item.matchingRules,
                    exclusionRules: item.exclusionRules
                )
            }

            self.content = .cardsList(
                titleText: translation.titleText ?? titleText,
                placeholder: placeholder,
                items: translatedItems,
                primaryActionText: translation.primaryActionText ?? primaryActionText,
                primaryAction: primaryAction
            )
        }
    }
}

public struct RemoteMessageSurfaceType: OptionSet, Codable, Hashable, Equatable {
    public var rawValue: Int16

    public init(rawValue: Int16) {
        self.rawValue = rawValue
    }

    /// Used to show a remote message as widgets in the browser new tab page.
    public static let newTabPage = RemoteMessageSurfaceType(rawValue: 1 << 0)
    /// Used to show a remote message in a modal prompt.
    public static let modal = RemoteMessageSurfaceType(rawValue: 1 << 1)
    /// Used to show a remote message in a dedicated tab.
    public static let dedicatedTab = RemoteMessageSurfaceType(rawValue: 1 << 2)
    /// Used to show a remote message in the tab bar of the browser.
    public static let tabBar = RemoteMessageSurfaceType(rawValue: 1 << 3)

    public static let allCases: RemoteMessageSurfaceType = [.newTabPage, .modal, .dedicatedTab, .tabBar]
}

public enum RemoteMessageModelType: Codable, Equatable {
    case small(titleText: String, descriptionText: String)
    case medium(titleText: String, descriptionText: String, placeholder: RemotePlaceholder)
    case bigSingleAction(titleText: String, descriptionText: String, placeholder: RemotePlaceholder,
                         primaryActionText: String, primaryAction: RemoteAction)
    case bigTwoAction(titleText: String, descriptionText: String, placeholder: RemotePlaceholder,
                      primaryActionText: String, primaryAction: RemoteAction, secondaryActionText: String,
                      secondaryAction: RemoteAction)
    case promoSingleAction(titleText: String, descriptionText: String, placeholder: RemotePlaceholder,
                           actionText: String, action: RemoteAction)
    case cardsList(titleText: String, placeholder: RemotePlaceholder?, items: [ListItem], primaryActionText: String, primaryAction: RemoteAction)
}

extension RemoteMessageModelType {

    var listItems: [ListItem]? {
        switch self {
        case .small, .medium, .bigSingleAction, .bigTwoAction, .promoSingleAction:
            return nil
        case let .cardsList(_, _, items, _, _):
            return items
        }
    }
}

public extension RemoteMessageModelType {

    struct ListItem: Codable, Equatable {
        public let id: String
        public let type: ListItemType
        public let matchingRules: [Int]
        public let exclusionRules: [Int]

        public init(id: String, type: ListItemType, matchingRules: [Int], exclusionRules: [Int]) {
            self.id = id
            self.type = type
            self.matchingRules = matchingRules
            self.exclusionRules = exclusionRules
        }
    }
}

public extension RemoteMessageModelType.ListItem {

    enum ListItemType: Codable, Equatable {
        /// Represents a standard two-line card with an icon, title, description, and optional action.
        /// - Parameters:
        ///   - titleText: The main title of the card (required, translatable)
        ///   - descriptionText: Supporting description text (required, translatable)
        ///   - placeholderImage: Image to display alongside the text
        ///   - action: Optional action triggered when the card is tapped
        case twoLinesItem(titleText: String, descriptionText: String, placeholderImage: RemotePlaceholder, action: RemoteAction?)

        /// Represents a section header with a title and an array of item IDs belonging to this section.
        /// - Parameters:
        ///   - titleText: The section header text (required, translatable)
        ///   - itemIDs: Array of item IDs that belong to this section. Used to determine if the section should be displayed after filtering.
        case titledSection(titleText: String, itemIDs: [String])
    }

}

public enum NavigationTarget: String, Codable, Equatable {
    case duckAISettings = "duckai.settings"
    case settings
    case feedback
    case sync
    case importPasswords = "import.passwords"
    case appearance
}

public enum RemoteAction: Codable, Equatable {
    case share(value: String, title: String?)
    /// Used to open a URL from a browser tab.
    case url(value: String)
    /// Used to open a URL from an embedded web view.
    case urlInContext(value: String)
    case survey(value: String)
    case appStore
    case dismiss
    case navigation(value: NavigationTarget)
}

public enum RemotePlaceholder: String, Codable, CaseIterable {
    case announce = "RemoteMessageAnnouncement"
    case ddgAnnounce = "RemoteMessageDDGAnnouncement"
    case criticalUpdate = "RemoteMessageCriticalAppUpdate"
    case appUpdate = "RemoteMessageAppUpdate"
    case macComputer = "RemoteMessageMacComputer"
    case newForMacAndWindows = "RemoteMessageNewForMacAndWindows"
    case privacyShield = "RemoteMessagePrivacyShield"
    case aiChat = "RemoteDuckAi"
    case visualDesignUpdate = "RemoteVisualDesignUpdate"
    case imageAI = "RemoteImageAI"
    case radar = "RemoteMessageRadar"
    case radarCheckGreen = "RemoteRadar"
    case radarCheckPurple = "RemoteMessageRadarCheck"
    case keyImport = "RemoteKeyImport"
    case mobileCustomization = "RemoteMobileCustomization"
    case pir = "RemoteMessagePIR"
    case subscription = "RemoteMessageSubscription"
}
