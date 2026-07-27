//
//  PromptBarWindow.swift
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

/// An `NSPanel` so it never becomes the app's main window and stays out of the Window menu.
final class PromptBarWindow: NSPanel {

    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        setUpWindow()
    }

    private func setUpWindow() {
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        animationBehavior = .utilityWindow

        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        isExcludedFromWindowsMenu = true
        isMovableByWindowBackground = false

        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // The presenter owns dismissal, so that it can suppress it.
        hidesOnDeactivate = false
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
