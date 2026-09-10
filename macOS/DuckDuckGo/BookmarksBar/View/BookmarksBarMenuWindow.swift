//
//  BookmarksBarMenuWindow.swift
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

/// Borderless panel that hosts `BookmarksBarMenuCustomPopover` content. Used in place of
/// `NSPopover` so the visible shape (corner radius, border, shadow) is fully under
/// our control on macOS 26+, where the popover chrome is rendered by an `NSGlassView`
/// that can't be clipped from outside. The shape and material backdrop live in the
/// hosted view controller; this window only manages chromeless presentation.
final class BookmarksBarMenuWindow: NSPanel {

    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .popUpMenu
        animationBehavior = .none
        hidesOnDeactivate = true
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.transient, .ignoresCycle]
    }
}
