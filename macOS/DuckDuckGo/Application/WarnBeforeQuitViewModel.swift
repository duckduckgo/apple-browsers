//
//  WarnBeforeQuitViewModel.swift
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

import AppKit
import Combine
import Foundation

enum ConfirmationAction {
    case quit
    case closePinnedTab
    case closeTabWithFloatingAIChat

    var shortcutText: String {
        switch self {
        case .quit: return "⌘Q"
        case .closePinnedTab: return "⌘W"
        case .closeTabWithFloatingAIChat: return "⌘W"
        }
    }
}

enum WarnBeforeButtonRole: Hashable {
    case dontShowAgain
    case closeTab
    case dismiss
}

enum ProgressState: Equatable {
    case idle                           // 0%, no animation
    case animating(duration: TimeInterval, targetValue: CGFloat = 1.0)  // animating to targetValue with specified duration
    case complete                       // 100%, no animation
    case resetting                      // animating back to 0% with spring

    var targetProgress: CGFloat {
        switch self {
        case .idle, .resetting: return 0
        case .animating(_, targetValue: let targetValue): return targetValue
        case .complete: return 1.0
        }
    }
}

@MainActor
final class WarnBeforeQuitViewModel: ObservableObject {

    @Published private(set) var progressState: ProgressState = .idle
    @Published var balloonAnchorPosition: CGPoint = .zero
    @Published var shouldHide: Bool = false
    let action: ConfirmationAction
    private let startupPreferences: StartupPreferences?
    private let buttonHandlers: [WarnBeforeButtonRole: () -> Void]

    var onHoverChange: ((Bool) -> Void)?

    private var usesFloatingCloseLayout: Bool {
        action == .closeTabWithFloatingAIChat && (buttonHandlers[.closeTab] != nil || buttonHandlers[.dismiss] != nil)
    }

    var shouldShowShortcutIndicator: Bool {
        !usesFloatingCloseLayout
    }

    var actionText: String {
        switch action {
        case .quit:
            return UserText.confirmQuitAction
        case .closePinnedTab:
            return UserText.confirmCloseAction
        case .closeTabWithFloatingAIChat:
            return usesFloatingCloseLayout ? UserText.aiChatFloatingCloseWarningTitle : UserText.aiChatFloatingCloseConfirmationAction
        }
    }

    var shortcutText: String {
        action.shortcutText
    }

    var subtitleText: String? {
        switch action {
        case .quit:
            return startupPreferences?.restorePreviousSession == true ? UserText.confirmQuitSubtitle : nil
        case .closePinnedTab:
            return nil
        case .closeTabWithFloatingAIChat:
            return UserText.aiChatFloatingCloseWarningSubtitle
        }
    }

    var isFloatingChatCloseAction: Bool {
        usesFloatingCloseLayout
    }

    init(action: ConfirmationAction = .quit,
         startupPreferences: StartupPreferences? = nil,
         buttonHandlers: [WarnBeforeButtonRole: () -> Void] = [:],
         onHoverChange: ((Bool) -> Void)? = nil) {
        self.action = action
        self.startupPreferences = startupPreferences
        self.buttonHandlers = buttonHandlers
        self.onHoverChange = onHoverChange
    }

    func startProgress(duration: TimeInterval = 0.6, targetValue: CGFloat = 1.0) {
        progressState = .animating(duration: duration, targetValue: targetValue)
    }

    func completeProgress() {
        progressState = .complete
    }

    func resetProgress() {
        progressState = .resetting
    }

    func dontAskAgainTapped() {
        buttonHandlers[.dontShowAgain]?()
    }

    func triggerButton(_ role: WarnBeforeButtonRole) {
        buttonHandlers[role]?()
    }

    func shouldShowButton(_ role: WarnBeforeButtonRole) -> Bool {
        buttonHandlers[role] != nil
    }

    func hoverChanged(_ isHovering: Bool) {
        onHoverChange?(isHovering)
    }

    func transitionToIdle() {
        progressState = .idle
    }
}
