//
//  Tab+NSSecureCoding.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

extension Tab: NSSecureCoding {
    // MARK: - Coding

    private enum NSSecureCodingKeys {
        static let uuid = "uuid"
        static let url = "url"
        static let videoID = "videoID"
        static let videoTimestamp = "videoTimestamp"
        static let title = "title"
        static let sessionStateData = "ssdata" // Used for session restoration on macOS 10.15 – 11
        static let interactionStateData = "interactionStateData" // Used for session restoration on macOS 12+
        static let favicon = "icon"
        static let tabType = "tabType"
        static let preferencePane = "preferencePane"
        static let lastSelectedAt = "lastSelectedAt"
    }

    static var supportsSecureCoding: Bool { true }

    @MainActor
    convenience init?(coder decoder: NSCoder) {
        let uuid: String? = decoder.decodeIfPresent(at: NSSecureCodingKeys.uuid)
        let url: URL? = decoder.decodeIfPresent(at: NSSecureCodingKeys.url)
        let videoID: String? = decoder.decodeIfPresent(at: NSSecureCodingKeys.videoID)
        let videoTimestamp: String? = decoder.decodeIfPresent(at: NSSecureCodingKeys.videoTimestamp)
        let preferencePane = decoder.decodeIfPresent(at: NSSecureCodingKeys.preferencePane)
            .flatMap(PreferencePaneIdentifier.init(rawValue:))

        guard let tabTypeRawValue: Int = decoder.decodeIfPresent(at: NSSecureCodingKeys.tabType),
              let tabType = TabContent.ContentType(rawValue: tabTypeRawValue),
              let content = TabContent(type: tabType, url: url, videoID: videoID, timestamp: videoTimestamp, preferencePane: preferencePane)
        else { return nil }

        let interactionStateData: Data? = decoder.decodeIfPresent(at: NSSecureCodingKeys.interactionStateData) ?? decoder.decodeIfPresent(at: NSSecureCodingKeys.sessionStateData)

        self.init(uuid: uuid,
                  content: content,
                  title: decoder.decodeIfPresent(at: NSSecureCodingKeys.title),
                  favicon: decoder.decodeIfPresent(at: NSSecureCodingKeys.favicon),
                  interactionStateData: interactionStateData,
                  shouldLoadInBackground: false,
                  lastSelectedAt: decoder.decodeIfPresent(at: NSSecureCodingKeys.lastSelectedAt))

        _=self.awakeAfter(using: decoder)
    }

    func encode(with coder: NSCoder) {
        guard webView.configuration.websiteDataStore.isPersistent == true else { return }

        coder.encode(uuid, forKey: NSSecureCodingKeys.uuid)
        content.urlForWebView.map(coder.encode(forKey: NSSecureCodingKeys.url))
        title.map(coder.encode(forKey: NSSecureCodingKeys.title))
        favicon.map(coder.encode(forKey: NSSecureCodingKeys.favicon))

        getActualInteractionStateData().map(coder.encode(forKey: NSSecureCodingKeys.interactionStateData))

        coder.encode(content.type.rawValue, forKey: NSSecureCodingKeys.tabType)
        lastSelectedAt.map(coder.encode(forKey: NSSecureCodingKeys.lastSelectedAt))

        if let pane = content.preferencePane {
            coder.encode(pane.rawValue, forKey: NSSecureCodingKeys.preferencePane)
        }

        self.encodeExtensions(with: coder)
    }

}

private extension Tab.TabContent {

    enum ContentType: Int, CaseIterable {
        case url = 0
        case preferences = 1
        case bookmarks = 2
        case newtab = 3
        case onboardingDeprecated = 4 // Not in use anymore
        case duckPlayer = 5
        case dataBrokerProtection = 6
        case subscription = 7
        case identityTheftRestoration = 8
        case onboarding = 9
        case releaseNotes = 10
        case history = 11
        case webExtensionUrl = 12
        case aiChat = 13
    }

    init?(type: ContentType, url: URL?, videoID: String?, timestamp: String?, preferencePane: PreferencePaneIdentifier?) {
        switch type {
        case .newtab:
            self = .newtab
        case .url:
            guard let url = url else { return nil }
            self = .url(url, source: .pendingStateRestoration)
        case .bookmarks:
            self = .bookmarks
        case .history:
            self = .history
        case .preferences:
            self = .settings(pane: preferencePane)
        case .duckPlayer:
            guard let videoID = videoID else { return nil }
            self = .url(.duckPlayer(videoID, timestamp: timestamp), source: .pendingStateRestoration)
        case .dataBrokerProtection:
            self = .dataBrokerProtection
        case .subscription:
            guard let url = url else { return nil }
            self = .subscription(url)
        case .identityTheftRestoration:
            guard let url = url else { return nil }
            self = .identityTheftRestoration(url)
        case .releaseNotes:
            self = .releaseNotes
        case .onboarding:
            self = .onboarding
        case .webExtensionUrl:
            guard let url = url else { return nil }
            self = .webExtensionUrl(url)
        case .onboardingDeprecated:
            self = .onboarding
        case .aiChat:
            guard let url = url else { return nil }
            self = .aiChat(url)
        }
    }

    var type: ContentType {
        switch self {
        case .url: return .url
        case .newtab: return .newtab
        case .history: return .history
        case .bookmarks: return .bookmarks
        case .settings: return .preferences
        case .onboarding: return .onboarding
        case .none: return .newtab
        case .dataBrokerProtection: return .dataBrokerProtection
        case .subscription: return .subscription
        case .identityTheftRestoration: return .identityTheftRestoration
        case .releaseNotes: return .releaseNotes
        case .webExtensionUrl: return .webExtensionUrl
        case .aiChat: return .aiChat
        }
    }

    var preferencePane: PreferencePaneIdentifier? {
        switch self {
        case let .settings(pane: pane):
            return pane
        default:
            return nil
        }
    }

}
