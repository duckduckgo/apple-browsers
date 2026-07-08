//
//  WindowDimmingBlockingView.swift
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

import Cocoa

/// A full-window dimming + mouse-blocking backdrop for modal-style overlays. Mounted on the window frame
/// view so it covers the titlebar / tab bar too; place interactive content (e.g. a dialog card) as a
/// sibling above it. Set `backgroundColor` for the dim.
final class WindowDimmingBlockingView: MouseEventInterceptingView {

    /// Height (from the top edge) where a left mouse-down starts a window drag instead of being blocked. 0 disables it.
    var topDraggableHeight: CGFloat = 0

    /// When true, the window's `.resizable` style is removed while shown and restored on leaving.
    var locksWindowResizing: Bool = false

    private weak var lockedResizableWindow: NSWindow?

    // Mounted on the frame view, so resolve the top-most hit against our superview, not the contentView.
    override var eventResolutionRootView: NSView? { superview }

    override func handleSpecialRegion(_ event: NSEvent, at locationInView: NSPoint, in window: NSWindow) -> Bool {
        // Left mouse-down in the top strip drags the window and consumes the click.
        guard event.type == .leftMouseDown, topDraggableHeight > 0,
              locationInView.y > bounds.height - topDraggableHeight else { return false }
        window.performDrag(with: event)
        return true
    }

    override func didStartListening() {
        guard locksWindowResizing, let window, window.styleMask.contains(.resizable) else { return }
        window.styleMask.remove(.resizable)
        lockedResizableWindow = window
    }

    override func willStopListening() {
        guard let lockedResizableWindow else { return }
        lockedResizableWindow.styleMask.insert(.resizable)
        self.lockedResizableWindow = nil
    }
}
