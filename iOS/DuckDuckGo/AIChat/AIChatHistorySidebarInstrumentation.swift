//
//  AIChatHistorySidebarInstrumentation.swift
//  DuckDuckGo
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

import PixelKit

/// Pixels for what only the iPad chat list sidebar does. Actions inside the list report through `AIChatHistoryInstrumentation`.
enum AIChatHistorySidebarPixel: PixelKit.Event {

    enum OpenSource: String {
        /// The floating Chats button shown while the sidebar is closed.
        case chatsButton = "chats_button"
        /// The Chats button beside the collapsed input, which replaces the floating one in narrow windows.
        case inputChatsButton = "input_chats_button"
        /// A Chats entry point (address bar menu, app menu, contextual "View all") that loads `sidebar=open`.
        case chatsEntryPoint = "chats_entry_point"
    }

    enum CloseSource: String {
        case closeButton = "close_button"
        case chatsButton = "chats_button"
        case inputChatsButton = "input_chats_button"
    }

    /// The buttons that toggle the sidebar.
    enum ChatsButton {
        case chatsButton
        case inputChatsButton

        var openSource: OpenSource {
            switch self {
            case .chatsButton: return .chatsButton
            case .inputChatsButton: return .inputChatsButton
            }
        }

        var closeSource: CloseSource {
            switch self {
            case .chatsButton: return .chatsButton
            case .inputChatsButton: return .inputChatsButton
            }
        }
    }

    enum Layout: String {
        /// A column over the chat's leading edge.
        case column
        /// Over the whole tab, in a window too narrow for the column.
        case overlay
    }

    enum MenuAction: String {
        case syncSettings = "sync_settings"
        case duckAISettings = "duckai_settings"
    }

    enum ChatOpenFallbackReason: String {
        case notFound = "not_found"
        case failed
        /// The page couldn't take the request or didn't answer in time.
        case noAnswer = "no_answer"

        /// `nil` for `.opened`, which needs no fallback.
        init?(outcome: AIChatOpenChatOutcome?) {
            switch outcome {
            case .opened: return nil
            case .notFound: self = .notFound
            case .failed: self = .failed
            case nil: self = .noAnswer
            }
        }
    }

    case opened(source: OpenSource, layout: Layout)
    case closed(source: CloseSource, layout: Layout)
    case newChatTapped
    case menuActionSelected(MenuAction)
    case chatOpenFallback(reason: ChatOpenFallbackReason)
    case openChatDeleted

    var name: String {
        switch self {
        case .opened: return "aichat_history_sidebar_opened"
        case .closed: return "aichat_history_sidebar_closed"
        case .newChatTapped: return "aichat_history_sidebar_new_chat_tapped"
        case .menuActionSelected: return "aichat_history_sidebar_menu_action"
        case .chatOpenFallback: return "aichat_history_sidebar_chat_open_fallback"
        case .openChatDeleted: return "aichat_history_sidebar_open_chat_deleted"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .opened(let source, let layout):
            return ["source": source.rawValue, "layout": layout.rawValue]
        case .closed(let source, let layout):
            return ["source": source.rawValue, "layout": layout.rawValue]
        case .menuActionSelected(let action):
            return ["action": action.rawValue]
        case .chatOpenFallback(let reason):
            return ["reason": reason.rawValue]
        case .newChatTapped, .openChatDeleted:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

protocol AIChatHistorySidebarInstrumentation {
    func sidebarOpened(source: AIChatHistorySidebarPixel.OpenSource, layout: AIChatHistorySidebarPixel.Layout)
    func sidebarClosed(source: AIChatHistorySidebarPixel.CloseSource, layout: AIChatHistorySidebarPixel.Layout)
    func floatingNewChatTapped()
    func menuActionSelected(_ action: AIChatHistorySidebarPixel.MenuAction)
    func chatOpenFellBack(outcome: AIChatOpenChatOutcome?)
    func openChatDeleted()
}

final class DefaultAIChatHistorySidebarInstrumentation: AIChatHistorySidebarInstrumentation {

    private let pixelFiring: PixelFiring?

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    func sidebarOpened(source: AIChatHistorySidebarPixel.OpenSource, layout: AIChatHistorySidebarPixel.Layout) {
        fire(.opened(source: source, layout: layout))
    }

    func sidebarClosed(source: AIChatHistorySidebarPixel.CloseSource, layout: AIChatHistorySidebarPixel.Layout) {
        fire(.closed(source: source, layout: layout))
    }

    func floatingNewChatTapped() {
        fire(.newChatTapped)
    }

    func menuActionSelected(_ action: AIChatHistorySidebarPixel.MenuAction) {
        fire(.menuActionSelected(action))
    }

    func chatOpenFellBack(outcome: AIChatOpenChatOutcome?) {
        guard let reason = AIChatHistorySidebarPixel.ChatOpenFallbackReason(outcome: outcome) else { return }
        fire(.chatOpenFallback(reason: reason))
    }

    func openChatDeleted() {
        fire(.openChatDeleted)
    }

    private func fire(_ pixel: AIChatHistorySidebarPixel) {
        pixelFiring?.fire(pixel, frequency: .dailyAndCount)
    }
}
