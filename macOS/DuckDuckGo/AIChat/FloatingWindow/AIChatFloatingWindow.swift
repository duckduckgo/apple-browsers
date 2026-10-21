//
//  AIChatFloatingWindow.swift
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

/// A standard macOS window used to display a detached AI Chat sidebar.
///
/// Uses `NSWindow` (not `NSPanel`) so it participates fully in Mission Control,
/// Stage Manager, Exposé, and the macOS Window menu. The native title bar is kept
/// for OS integration but rendered transparent while preserving standard traffic lights.
/// The content view controller draws a custom header.
final class AIChatFloatingWindow: NSWindow {

    private enum Constants {
        static let defaultWidth: CGFloat = 400
        static let defaultHeight: CGFloat = 600
        static let minWidth: CGFloat = 320
        static let minHeight: CGFloat = 505
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect? = nil) {
        let frame = contentRect ?? NSRect(
            x: 0,
            y: 0,
            width: Constants.defaultWidth,
            height: Constants.defaultHeight)

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true)

        setupWindow()
    }

    private func setupWindow() {
        isReleasedWhenClosed = false
        animationBehavior = .documentWindow
        hasShadow = true

        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        isMovableByWindowBackground = true

        title = UserText.aiChatSidebarTitle

        collectionBehavior = [.fullScreenNone]
        minSize = NSSize(width: Constants.minWidth, height: Constants.minHeight)

        backgroundColor = .windowBackgroundColor

        toolbar = NSToolbar()
        toolbar?.showsBaselineSeparator = true
        toolbarStyle = .unifiedCompact
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandW = event.type == .keyDown &&
            modifiers == .command &&
            event.charactersIgnoringModifiers?.lowercased() == "w"

        if isCommandW {
            close()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
