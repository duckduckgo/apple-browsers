//
//  AIChatFloatingWindowController.swift
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

import AppKit
import Combine

@MainActor
protocol AIChatFloatingWindowControllerDelegate: AnyObject {
    /// The user closed the floating window (via close button or Escape).
    func floatingWindowDidClose(_ controller: AIChatFloatingWindowController, initiatedByUser: Bool)
}

/// Manages a single detached AI Chat floating window for one tab.
///
/// Each instance owns one `AIChatFloatingWindow` and the
/// `AIChatViewController` that was moved out of the docked sidebar.
@MainActor
final class AIChatFloatingWindowController: NSObject {
    /// Why the floating window is being closed.
    ///
    /// - user: Closed by explicit user action in the floating window.
    /// - attach: Closed because chat is being re-docked to the sidebar. Delegate callback is suppressed.
    /// - teardown: Closed while coordinator is already tearing down this tab session. Delegate callback is suppressed.
    /// - system: Closed programmatically by coordinator/session cleanup.
    enum CloseReason {
        case user
        case attach
        case teardown
        case system
    }

    typealias WindowFactory = (NSRect) -> NSWindow

    static var windowFactory: WindowFactory = { contentRect in
        AIChatFloatingWindow(contentRect: contentRect)
    }

    private enum Constants {
        static let windowTitleSeparator = "\u{30FB}"
    }

    weak var delegate: AIChatFloatingWindowControllerDelegate?
    var onFrameChanged: ((NSRect) -> Void)?

    /// The tab this floating window is associated with.
    let tabID: TabIdentifier

    private let floatingWindow: NSWindow
    private var chatViewController: AIChatViewController?
    private var closeReason: CloseReason = .user
    private var tabInfoCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    var isShowing: Bool {
        floatingWindow.isVisible
    }

    var frame: NSRect {
        floatingWindow.frame
    }

    init(tabID: TabIdentifier,
         chatViewController: AIChatViewController,
         tabViewModel: TabViewModel?,
         contentRect: NSRect) {
        self.tabID = tabID
        self.chatViewController = chatViewController
        self.floatingWindow = Self.windowFactory(contentRect)
        super.init()

        embedChatViewController(chatViewController)
        // Embedding an already-laid-out sidebar VC can make AppKit snap the window
        // back to the VC's previous docked size. Re-apply the requested floating frame.
        floatingWindow.setFrame(contentRect, display: false)
        subscribeToTabInfo(tabViewModel)

        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: floatingWindow)
            .sink { [weak self] _ in
                guard let self else { return }
                let closeReason = self.closeReason
                self.closeReason = .user

                switch closeReason {
                case .attach:
                    return
                case .teardown:
                    return
                case .user:
                    self.delegate?.floatingWindowDidClose(self, initiatedByUser: true)
                case .system:
                    self.delegate?.floatingWindowDidClose(self, initiatedByUser: false)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: floatingWindow)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: floatingWindow))
            .sink { [weak self] _ in
                guard let self else { return }
                self.onFrameChanged?(self.frame)
            }
            .store(in: &cancellables)
    }

    func show() {
        floatingWindow.makeKeyAndOrderFront(nil)
    }

    func close(reason: CloseReason = .user) {
        closeReason = reason
        floatingWindow.close()
    }

    func updateTabViewModel(_ tabViewModel: TabViewModel?) {
        subscribeToTabInfo(tabViewModel)
    }

    /// Removes the chat view controller from the floating window so it can be
    /// re-embedded in the docked sidebar. Returns `nil` if already detached.
    func detachChatViewController() -> AIChatViewController? {
        guard let vc = chatViewController else { return nil }
        floatingWindow.contentViewController = nil
        chatViewController = nil
        return vc
    }

    // MARK: - Private

    private func subscribeToTabInfo(_ tabViewModel: TabViewModel?) {
        tabInfoCancellable = nil
        guard let tabViewModel else { return }
        chatViewController?.updateFloatingTitle(tabViewModel.title, favicon: tabViewModel.favicon)
        floatingWindow.title = windowTitle(for: tabViewModel.title)

        tabInfoCancellable = tabViewModel.$title.combineLatest(tabViewModel.$favicon)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title, favicon in
                self?.chatViewController?.updateFloatingTitle(title, favicon: favicon)
                self?.floatingWindow.title = self?.windowTitle(for: title) ?? UserText.aiChatSidebarTitle
            }
    }

    private func windowTitle(for pageTitle: String) -> String {
        let trimmedPageTitle = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPageTitle.isEmpty else {
            return UserText.aiChatSidebarTitle
        }
        return "\(UserText.aiChatSidebarTitle)\(Constants.windowTitleSeparator)\(trimmedPageTitle)"
    }

    private func embedChatViewController(_ viewController: AIChatViewController) {
        floatingWindow.contentViewController = viewController
    }
}
