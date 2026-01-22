//
//  AIChatHistoryManager.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import UIKit
import SwiftUI

/// Protocol for handling AI chat history events
protocol AIChatHistoryManagerDelegate: AnyObject {
    func aiChatHistoryManager(_ manager: AIChatHistoryManager, didSelectChat chat: AIChatHistoryItem)
}

/// Manages the AI Chat history list installation and interaction
final class AIChatHistoryManager {

    // MARK: - Properties

    weak var delegate: AIChatHistoryManagerDelegate?

    private var hostingController: UIHostingController<AIChatHistoryListView>?

    /// Mock data - will be replaced with real API integration
    private let pinnedChats: [AIChatHistoryItem] = AIChatHistoryItem.mockPinnedChats
    private let recentChats: [AIChatHistoryItem] = AIChatHistoryItem.mockRecentChats

    // MARK: - Public Methods

    /// Installs the chat history list in the provided container view
    /// - Parameters:
    ///   - containerView: The view to install the chat history list into
    ///   - parentViewController: The parent view controller for the hosting controller
    func installInContainerView(_ containerView: UIView, parentViewController: UIViewController) {
        guard hostingController == nil else { return }

        let historyView = AIChatHistoryListView(
            pinnedChats: pinnedChats,
            recentChats: recentChats,
            onChatSelected: { [weak self] chat in
                guard let self else { return }
                self.delegate?.aiChatHistoryManager(self, didSelectChat: chat)
            }
        )

        let hostingController = UIHostingController(rootView: historyView)
        hostingController.view.backgroundColor = .clear

        parentViewController.addChild(hostingController)
        containerView.addSubview(hostingController.view)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor)
        ])

        hostingController.didMove(toParent: parentViewController)
        self.hostingController = hostingController
    }
}
