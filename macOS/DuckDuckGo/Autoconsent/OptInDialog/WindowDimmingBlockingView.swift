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

/// A full-window dimming + mouse-blocking backdrop for modal-style overlays.
///
/// This reuses the event-blocking behaviour of `MouseBlockingBackgroundView` (a local event monitor that
/// intercepts mouse/scroll events and manually forwards them only to its own subviews, so nothing reaches
/// the views behind — like a web view). The one difference: it resolves "am I the top-most view here?"
/// against its own `superview` instead of the window's `contentView`. That lets it be mounted on the
/// window's frame view (`contentView.superview`), above the titlebar, so the dim and the blocking cover the
/// WHOLE window — titlebar / tab bar included — which a contentView-bound view can't do.
///
/// Set `backgroundColor` for the dim. Place interactive content (e.g. a dialog card) as a sibling above
/// this view so it receives events normally.
final class WindowDimmingBlockingView: ColorView {
    private var localMonitor: Any?

    /// Height (from the top edge) of a region where a left mouse-down starts a window drag instead of being
    /// blocked — so the window stays movable by its titlebar while the overlay is shown. 0 disables it.
    var topDraggableHeight: CGFloat = 0

    /// When true, the window's `.resizable` style is removed while this view is in its window and restored
    /// when it leaves — so the window can't be resized behind the overlay. Set before adding to the window.
    var locksWindowResizing: Bool = false

    private weak var lockedResizableWindow: NSWindow?

    init() {
        super.init(frame: .zero, backgroundColor: nil, cornerRadius: 0, borderColor: nil, borderWidth: 0, interceptClickEvents: false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        stopListening()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            startListening()
        } else {
            stopListening()
        }
    }

    /// Starts listening to mouse events. Called automatically when the view enters a window.
    func startListening() {
        guard localMonitor == nil else { return }

        if locksWindowResizing, let window, window.styleMask.contains(.resizable) {
            window.styleMask.remove(.resizable)
            lockedResizableWindow = window
        }

        // A LOCAL monitor intercepts ALL mouse events and manually dispatches to our subviews, so events
        // never reach the views behind us (e.g. the web view / toolbar / tab bar).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]) { [weak self] event -> NSEvent? in
            guard let self = self else { return event }

            guard !self.isHidden else { return event }

            guard let window = self.window, event.window === window, window.isKeyWindow || window.isMainWindow else { return event }
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)

            guard self.bounds.contains(locationInView) else { return event }

            // Top strip: a left mouse-down starts a window drag (so the window stays movable by its titlebar)
            // while the click itself is still consumed — a plain click moves nothing and doesn't reach the
            // tab bar, a drag moves the window.
            if event.type == .leftMouseDown, self.topDraggableHeight > 0,
               locationInView.y > self.bounds.height - self.topDraggableHeight {
                window.performDrag(with: event)
                return nil
            }

            // Resolve the top-most view against our SUPERVIEW (the window frame view when mounted there),
            // not the contentView — this is what lets the overlay span the whole window. If something
            // legitimately sits above us (e.g. the dialog card, a sibling), let the event flow normally.
            if let root = self.superview {
                let locationInRoot = root.convert(locationInWindow, from: nil)
                if let topHitView = root.hitTest(locationInRoot), topHitView != self, !topHitView.isDescendant(of: self) {
                    return event
                }
            }

            let hitView = self.hitTest(locationInView)

            if let hitView = hitView, hitView != self {
                switch event.type {
                case .leftMouseDown:
                    if hitView.acceptsFirstResponder {
                        window.makeFirstResponder(hitView)
                    }
                    hitView.mouseDown(with: event)
                case .leftMouseUp:
                    hitView.mouseUp(with: event)
                case .rightMouseDown:
                    hitView.rightMouseDown(with: event)
                case .rightMouseUp:
                    hitView.rightMouseUp(with: event)
                case .otherMouseDown:
                    hitView.otherMouseDown(with: event)
                case .otherMouseUp:
                    hitView.otherMouseUp(with: event)
                case .mouseMoved:
                    hitView.mouseMoved(with: event)
                case .leftMouseDragged:
                    hitView.mouseDragged(with: event)
                case .rightMouseDragged:
                    hitView.rightMouseDragged(with: event)
                case .otherMouseDragged:
                    hitView.otherMouseDragged(with: event)
                case .scrollWheel:
                    hitView.scrollWheel(with: event)
                default:
                    break
                }
            }

            return nil
        }
    }

    /// Stops listening to mouse events. Called automatically when the view leaves its window.
    func stopListening() {
        if let lockedResizableWindow {
            lockedResizableWindow.styleMask.insert(.resizable)
            self.lockedResizableWindow = nil
        }

        guard let monitor = localMonitor else { return }
        NSEvent.removeMonitor(monitor)
        localMonitor = nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }

        // Iterate subviews front to back so the dialog's own controls claim their hits.
        for subview in subviews.reversed() where !subview.isHidden {
            if subview.frame.contains(point) {
                if let hitView = subview.hitTest(point) {
                    return hitView
                }
            }
        }

        return self
    }
}
