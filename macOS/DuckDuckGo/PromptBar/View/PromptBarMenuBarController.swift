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

    private let makeStatusItem: @MainActor () -> PromptBarStatusItem
    private var statusItem: PromptBarStatusItem?

    var onClick: (() -> Void)?

    /// - Parameter makeStatusItem: Injectable for testing; defaults to a real menu bar item.
    init(makeStatusItem: @escaping @MainActor () -> PromptBarStatusItem = { NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }) {
        self.makeStatusItem = makeStatusItem
        super.init()
    }

    private func configureStatusItem(_ statusItem: PromptBarStatusItem) {
        guard let button = statusItem.button else { return }

        button.image = DesignSystemImages.Glyphs.Size16.duckAi
        button.image?.isTemplate = true
        button.setAccessibilityIdentifier("PromptBar.menuBarIcon")
        button.target = self
        button.action = #selector(statusBarButtonTapped)
    }

    @objc
    private func statusBarButtonTapped() {
        onClick?()
    }

    /// The item is created on first show: `NSStatusBar` puts it on screen as soon
    /// as it exists, so it must not be created while the icon should be hidden.
    func show() {
        if statusItem == nil {
            let statusItem = makeStatusItem()
            self.statusItem = statusItem
            configureStatusItem(statusItem)
        }
        statusItem?.isVisible = true
    }

    func hide() {
        statusItem?.isVisible = false
    }
}
