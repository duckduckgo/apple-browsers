//
//  MouseEventInterceptingView.swift
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

/// A `ColorView` that intercepts ALL mouse/scroll events via a local event monitor and manually forwards
/// them only to its own subviews, so nothing reaches the views behind it (web view, toolbar, tab bar, …).
///
/// Subclasses customise behaviour through the hooks below:
/// - `shouldPassThroughEvent(at:)` — a region where events fall through untouched (also excluded from hit-testing).
/// - `handleSpecialRegion(_:at:in:)` — a region handled specially and consumed (e.g. starting a window drag).
/// - `eventResolutionRootView` — the view the "is something legitimately above me?" check resolves against;
///   defaults to the window's `contentView`, override with `superview` when mounted on the window frame view.
/// - `didStartListening()` / `willStopListening()` — template hooks for extra setup/teardown (e.g. a resize lock).
internal class MouseEventInterceptingView: ColorView {

    private var localMonitor: Any?

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

    // MARK: - Monitor lifecycle

    func startListening() {
        guard localMonitor == nil else { return }

        // A LOCAL monitor intercepts ALL mouse events and manually dispatches to our subviews, so events
        // never reach the views behind us (e.g. the web view / toolbar / tab bar).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]) { [weak self] event -> NSEvent? in
            guard let self else { return event }
            return self.handleMonitoredEvent(event)
        }
        didStartListening()
    }

    func stopListening() {
        willStopListening()
        guard let localMonitor else { return }
        NSEvent.removeMonitor(localMonitor)
        self.localMonitor = nil
    }

    // MARK: - Overridable hooks

    /// A region (in this view's coordinates) where events pass through untouched and hit-testing is skipped.
    func shouldPassThroughEvent(at locationInView: NSPoint) -> Bool { false }

    /// A region handled specially and consumed; return `true` if the event was handled (e.g. a window drag started).
    func handleSpecialRegion(_ event: NSEvent, at locationInView: NSPoint, in window: NSWindow) -> Bool { false }

    /// The view the "is something legitimately above me?" check resolves against.
    var eventResolutionRootView: NSView? { window?.contentView }

    /// Called right after the event monitor is installed.
    func didStartListening() {}

    /// Called right before the event monitor is removed.
    func willStopListening() {}

    // MARK: - Event handling

    private func handleMonitoredEvent(_ event: NSEvent) -> NSEvent? {
        guard !isHidden else { return event }
        guard let window, event.window === window, window.isKeyWindow || window.isMainWindow else { return event }
        let locationInWindow = event.locationInWindow
        let locationInView = convert(locationInWindow, from: nil)
        guard bounds.contains(locationInView) else { return event }

        if shouldPassThroughEvent(at: locationInView) { return event }
        if handleSpecialRegion(event, at: locationInView, in: window) { return nil }

        // If a view legitimately sits above us, let the event flow to it normally.
        if let root = eventResolutionRootView {
            let locationInRoot = root.convert(locationInWindow, from: nil)
            if let topHitView = root.hitTest(locationInRoot), topHitView != self, !topHitView.isDescendant(of: self) {
                return event
            }
        }

        if let hitView = hitTest(locationInView), hitView != self {
            forward(event, to: hitView, in: window)
        }
        return nil
    }

    private func forward(_ event: NSEvent, to hitView: NSView, in window: NSWindow) {
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

    // MARK: - Blocking overrides

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        if shouldPassThroughEvent(at: point) { return nil }
        guard bounds.contains(point) else { return nil }
        // Front-to-back so a subview claims its own hit.
        for subview in subviews.reversed() where !subview.isHidden {
            if subview.frame.contains(point), let hitView = subview.hitTest(point) {
                return hitView
            }
        }
        return self
    }
}
