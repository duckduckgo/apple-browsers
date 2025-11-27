//
//  WebNotificationsHandler.swift
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

import Common
import Foundation
import OSLog
import UserScript
import WebKit

/// Handles messages from the ContentScopeScripts webNotifications feature.
/// This handler bridges the JavaScript Notification API polyfill to native macOS notifications.
final class WebNotificationsHandler: NSObject, Subfeature {

    let messageOriginPolicy: MessageOriginPolicy = .all
    let featureName: String = "webNotifications"

    weak var broker: UserScriptMessageBroker?

    // MARK: - Message Names

    enum MessageNames: String, CaseIterable {
        case showNotification
        case closeNotification
        case requestPermission
    }

    // MARK: - Message Payloads

    struct ShowNotificationPayload: Decodable {
        let id: String
        let title: String
        let body: String?
        let icon: String?
        let tag: String?
    }

    struct CloseNotificationPayload: Decodable {
        let id: String
    }

    struct RequestPermissionResponse: Encodable {
        let permission: String
    }

    // MARK: - Subfeature Handler

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .showNotification:
            return { [weak self] params, original in
                self?.handleShowNotification(params: params, original: original)
                return nil
            }
        case .closeNotification:
            return { [weak self] params, original in
                self?.handleCloseNotification(params: params, original: original)
                return nil
            }
        case .requestPermission:
            return { [weak self] params, original in
                return self?.handleRequestPermission(params: params, original: original)
            }
        default:
            return nil
        }
    }

    // MARK: - Message Handlers

    private func handleShowNotification(params: Any, original: WKScriptMessage) {
        guard let payload: ShowNotificationPayload = DecodableHelper.decode(from: params) else {
            Logger.general.error("WebNotificationsHandler: Invalid showNotification payload")
            return
        }

        Logger.general.debug("""
            WebNotificationsHandler: Notification requested (ID: \(payload.id))
            - Title: \(payload.title)
            - Body: \(payload.body ?? "")
            - Icon: \(payload.icon ?? "")
            - Tag: \(payload.tag ?? "")
            """)

        // Project 3 will implement UNUserNotificationCenter.add() here
    }

    private func handleCloseNotification(params: Any, original: WKScriptMessage) {
        guard let payload: CloseNotificationPayload = DecodableHelper.decode(from: params) else {
            Logger.general.error("WebNotificationsHandler: Invalid closeNotification payload")
            return
        }

        Logger.general.debug("WebNotificationsHandler: Notification close requested (ID: \(payload.id))")

        // Project 7 will implement UNUserNotificationCenter.removeDeliveredNotifications() here
    }

    private func handleRequestPermission(params: Any, original: WKScriptMessage) -> Encodable? {
        Logger.general.debug("WebNotificationsHandler: Permission request received")

        // For now, auto-grant permissions
        // Project 5 will implement the permission UI
        return RequestPermissionResponse(permission: "granted")
    }

    // MARK: - Event Sending (for native to JS communication)

    /// Sends a notification event to JavaScript.
    /// - Parameters:
    ///   - id: The notification ID
    ///   - event: The event type (show, close, click, error)
    ///   - webView: The webView to send the event to
    func sendNotificationEvent(id: String, event: String, to webView: WKWebView) {
        broker?.push(method: "notificationEvent", params: NotificationEventParams(id: id, event: event), for: self, into: webView)
    }

    struct NotificationEventParams: Encodable {
        let id: String
        let event: String
    }
}

