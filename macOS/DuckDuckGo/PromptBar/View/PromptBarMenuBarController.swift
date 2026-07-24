//
//  PromptBarMenuBarController.swift
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
import DesignResourcesKitIcons

/// The part of `NSStatusItem` this controller drives, so tests can substitute a
/// detached item instead of installing one in the system menu bar.
@MainActor
protocol PromptBarStatusItem: AnyObject {
    var button: NSStatusBarButton? { get }
    var isVisible: Bool { get set }
}

extension NSStatusItem: PromptBarStatusItem {}

/// Manages the Prompt Bar's duck.ai icon in the macOS menu bar.
@MainActor
final class PromptBarMenuBarController: NSObject {

    private let statusItem: PromptBarStatusItem

    /// - Parameter statusItem: Injectable for testing; defaults to a real menu bar item.
    init(statusItem: PromptBarStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)) {
        self.statusItem = statusItem
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = DesignSystemImages.Glyphs.Size16.duckAi
        button.image?.isTemplate = true
        button.setAccessibilityIdentifier("PromptBar.menuBarIcon")
        button.target = self
        button.action = #selector(statusBarButtonTapped)
    }

    @objc
    private func statusBarButtonTapped() {
        // No-op for now: this milestone only places the icon. Opening the floating
        // Prompt Bar window is wired here in a later milestone.
    }

    func show() {
        statusItem.isVisible = true
    }

    func hide() {
        statusItem.isVisible = false
    }
}
