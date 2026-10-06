//
//  DuckAIResponseNotificationPresenter.swift
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

import AIChat
import AppKit
import DesignResourcesKitIcons
import os.log
import UserNotifications

@MainActor
protocol DuckAIResponseNotificationPresenting: AnyObject {
    func presentResponseNotification(tabID: String, isLoadedInSidebar: Bool, chatID: String, lastMessage: DuckAiChatLastMessage)
}

@MainActor
final class DuckAIResponseNotificationPresenter: DuckAIResponseNotificationPresenting {

    enum UserInfoKey {
        static let tabID = "duckAIResponseTabID"
        static let isLoadedInSidebar = "duckAIResponseIsLoadedInSidebar"
    }

    private enum Constants {
        static let maxPreviewLength = 300
    }

    static let shared = DuckAIResponseNotificationPresenter()

    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func presentResponseNotification(tabID: String, isLoadedInSidebar: Bool, chatID: String, lastMessage: DuckAiChatLastMessage) {
        // Internal-only proof of concept, so the copy isn't localized yet.
        let content = UNMutableNotificationContent()
        content.title = "Duck.ai"
        content.subtitle = lastMessage.chatTitle ?? ""
        content.body = lastMessage.text.flatMap(Self.preview(of:)) ?? "Your response is ready"
        content.sound = .default
        content.threadIdentifier = chatID
        content.userInfo = [UserInfoKey.tabID: tabID, UserInfoKey.isLoadedInSidebar: isLoadedInSidebar]
        if let iconAttachment = Self.makeIconAttachment() {
            content.attachments = [iconAttachment]
        }

        // One identifier per chat, so a newer answer replaces the older one in Notification Center.
        let request = UNNotificationRequest(identifier: "duckai-response-\(chatID)", content: content, trigger: nil)

        Task {
            guard await isAuthorized() else {
                Logger.aiChat.debug("Duck.ai response notification skipped: notifications not authorized")
                return
            }
            do {
                try await notificationCenter.add(request)
            } catch {
                Logger.aiChat.error("Duck.ai response notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func isAuthorized() async -> Bool {
        let status = await notificationCenter.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                return try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            } catch {
                // Unsigned or ad-hoc signed builds land here without the system ever asking the user.
                Logger.aiChat.error("Duck.ai response notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        default:
            Logger.aiChat.debug("Duck.ai response notification authorization status: \(status.rawValue, privacy: .public)")
            return false
        }
    }

    /// Notification Center shows plain text, so drop the Markdown and fold the answer onto one line.
    static func preview(of text: String) -> String? {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let plainText = (try? AttributedString(markdown: text, options: options)).map { String($0.characters) } ?? text

        let lines = plainText
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"^\s*(#{1,6}|>|[-*+]|\d+\.)\s+"#, with: "", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let preview = lines.joined(separator: " ")
        guard preview.count > Constants.maxPreviewLength else { return preview }
        return String(preview.prefix(Constants.maxPreviewLength - 1)) + "…"
    }

    /// The sender icon is always the app icon on macOS, so the Duck.ai icon goes in as a
    /// thumbnail attachment. The system moves the file into its own store, so each notification
    /// needs a fresh copy.
    private static func makeIconAttachment() -> UNNotificationAttachment? {
        let icon = DesignSystemImages.Color.Size96.duckAI
        guard let tiffData = icon.tiffRepresentation,
              let pngData = NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:]) else { return nil }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("duckai-notification-icon-\(UUID().uuidString).png")
        do {
            try pngData.write(to: fileURL)
            return try UNNotificationAttachment(identifier: "duckai-icon", url: fileURL)
        } catch {
            Logger.aiChat.error("Duck.ai notification icon attachment failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// Brings the chat that posted a response notification to the front.
final class DuckAIResponseNotificationClickHandler {

    private let tabFinder: WebNotificationTabFinding
    private let sessionStore: AIChatSessionStoring

    init(tabFinder: WebNotificationTabFinding, sessionStore: AIChatSessionStoring) {
        self.tabFinder = tabFinder
        self.sessionStore = sessionStore
    }

    @MainActor
    func handleClick(userInfo: [AnyHashable: Any]) -> Bool {
        typealias Key = DuckAIResponseNotificationPresenter.UserInfoKey
        guard let tabID = userInfo[Key.tabID] as? String else { return false }

        var tabToFocus = tabID
        if userInfo[Key.isLoadedInSidebar] as? Bool == true {
            // The sidebar chat runs in its own tab outside the tab bar, so focus the page tab it belongs to.
            guard let owner = sessionStore.sessions.first(where: { $0.value.chatViewController?.aiTabUUID == tabID }) else {
                tabFinder.focusBrowser()
                return true
            }
            if let floatingWindowController = owner.value.floatingWindowController {
                floatingWindowController.show()
                return true
            }
            tabToFocus = owner.key
        }

        if tabFinder.focusTab(byUUID: tabToFocus) == nil {
            tabFinder.focusBrowser()
        }
        return true
    }
}
