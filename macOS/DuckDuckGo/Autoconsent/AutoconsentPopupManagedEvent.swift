//
//  AutoconsentPopupManagedEvent.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

/// Represents a cookie popup managed event from either the user script or web extension source.
/// This unified type allows consumers to handle events from both sources without knowing
/// which implementation handled the popup.
public struct AutoconsentPopupManagedEvent {

    public enum Source {
        case userScript
        case webExtension
    }

    public let url: URL
    public let host: String
    public let cmpName: String
    public let isCosmetic: Bool
    public let totalClicks: Int
    public let duration: TimeInterval // in milliseconds
    public let source: Source

    public init(
        url: URL,
        host: String,
        cmpName: String,
        isCosmetic: Bool,
        totalClicks: Int,
        duration: TimeInterval,
        source: Source
    ) {
        self.url = url
        self.host = host
        self.cmpName = cmpName
        self.isCosmetic = isCosmetic
        self.totalClicks = totalClicks
        self.duration = duration
        self.source = source
    }

    /// Creates an event from notification userInfo dictionary
    init?(from userInfo: [AnyHashable: Any], source: Source) {
        guard let url = userInfo[AutoconsentPopupManagedEvent.NotificationKeys.url] as? URL,
              let host = url.host else { return nil }

        self.url = url
        self.host = host
        self.cmpName = userInfo[AutoconsentPopupManagedEvent.NotificationKeys.cmpName] as? String ?? "unknown"
        self.isCosmetic = userInfo[AutoconsentPopupManagedEvent.NotificationKeys.isCosmetic] as? Bool ?? false
        self.totalClicks = userInfo[AutoconsentPopupManagedEvent.NotificationKeys.totalClicks] as? Int ?? 0
        self.duration = userInfo[AutoconsentPopupManagedEvent.NotificationKeys.duration] as? TimeInterval ?? 0
        self.source = source
    }
}

// MARK: - Notification Support

extension AutoconsentPopupManagedEvent {

    /// Notification posted when the user script handles a cookie popup
    static let userScriptPopupManagedNotification = Notification.Name("com.duckduckgo.autoconsent.userScript.popupManaged")

    /// Notification posted when the web extension handles a cookie popup
    static let webExtensionPopupManagedNotification = Notification.Name("com.duckduckgo.autoconsent.webExtension.popupManaged")

    enum NotificationKeys {
        static let url = "url"
        static let cmpName = "cmpName"
        static let isCosmetic = "isCosmetic"
        static let totalClicks = "totalClicks"
        static let duration = "duration"
    }

    /// Creates userInfo dictionary for posting notifications
    static func makeNotificationUserInfo(
        url: URL,
        cmpName: String,
        isCosmetic: Bool,
        totalClicks: Int,
        duration: TimeInterval
    ) -> [String: Any] {
        return [
            NotificationKeys.url: url,
            NotificationKeys.cmpName: cmpName,
            NotificationKeys.isCosmetic: isCosmetic,
            NotificationKeys.totalClicks: totalClicks,
            NotificationKeys.duration: duration
        ]
    }
}
