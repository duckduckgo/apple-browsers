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
    case close

    var shortcutText: String {
        switch self {
        case .quit: return "⌘Q"
        case .close: return "⌘W"
        }
    }

    var actionText: String {
        switch self {
        case .quit: return UserText.confirmQuitAction
        case .close: return UserText.confirmCloseAction
        }
    }
}

@MainActor
final class WarnBeforeQuitViewModel: ObservableObject {

    @Published private(set) var progress: CGFloat = 0
    let action: ConfirmationAction
    private let startupPreferences: StartupPreferences?

    var onDontAskAgain: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    var subtitleText: String? {
        // For quit action, only show "Tabs will be restored" subtitle if restore tabs is enabled
        // For close action, no subtitle
        switch action {
        case .quit:
            return startupPreferences?.restorePreviousSession == true ? UserText.confirmQuitSubtitle : nil
        case .close:
            return nil
        }
    }

    init(action: ConfirmationAction = .quit, startupPreferences: StartupPreferences? = nil) {
        self.action = action
        self.startupPreferences = startupPreferences
    }

    func updateProgress(_ newProgress: CGFloat) {
        progress = min(1.0, max(0, newProgress))
    }

    func resetProgress() {
        progress = 0
    }

    func dontAskAgainTapped() {
        onDontAskAgain?()
    }

    func hoverChanged(_ isHovering: Bool) {
        onHoverChange?(isHovering)
    }
}
