//
//  DuckAIResponseNotificationTabExtension.swift
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
import Combine
import ConcurrencyExtensions
import DuckAiDataStore
import os.log
import WebKit

/// Posts a system notification when a Duck.ai response finishes in this tab while the chat isn't
/// in front of the user.
final class DuckAIResponseNotificationTabExtension {

    private let tabID: String
    private let isLoadedInSidebar: Bool
    private let presenter: DuckAIResponseNotificationPresenting
    private var detector = DuckAIResponseCompletionDetector()
    private weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()

    init(tabID: String,
         isLoadedInSidebar: Bool,
         nativeStorageUserScriptPublisher: some Publisher<DuckAiNativeStorageUserScript?, Never>,
         webViewPublisher: some Publisher<WKWebView, Never>,
         presenter: DuckAIResponseNotificationPresenting) {
        self.tabID = tabID
        self.isLoadedInSidebar = isLoadedInSidebar
        self.presenter = presenter

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }.store(in: &cancellables)

        nativeStorageUserScriptPublisher
            .compactMap { $0?.chatWritesPublisher }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] record in
                MainActor.assumeMainThread {
                    self?.handleChatWrite(record)
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func handleChatWrite(_ record: DuckAiChatRecord) {
        guard let lastMessage = try? DuckAiChatLastMessage.decode(from: record.data),
              detector.isFinishedResponse(chatID: record.chatId, lastMessage: lastMessage),
              !isChatInFrontOfUser else { return }

        Logger.aiChat.debug("Duck.ai response finished off screen, posting notification")
        presenter.presentResponseNotification(tabID: tabID,
                                              isLoadedInSidebar: isLoadedInSidebar,
                                              chatID: record.chatId,
                                              lastMessage: lastMessage)
    }

    /// Unselected tabs have their web view taken out of the window, and a collapsed sidebar
    /// keeps it with an empty visible area.
    @MainActor
    private var isChatInFrontOfUser: Bool {
        guard NSApp.isActive,
              let webView,
              webView.window?.isKeyWindow == true,
              !webView.isHiddenOrHasHiddenAncestor else { return false }
        return !webView.visibleRect.isEmpty
    }
}

extension DuckAIResponseNotificationTabExtension: TabExtension {
    func getPublicProtocol() -> DuckAIResponseNotificationTabExtension { self }
}
