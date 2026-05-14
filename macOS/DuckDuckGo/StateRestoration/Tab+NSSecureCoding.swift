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

    static var supportsSecureCoding: Bool { true }

    @MainActor
    convenience init?(coder decoder: NSCoder) {
        guard let data = TabRestorationData(coder: decoder) else { return nil }

        self.init(uuid: data.uuid,
                  content: data.content,
                  title: data.title,
                  favicon: data.favicon,
                  interactionStateData: data.interactionStateData,
                  shouldLoadInBackground: false,
                  lastSelectedAt: data.lastSelectedAt)

        _=self.awakeAfter(using: decoder)
    }

    func encode(with coder: NSCoder) {
        guard webView.configuration.websiteDataStore.isPersistent == true else { return }
        makeRestorationData().encode(with: coder)
    }

    func makeRestorationData() -> TabRestorationData {
        let restorableContent: Tab.TabContent = {
            guard case .url(let url, let credential, _) = content else { return content }
            return .url(url, credential: credential, source: .pendingStateRestoration)
        }()

        return TabRestorationData(
            uuid: uuid,
            content: restorableContent,
            title: title,
            favicon: favicon,
            interactionStateData: getActualInteractionStateData(),
            lastSelectedAt: lastSelectedAt,
            localHistoryIDs: localHistory.compactMap(\.identifier),
            tabSnapshotIdentifier: tabSnapshotIdentifier?.uuidString
        )
    }

}

extension Tab.TabContent {

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

    init?(type: ContentType, url: URL?, videoID: String?, timestamp: String?, preferencePane: PreferencePaneIdentifier?, historyPane: HistoryPaneIdentifier?) {
        switch type {
        case .newtab:
            self = .newtab
        case .url:
            guard let url = url else { return nil }
            self = .url(url, source: .pendingStateRestoration)
        case .bookmarks:
            self = .bookmarks
        case .history:
            self = .history(pane: historyPane)
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

    var historyPane: HistoryPaneIdentifier? {
        switch self {
        case let .history(pane: pane):
            return pane
        default:
            return nil
        }
    }

}
