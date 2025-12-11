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

import BrowserServicesKit
import Common
import FeatureFlags
import Foundation
import OSLog
import UserNotifications
import UserScript
import WebKit

// MARK: - Protocols for Testability

/// Abstraction for `UNUserNotificationCenter` operations, enabling dependency injection and testing.
protocol WebNotificationService {

    /// Requests authorization to display notifications.
    /// - Parameter options: The notification options to request.
    /// - Returns: `true` if authorization was granted.
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool

    /// Returns the current notification authorization status.
    func authorizationStatus() async -> UNAuthorizationStatus

    /// Schedules a notification request.
    /// - Parameter request: The notification request to schedule.
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: WebNotificationService {}

// MARK: - WebNotificationsHandler

/// Bridges the JavaScript `Notification` API polyfill to native macOS notifications.
///
/// This handler receives messages from ContentScopeScripts' webNotifications feature and
/// translates them into `UNUserNotificationCenter` calls. Permission decisions are stored
/// via `PermissionManager` and cleared on burn for Fire Windows.
final class WebNotificationsHandler: NSObject, Subfeature {

    let messageOriginPolicy: MessageOriginPolicy = .all
    let featureName: String = "webCompat"

    weak var broker: UserScriptMessageBroker?

    // MARK: - Dependencies

    private let tabUUID: String
    private let notificationService: WebNotificationService
    private let iconFetcher: NotificationIconFetching
    private let featureFlagger: FeatureFlagger
    private let permissionManager: PermissionManagerProtocol

    /// The webView associated with this handler's tab, set by `WebNotificationsTabExtension`.
    weak var webView: WKWebView?

    private var isWebNotificationsEnabled: Bool {
        featureFlagger.isFeatureOn(.webNotifications)
    }

    // MARK: - Initialization

    init(tabUUID: String,
         notificationService: WebNotificationService = UNUserNotificationCenter.current(),
         iconFetcher: NotificationIconFetching = NotificationIconFetcher(),
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         permissionManager: PermissionManagerProtocol = NSApp.delegateTyped.permissionManager) {
        self.tabUUID = tabUUID
        self.notificationService = notificationService
        self.iconFetcher = iconFetcher
        self.featureFlagger = featureFlagger
        self.permissionManager = permissionManager
        super.init()
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    // MARK: - Subfeature Handler

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .showNotification:
            return { [weak self] params, original in
                await self?.handleShowNotification(params: params, original: original)
                return nil
            }
        case .closeNotification:
            return { [weak self] params, original in
                self?.handleCloseNotification(params: params, original: original)
                return nil
            }
        case .requestPermission:
            return { [weak self] params, original in
                return await self?.handleRequestPermission(params: params, original: original)
            }
        default:
            return nil
        }
    }

    // MARK: - Domain Extraction

    /// Extracts the domain from the webView's URL for permission storage.
    @MainActor
    private func domain(from webView: WKWebView?) -> String? {
        webView?.url?.host
    }

    /// Returns true if the domain has a stored denial for notifications.
    @MainActor
    private func isDomainDenied(for webView: WKWebView?) -> Bool {
        guard let domain = domain(from: webView) else { return false }
        return permissionManager.permission(forDomain: domain, permissionType: .notification) == .deny
    }

    // MARK: - System Authorization

    /// Checks if system notification authorization is granted (without prompting).
    /// - Returns: `true` if already authorized, `false` otherwise.
    private func isSystemAuthorized() async -> Bool {
        let status = await notificationService.authorizationStatus()
        return status == .authorized || status == .provisional
    }

    /// Checks system notification authorization, requesting permission if not yet determined.
    /// - Returns: `true` if authorized to show notifications, `false` otherwise.
    private func ensureSystemAuthorization() async -> Bool {
        let status = await notificationService.authorizationStatus()

        switch status {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                return try await notificationService.requestAuthorization(options: [.alert, .sound])
            } catch {
                Logger.general.error("WebNotificationsHandler: Authorization failed - \(error.localizedDescription)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Notification Content Building

    /// Builds notification content from a JavaScript payload.
    /// - Parameters:
    ///   - payload: The notification data from JavaScript.
    ///   - originURL: The URL of the page requesting the notification.
    /// - Returns: Configured notification content with optional icon attachment.
    private func buildNotificationContent(
        from payload: ShowNotificationPayload,
        originURL: String
    ) async -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body ?? ""
        content.sound = .default
        content.userInfo = [
            UserInfoKey.notificationId: payload.id,
            UserInfoKey.originURL: originURL,
            UserInfoKey.tabUUID: tabUUID
        ]

        if let tag = payload.tag {
            content.threadIdentifier = tag
        }

        if let iconURLString = payload.icon, let iconURL = URL(string: iconURLString) {
            if let attachment = await iconFetcher.fetchIcon(from: iconURL) {
                content.attachments = [attachment]
            }
        }

        return content
    }

    // MARK: - Notification Posting

    /// Posts a notification to the system and dispatches the corresponding JavaScript event.
    /// - Parameters:
    ///   - id: The notification identifier.
    ///   - content: The notification content to display.
    ///   - webView: The web view to receive the `onshow` or `onerror` event.
    private func postNotification(
        id: String,
        content: UNNotificationContent,
        webView: WKWebView?
    ) async {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)

        do {
            try await notificationService.add(request)
            Logger.general.debug("WebNotificationsHandler: Notification posted (ID: \(id))")
            sendShowEvent(id: id, to: webView)
        } catch {
            Logger.general.error("WebNotificationsHandler: Failed to post - \(error.localizedDescription)")
            sendErrorEvent(id: id, to: webView)
        }
    }

    // MARK: - Message Handlers

    private func handleShowNotification(params: Any, original: WKScriptMessage) async {
        guard let payload: ShowNotificationPayload = DecodableHelper.decode(from: params) else {
            Logger.general.error("WebNotificationsHandler: Invalid showNotification payload")
            return
        }

        // Block notifications from iframes to prevent content spoofing attacks
        guard original.frameInfo.isMainFrame else {
            Logger.general.debug("WebNotificationsHandler: Blocked notification from iframe (ID: \(payload.id))")
            sendErrorEvent(id: payload.id, to: original.webView)
            return
        }

        guard isWebNotificationsEnabled else {
            Logger.general.debug("WebNotificationsHandler: Blocked - feature flag disabled (ID: \(payload.id))")
            sendErrorEvent(id: payload.id, to: original.webView)
            return
        }

        // Check stored permission (Fire Windows use same storage, cleared on burn)
        if await isDomainDenied(for: original.webView) {
            Logger.general.debug("WebNotificationsHandler: Blocked - stored denial (ID: \(payload.id))")
            sendErrorEvent(id: payload.id, to: original.webView)
            return
        }

        guard await isSystemAuthorized() else {
            Logger.general.debug("WebNotificationsHandler: Blocked - not authorized (ID: \(payload.id))")
            sendErrorEvent(id: payload.id, to: original.webView)
            return
        }

        let originURL = await original.webView?.url?.absoluteString ?? ""
        let content = await buildNotificationContent(from: payload, originURL: originURL)
        await postNotification(id: payload.id, content: content, webView: original.webView)
    }

    private func handleCloseNotification(params: Any, original: WKScriptMessage) {
        guard let payload: CloseNotificationPayload = DecodableHelper.decode(from: params) else {
            Logger.general.error("WebNotificationsHandler: Invalid closeNotification payload")
            return
        }

        guard isWebNotificationsEnabled else {
            Logger.general.debug("WebNotificationsHandler: Close blocked - feature flag disabled (ID: \(payload.id))")
            return
        }

        Logger.general.debug("WebNotificationsHandler: Notification close requested (ID: \(payload.id))")
    }

    private func handleRequestPermission(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.general.debug("WebNotificationsHandler: Permission request received")

        // Block permission requests from iframes to prevent spoofing
        guard original.frameInfo.isMainFrame else {
            Logger.general.debug("WebNotificationsHandler: Permission denied from iframe")
            return RequestPermissionResponse(permission: Permission.denied.rawValue)
        }

        guard isWebNotificationsEnabled else {
            Logger.general.debug("WebNotificationsHandler: Permission denied - feature flag disabled")
            return RequestPermissionResponse(permission: Permission.denied.rawValue)
        }

        // Check stored permission (Fire Windows use same storage, cleared on burn)
        if await isDomainDenied(for: original.webView) {
            Logger.general.debug("WebNotificationsHandler: Permission denied - stored decision")
            return RequestPermissionResponse(permission: Permission.denied.rawValue)
        }

        // Check/request system authorization
        let authorized = await ensureSystemAuthorization()

        // Store the decision (Fire Windows cleared on burn via burnPermissions())
        if authorized, let domain = await domain(from: original.webView) {
            permissionManager.setPermission(.allow, forDomain: domain, permissionType: .notification)
            Logger.general.debug("WebNotificationsHandler: Stored allow permission for \(domain)")
        }

        let permission = authorized ? Permission.granted : Permission.denied
        return RequestPermissionResponse(permission: permission.rawValue)
    }

    // MARK: - Event Sending (for native to JS communication)

    /// Sends a notification event to JavaScript.
    /// - Parameters:
    ///   - id: The notification ID
    ///   - event: The event type (show, close, click, error)
    ///   - webView: The webView to send the event to
    func sendNotificationEvent(id: String, event: NotificationEvent, to webView: WKWebView?) {
        guard let webView = webView else { return }
        broker?.push(method: MethodName.notificationEvent, params: NotificationEventParams(id: id, event: event.rawValue), for: self, into: webView)
    }

    private func sendShowEvent(id: String, to webView: WKWebView?) {
        sendNotificationEvent(id: id, event: .show, to: webView)
    }

    private func sendErrorEvent(id: String, to webView: WKWebView?) {
        sendNotificationEvent(id: id, event: .error, to: webView)
    }

    /// Dispatches a click event to JavaScript for the given notification.
    /// Called by `WebNotificationsTabExtension` when a notification is clicked.
    /// - Parameter notificationId: The ID of the notification that was clicked.
    func sendClickEvent(notificationId: String) {
        Logger.general.debug("WebNotificationsHandler: Click event for notification (ID: \(notificationId))")
        sendNotificationEvent(id: notificationId, event: .click, to: webView)
    }
}

// MARK: - Nested Types

extension WebNotificationsHandler {

    enum MessageNames: String, CaseIterable {
        case showNotification
        case closeNotification
        case requestPermission
    }

    enum Permission: String {
        case granted
        case denied
    }

    enum NotificationEvent: String {
        case show
        case error
        case click
        case close
    }

    enum UserInfoKey {
        static let notificationId = "notificationId"
        static let originURL = "originURL"
        static let tabUUID = "tabUUID"
    }

    enum MethodName {
        static let notificationEvent = "notificationEvent"
    }

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

    struct NotificationEventParams: Encodable {
        let id: String
        let event: String
    }
}
