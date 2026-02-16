//
//  MouseBlockingBackgroundView.swift
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

import Cocoa

/// A view that aggressively blocks ALL mouse events from reaching views behind it.
/// Uses a local event monitor to intercept events and manually forwards them to subviews.
/// This prevents events from ever reaching views behind this one (like a webview).
final class MouseBlockingBackgroundView: ColorView {
    private var localMonitor: Any?

    /// Height from bottom of view that should pass events through (not intercept).
    /// Used to allow clicks to reach views behind this one in a specific region.
    var passthroughBottomHeight: CGFloat = 0

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

    /// Starts listening to mouse events. Call this when the view becomes visible.
    func startListening() {
        guard localMonitor == nil else { return }
        setupEventBlocking()
    }

    /// Stops listening to mouse events. Call this when the view is no longer visible.
    func stopListening() {
        guard let monitor = localMonitor else { return }
        NSEvent.removeMonitor(monitor)
        localMonitor = nil
    }

    private func setupEventBlocking() {
        // Use a LOCAL monitor to intercept ALL events and manually dispatch to our subviews
        // This prevents events from reaching the webview behind us
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]) { [weak self] event -> NSEvent? in
            guard let self = self else { return event }

            guard !self.isHidden else { return event }

            guard let window = self.window, event.window === window, window.isKeyWindow || window.isMainWindow else { return event }
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)

            guard self.bounds.contains(locationInView) else { return event }

            // Check if click is in passthrough region (bottom of view)
            // In AppKit, y=0 is at the bottom, so we check if y < passthroughBottomHeight
            if self.passthroughBottomHeight > 0 && locationInView.y < self.passthroughBottomHeight {
                return event
            }

            if let contentView = window.contentView {
                let locationInContentView = contentView.convert(locationInWindow, from: nil)
                if let topHitView = contentView.hitTest(locationInContentView) {
                    if topHitView != self && !topHitView.isDescendant(of: self) {
                        return event
                    }
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
    }

    override func mouseUp(with event: NSEvent) {
    }

    override func rightMouseDown(with event: NSEvent) {
    }

    override func rightMouseUp(with event: NSEvent) {
    }

    override func otherMouseDown(with event: NSEvent) {
    }

    override func otherMouseUp(with event: NSEvent) {
    }

    override func mouseMoved(with event: NSEvent) {
    }

    override func mouseDragged(with event: NSEvent) {
    }

    override func rightMouseDragged(with event: NSEvent) {
    }

    override func otherMouseDragged(with event: NSEvent) {
    }

    override func scrollWheel(with event: NSEvent) {
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Note: When called from our event monitor, point is already in our coordinate system.
        // When called normally (e.g., from contentView.hitTest), point is in superview's coords.
        // Since this view fills its superview at origin (0,0), both are equivalent.

        // Check if point is in passthrough region (bottom of view)
        // In AppKit, y=0 is at the bottom, so we check if y < passthroughBottomHeight
        if passthroughBottomHeight > 0 && point.y < passthroughBottomHeight {
            return nil
        }

        guard bounds.contains(point) else {
            return nil
        }

        // Iterate subviews in reverse order (front to back)
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
