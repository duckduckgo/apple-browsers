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
/// Not `final`: the unit test target refuses to put real windows on screen, so presenter tests
/// substitute a subclass that stubs ordering — the same trick `MockWindow` plays on `NSWindow`.
internal class PromptBarWindow: NSPanel {

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

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown, event.clickCount == 1, isMovableByWindowBackground,
              let hitView = contentView?.hitTest(event.locationInWindow),
              hitView is NSTextView || hitView is NSClipView || hitView is NSScrollView else {
            super.sendEvent(event)
            return
        }
        dragOrClick(startingWith: event)
    }

    private func dragOrClick(startingWith mouseDown: NSEvent) {
        let dragThreshold: CGFloat = 3
        let startLocation = NSEvent.mouseLocation
        let startOrigin = frame.origin
        var isDragging = false

        while let event = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp {
                if !isDragging {
                    NSApp.postEvent(event, atStart: true)
                    super.sendEvent(mouseDown)
                }
                return
            }
            let location = NSEvent.mouseLocation
            let offset = CGPoint(x: location.x - startLocation.x, y: location.y - startLocation.y)
            if !isDragging, hypot(offset.x, offset.y) < dragThreshold { continue }
            isDragging = true
            setFrameOrigin(CGPoint(x: startOrigin.x + offset.x, y: startOrigin.y + offset.y))
        }
    }
}
