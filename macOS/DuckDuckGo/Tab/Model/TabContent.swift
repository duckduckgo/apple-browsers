//
//  TabContent.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import Foundation
import HistoryView
import Navigation
import Subscription

extension Tab {

    enum Content: Equatable {
        case newtab
        case url(URL, credential: URLCredential? = nil, source: URLSource)
        case settings(pane: PreferencePaneIdentifier?)
        case bookmarks
        case history(pane: HistoryPaneIdentifier?)
        case onboarding
        case none
        case dataBrokerProtection
        case subscription(URL)
        case identityTheftRestoration(URL)
        case releaseNotes
        case webExtensionUrl(URL)
        case aiChat(URL)
    }
    typealias TabContent = Tab.Content

}
typealias TabContent = Tab.Content
typealias HistoryPaneIdentifier = HistoryView.DataModel.HistoryRange

extension TabContent {

    enum URLSource: Equatable {
        case pendingStateRestoration
        case loadedByStateRestoration
        case userEntered(String, downloadRequested: Bool = false)
        case historyEntry
        case bookmark(isFavorite: Bool)
        case ui
        case link
        case appOpenUrl
        case reload
        case switchToOpenTab

        case webViewUpdated

        var userEnteredValue: String? {
            if case .userEntered(let userEnteredValue, _) = self {
                userEnteredValue
            } else {
                nil
            }
        }

        var isUserEnteredUrl: Bool {
            userEnteredValue != nil
        }

        var navigationType: NavigationType {
            switch self {
            case .userEntered(_, downloadRequested: true):
                .custom(.userRequestedPageDownload)
            case .userEntered, .switchToOpenTab /* fallback */:
                .custom(.userEnteredUrl)
            case .pendingStateRestoration:
                .sessionRestoration
            case .loadedByStateRestoration:
                .custom(.loadedByStateRestoration)
            case .appOpenUrl:
                .custom(.appOpenUrl)
            case .historyEntry:
                .custom(.historyEntry)
            case .bookmark:
                .custom(.bookmark)
            case .ui:
                .custom(.ui)
            case .link:
                .custom(.link)
            case .webViewUpdated:
                .custom(.webViewUpdated)
            case .reload:
                .reload
            }
        }

        var cachePolicy: URLRequest.CachePolicy {
            switch self {
            case .pendingStateRestoration, .historyEntry:
                .returnCacheDataElseLoad
            case .reload, .loadedByStateRestoration:
                .reloadIgnoringCacheData
            case .userEntered, .bookmark, .ui, .link, .appOpenUrl, .webViewUpdated, .switchToOpenTab:
                .useProtocolCachePolicy
            }
        }

    }
}
extension TabContent {

    // swiftlint:disable:next cyclomatic_complexity
    static func contentFromURL(_ url: URL?, source: URLSource) -> TabContent {
        switch url {
        case URL.newtab, URL.Invalid.aboutNewtab, URL.Invalid.duckHome:
            return .newtab
        case URL.onboarding:
            return .onboarding
        case URL.settings, URL.Invalid.aboutPreferences, URL.Invalid.aboutConfig, URL.Invalid.aboutSettings, URL.Invalid.duckConfig, URL.Invalid.duckPreferences:
            return .anySettingsPane
        case URL.bookmarks, URL.Invalid.aboutBookmarks:
            return .bookmarks
        case URL.dataBrokerProtection:
            return .dataBrokerProtection
        case URL.releaseNotes:
            return .releaseNotes
        case URL.Invalid.aboutHome:
            guard let customURL = URL(string: NSApp.delegateTyped.startupPreferences.formattedCustomHomePageURL) else {
                return .newtab
            }
            return .url(customURL, source: source)
        case URL.history, URL.Invalid.aboutHistory:
            return .anyHistoryPane
        default: break
        }

        if let url {
            if url.isWebExtensionUrl {
                return .webExtensionUrl(url)
            }
            if url.isDuckAIURL,
               NSApp.delegateTyped.featureFlagger.isFeatureOn(.aiChatSidebar) {
                    return .aiChat(url)
            }

            let subscriptionManager = Application.appDelegate.subscriptionAuthV1toV2Bridge
            let environment = subscriptionManager.currentEnvironment.serviceEnvironment
            let subscriptionBaseURL = subscriptionManager.url(for: .baseURL)
            let identityTheftRestorationURL = subscriptionManager.url(for: .identityTheftRestoration)
            if url.isChild(of: subscriptionBaseURL) {
                if environment == .staging, url.getParameter(named: "environment") == nil {
                    return .subscription(url.appendingParameter(name: "environment", value: "staging"))
                }
                return .subscription(url)
            } else if url.isChild(of: identityTheftRestorationURL) {
                return .identityTheftRestoration(url)
            }
        }

        if let settingsPane = url.flatMap(PreferencePaneIdentifier.init(url:)) {
            return .settings(pane: settingsPane)
        } else if let historyPane = url.flatMap(HistoryPaneIdentifier.init(url:)) {
            return .history(pane: historyPane)
        } else if url?.isDuckPlayer == true, let (videoId, timestamp) = url?.youtubeVideoParams {
            return .url(.duckPlayer(videoId, timestamp: timestamp), credential: nil, source: source)
        } else if let url, let credential = url.basicAuthCredential {
            // when navigating to a URL with basic auth username/password, cache it and redirect to a trimmed URL
            return .url(url.removingBasicAuthCredential(), credential: credential, source: source)
        } else {
            return .url(url ?? .blankPage, source: source)
        }
    }

    static var displayableTabTypes: [TabContent] {
        // Add new displayable types here
        let displayableTypes = [TabContent.anySettingsPane, .bookmarks]

        return displayableTypes.sorted { first, second in
            guard let firstTitle = first.title, let secondTitle = second.title else {
                return true // Arbitrary sort order, only non-standard tabs are displayable.
            }
            return firstTitle.localizedStandardCompare(secondTitle) == .orderedAscending
        }
    }

    /// Convenience accessor for `.preferences` Tab Content with no particular pane selected,
    /// i.e. the currently selected pane is decided internally by `PreferencesViewController`.
    static let anySettingsPane: Self = .settings(pane: nil)
    static let anyHistoryPane: Self = .history(pane: nil)

    var isDisplayable: Bool {
        switch self {
        case .settings, .bookmarks, .history, .dataBrokerProtection, .subscription, .identityTheftRestoration, .releaseNotes, .aiChat:
            return true
        default:
            return false
        }
    }

    func matchesDisplayableTab(_ other: TabContent) -> Bool {
        switch (self, other) {
        case (.settings, .settings):
            return true
        case (.bookmarks, .bookmarks):
            return true
        case (.history, .history):
            return true
        case (.dataBrokerProtection, .dataBrokerProtection):
            return true
        case (.subscription, .subscription):
            return true
        case (.identityTheftRestoration, .identityTheftRestoration):
            return true
        case (.releaseNotes, .releaseNotes):
            return true
        default:
            return false
        }
    }

    var title: String? {
        switch self {
        case .url, .newtab, .onboarding, .none, .webExtensionUrl: return nil
        case .settings: return UserText.tabPreferencesTitle
        case .bookmarks: return UserText.tabBookmarksTitle
        case .history: return UserText.mainMenuHistory
        case .dataBrokerProtection: return UserText.tabDataBrokerProtectionTitle
        case .releaseNotes: return UserText.releaseNotesTitle
        case .subscription, .identityTheftRestoration: return nil
        case .aiChat: return nil
        }
    }

    // !!! don‘t add `url` property to avoid ambiguity with the `.url` enum case
    // use `userEditableUrl` or `urlForWebView` instead.

    /// user-editable URL displayed in the address bar
    var userEditableUrl: URL? {
        let url = urlForWebView
        if let url, url.isDuckPlayer,
           let (videoID, timestamp) = url.youtubeVideoParams {
            return .duckPlayer(videoID, timestamp: timestamp)
        }
        return url
    }

    /// `real` URL loaded in the web view
    var urlForWebView: URL? {
        switch self {
        case .url(let url, credential: _, source: _), .subscription(let url), .identityTheftRestoration(let url), .webExtensionUrl(let url), .aiChat(let url):
            return url
        case .newtab:
            return .newtab
        case .settings(pane: .some(let pane)):
            return .settingsPane(pane)
        case .settings(pane: .none):
            return .settings
        case .bookmarks:
            return .bookmarks
        case .history(pane: .some(let pane)):
            return .historyPane(pane)
        case .history(pane: .none):
            return .history
        case .onboarding:
            return URL.onboarding
        case .dataBrokerProtection:
            return .dataBrokerProtection
        case .releaseNotes:
            return .releaseNotes
        case .none:
            return nil
        }
    }

    var source: URLSource {
        switch self {
        case .url(_, _, source: let source):
            return source
        case .newtab, .settings, .bookmarks, .history, .onboarding, .releaseNotes, .dataBrokerProtection,
                .subscription, .identityTheftRestoration, .webExtensionUrl, .none, .aiChat:
            return .ui
        }
    }

    var isExternalUrl: Bool {
        switch self {
        case .url, .subscription, .identityTheftRestoration, .aiChat:
            return true
        default:
            return false
        }
    }

    var userEnteredValue: String? {
        switch self {
        case .url(_, credential: _, source: let source):
            return source.userEnteredValue
        default:
            return nil
        }
    }

    var isUserEnteredUrl: Bool {
        userEnteredValue != nil
    }

    var isHistory: Bool {
        if case .history = self { true } else { false }
    }

    var isUserRequestedPageDownload: Bool {
        if case .url(_, credential: _, source: .userEntered(_, downloadRequested: true)) = self {
            return true
        } else {
            return false
        }
    }

    var displaysContentInWebView: Bool {
        switch self {
        case .url, .subscription, .identityTheftRestoration, .releaseNotes, .history, .aiChat: true
        default: false
        }
    }

    var usesExternalWebView: Bool {
        switch self {
        case .newtab, .history:
            return true
        default:
            return false
        }
    }

    var canBeDuplicated: Bool {
        switch self {
        case .settings, .subscription, .identityTheftRestoration, .dataBrokerProtection, .releaseNotes:
            return false
        default:
            return true
        }
    }

    var canBePinned: Bool {
        switch self {
        case .subscription, .identityTheftRestoration, .dataBrokerProtection, .history, .settings, .newtab, .bookmarks:
            return true
        case .releaseNotes:
            return false
        default:
            return isExternalUrl
        }
    }

    var canBeBookmarked: Bool {
        switch self {
        case .history, .newtab, .onboarding, .bookmarks, .settings, .none:
            return false
        case .url, .subscription, .identityTheftRestoration, .dataBrokerProtection, .releaseNotes, .webExtensionUrl, .aiChat:
            return true
        }
    }
}
extension HistoryPaneIdentifier {
    init?(url: URL) {
        // Try query parameter format first (duck://history?range=today)
        if let rangeValue = url.getParameter(named: "range") {
            self.init(rawValue: rangeValue)
            return
        }

        // Fallback to path format (duck://history/today, about:history/today)
        // Manually extract path because URLs such as "about:history" can't figure out their host or path
        for urlPrefix in [URL.history, URL.Invalid.aboutHistory] {
            let prefix = urlPrefix.absoluteString + "/"
            guard url.absoluteString.hasPrefix(prefix) else { continue }

            let path = url.absoluteString.dropping(prefix: prefix)
            self.init(rawValue: path)
            return
        }
        return nil
    }
}
