//
//  WebPushNotificationDelegate.swift
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
import OSLog
import UserNotifications
import WebKit

private let log = Logger(subsystem: "com.duckduckgo.macos.browser", category: "WebPush")

/// Receives SW-side `registration.showNotification(...)` callbacks from WebKit
/// and posts them via `UNUserNotificationCenter`. Installed as the `_delegate`
/// of `WKWebsiteDataStore` (see `WKWebsiteDataStore.ddg_setPushDelegate`).
///
/// PoC only — the production version would reuse `WebNotificationsHandler`'s
/// permission gating, icon fetching and pixel reporting.
@available(macOS 13.3, *)
final class WebPushNotificationDelegate: NSObject, _DDGWebsiteDataStoreDelegate {

    /// App-process-lifetime singleton — the data store's `_delegate` property
    /// is `weak`, so we keep a strong reference here.
    static let shared = WebPushNotificationDelegate()

    /// Key under which we stash the SW scope URL in the `UNNotificationRequest`'s
    /// `userInfo`, so `AppDelegate`'s `UNUserNotificationCenterDelegate` can
    /// route the click back to the right tab.
    static let scopeURLUserInfoKey = "ddg.webPush.scopeURL"

    private override init() {}

    /// Origins that should be treated as having notification permission granted.
    /// PoC: starts with the local test page and accepts ad-hoc additions from
    /// the debug menu. Production would wire this to `PermissionManager`.
    private var grantedOrigins: Set<String> = ["http://localhost:8765"]
    private let lock = NSLock()

    func grantPermission(forOrigin origin: String) {
        lock.lock(); defer { lock.unlock() }
        grantedOrigins.insert(origin)
    }

    // Explicit selector — Swift's auto-derived `notificationPermissionsFor:`
    // doesn't match what WebKit actually invokes.
    @objc(notificationPermissionsForWebsiteDataStore:)
    func notificationPermissions(for dataStore: WKWebsiteDataStore) -> [String: NSNumber] {
        lock.lock(); defer { lock.unlock() }
        let dict = Dictionary(uniqueKeysWithValues: grantedOrigins.map { ($0, NSNumber(value: true)) })
        log.info("🟣 [native] notificationPermissionsForWebsiteDataStore: → \(dict.keys.joined(separator: ","), privacy: .public)")
        return dict
    }

    func websiteDataStore(_ dataStore: WKWebsiteDataStore, showNotification notificationData: NSObject) {
        // `_WKNotificationData` fields are read via KVC. Fallback to
        // `dictionaryRepresentation` if any direct access fails.
        let title = (notificationData.value(forKey: "title") as? String) ?? "Notification"
        let body = (notificationData.value(forKey: "body") as? String) ?? ""
        let tag = notificationData.value(forKey: "tag") as? String
        let scopeURL = notificationData.value(forKey: "serviceWorkerRegistrationURL") as? URL
        let identifierRaw = notificationData.value(forKey: "identifier") as? String
        let identifier = (identifierRaw?.isEmpty == false) ? identifierRaw! : UUID().uuidString

        log.debug("WebPushNotificationDelegate: showNotification title=\(title, privacy: .public) scope=\(scopeURL?.absoluteString ?? "-", privacy: .public)")

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let tag, !tag.isEmpty {
            content.threadIdentifier = tag
        }
        if let scopeURL {
            content.userInfo = [Self.scopeURLUserInfoKey: scopeURL.absoluteString]
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            do {
                try await center.add(request)
            } catch {
                log.error("WebPushNotificationDelegate failed to post: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
