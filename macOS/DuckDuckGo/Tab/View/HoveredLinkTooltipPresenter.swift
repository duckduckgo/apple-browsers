//
//  HoveredLinkTooltipPresenter.swift
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

/// A passive child window lets the hovered URL move below the browser without covering links.
final class HoveredLinkTooltipPresenter {

    private weak var hostView: NSView?
    private let window: NSWindow
    private let label = NSTextField(labelWithString: "")
    private let schedule: (TimeInterval, @escaping () -> Void) -> DispatchWorkItem
    private let mouseLocation: () -> NSPoint
    private let trailingInset: () -> CGFloat
    private let currentHoveredURL: () -> URL?
    private let animate: (NSWindow, CGFloat, TimeInterval, @escaping () -> Void) -> Void
    private let move: (NSWindow, NSRect, TimeInterval) -> Void
    private var targetFrame: NSRect?
    private var hoveredURL: URL?
    private var isMouseInside = true
    private var hasShownTooltip = false
    private var isFadingOut = false
    private var shouldRestoreOnNextMove = false
    private var visibilityUpdateID = UUID()
    private var positionUpdateID = UUID()
    private var workItem: DispatchWorkItem?
    private var positionWorkItem: DispatchWorkItem?
    private var windowObservers = [NSObjectProtocol]()
    private var appearanceObservation: NSKeyValueObservation?

    init(hostView: NSView, backgroundColor: NSColor,
         makeWindow: () -> NSWindow = { HoveredLinkTooltipWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true) },
         mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
         trailingInset: @escaping () -> CGFloat = { 0 },
         currentHoveredURL: @escaping () -> URL? = { nil },
         animate: @escaping (NSWindow, CGFloat, TimeInterval, @escaping () -> Void) -> Void = { window, opacity, duration, completion in
             NSAnimationContext.runAnimationGroup { context in
                 context.duration = duration
                 window.animator().alphaValue = opacity
             } completionHandler: {
                 completion()
             }
         },
         move: @escaping (NSWindow, NSRect, TimeInterval) -> Void = { window, frame, duration in
             // Cancel any previous movement and apply sizing immediately so text stays within its bounds.
             NSAnimationContext.runAnimationGroup { context in
                 context.duration = 0
                 window.animator().setFrame(NSRect(origin: window.frame.origin, size: frame.size), display: true)
             }
             NSAnimationContext.runAnimationGroup { context in
                 context.duration = duration
                 window.animator().setFrame(frame, display: true)
             }
         },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> DispatchWorkItem = { delay, action in
             let item = DispatchWorkItem(block: action)
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
             return item
         }) {
        self.hostView = hostView
        self.window = makeWindow()
        self.mouseLocation = mouseLocation
        self.trailingInset = trailingInset
        self.currentHoveredURL = currentHoveredURL
        self.animate = animate
        self.move = move
        self.schedule = schedule

        let background = NSBox(frame: .zero)
        background.boxType = .custom
        background.titlePosition = .noTitle
        background.borderWidth = 0
        background.cornerRadius = 4
        background.fillColor = backgroundColor
        background.contentViewMargins = .zero
        background.contentView?.addSubview(label)

        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.maximumNumberOfLines = 1
        label.setAccessibilityIdentifier("HoveredLinkTooltip.label")

        window.contentView = background
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    deinit {
        workItem?.cancel()
        positionWorkItem?.cancel()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        let window = window
        DispatchQueue.main.async {
            window.alphaValue = 0
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
            // Release the window's views: a hidden, never closed window keeps them alive.
            window.contentView = nil
            window.close()
        }
    }

    func update(url: URL?) {
        hoveredURL = url
        // A tooltip that is already fading out keeps fading instead of popping back and fading again.
        if url == nil, isFadingOut { return }
        cancelPendingUpdates()
        guard isMouseInside else { return }

        guard let url else {
            guard window.isVisible else { return }
            scheduleVisibilityUpdate(after: 0.1) { $0.fadeOut() }
            return
        }

        label.stringValue = url.absoluteString
        if window.isVisible {
            updatePosition()
        } else {
            // A tooltip that is still fading out stays visible above; once hidden, the reveal delay applies again.
            scheduleVisibilityUpdate(after: 0.5) { $0.show() }
        }
    }

    /// The window was deactivated: hide and forget the link. The page reports link changes only, so when the pointer
    /// is still on the same link after the window becomes active again, the next move takes it from the page.
    func windowDidResignKey() {
        reset()
        shouldRestoreOnNextMove = true
    }

    func reset() {
        cancelPendingUpdates()
        hoveredURL = nil
        hasShownTooltip = false
        hide()
    }

    private func hide() {
        isFadingOut = false
        window.alphaValue = 0
        // Only a window that was positioned can still be moving.
        if targetFrame != nil {
            move(window, window.frame, 0)
        }
        targetFrame = nil
        appearanceObservation = nil
        window.orderOut(nil)
        window.parent?.removeChildWindow(window)
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }

    private func fadeOut() {
        let updateID = visibilityUpdateID
        isFadingOut = true
        // Fade the complete window while its label and child relationship remain intact.
        animate(window, 0, 0.1) { [weak self] in
            guard let self, self.visibilityUpdateID == updateID else { return }
            self.hide()
        }
    }

    private func cancelPendingUpdates() {
        visibilityUpdateID = UUID()
        positionUpdateID = UUID()
        if isFadingOut {
            isFadingOut = false
            // Replace the in-flight animation, including its target opacity.
            animate(window, 1, 0) {}
        }
        workItem?.cancel()
        workItem = nil
        positionWorkItem?.cancel()
        positionWorkItem = nil
    }

    private func scheduleVisibilityUpdate(after delay: TimeInterval, action: @escaping (HoveredLinkTooltipPresenter) -> Void) {
        let updateID = visibilityUpdateID
        workItem = schedule(delay) { [weak self] in
            // A cancelled callback may already be enqueued. It cannot change newer hover state.
            guard let self, self.visibilityUpdateID == updateID else { return }
            self.workItem = nil
            action(self)
        }
    }

    func mouseDidMove() {
        let isReturning = !isMouseInside || shouldRestoreOnNextMove
        shouldRestoreOnNextMove = false
        isMouseInside = true
        // The page reports only link changes. After the URL was forgotten (window deactivated) or the pointer came
        // back from a view that doesn't belong to the page (inspector) onto the same link, nothing will report it again.
        if isReturning, hoveredURL == nil {
            hoveredURL = currentHoveredURL()
        }
        if isReturning, hoveredURL != nil, !window.isVisible {
            // WebKit may still consider the same link hovered and send no new URL.
            // Give its hover update a chance to cancel a stale URL before restoring it.
            scheduleVisibilityUpdate(after: hasShownTooltip ? 0.05 : 0.5) { $0.show() }
            return
        }
        guard hoveredURL != nil, window.isVisible, positionWorkItem == nil else { return }
        let updateID = positionUpdateID
        // The native monitor runs before WebKit receives the event. Allow its hover-exit
        // message to cancel this move instead of shifting a tooltip that's about to hide.
        positionWorkItem = schedule(0.05) { [weak self] in
            guard let self, self.positionUpdateID == updateID else { return }
            self.positionWorkItem = nil
            self.updatePosition()
        }
    }

    func mouseDidExit() {
        guard isMouseInside else { return }
        isMouseInside = false
        cancelPendingUpdates()
        hide()
    }

    private func show() {
        guard let hoveredURL, isMouseInside else { return }
        hide()
        guard let hostView, let parent = hostView.window, parent.isKeyWindow, parent.isVisible else { return }
        label.stringValue = hoveredURL.absoluteString
        layout()
        window.alphaValue = 0
        parent.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        animate(window, 1, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25) {}
        hasShownTooltip = true
        appearanceObservation = hostView.observe(\.effectiveAppearance, options: [.new]) { [weak self] hostView, _ in
            self?.window.appearance = hostView.effectiveAppearance
        }

        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            windowObservers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                self?.updatePosition()
            })
        }
        windowObservers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: parent, queue: .main) { [weak self] _ in
            self?.windowDidResignKey()
        })
        for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
            windowObservers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                self?.reset()
            })
        }
    }

    func updatePosition() {
        guard hoveredURL != nil, window.isVisible else { return }
        layout(animated: true)
    }

    private func layout(animated: Bool = false) {
        guard let hostView, let parent = hostView.window else { return }
        var hostFrame = parent.convertToScreen(hostView.convert(hostView.bounds, to: nil))
        // Keep the tooltip out of a sidebar that overlaps the host's trailing edge.
        hostFrame.size.width = max(0, hostFrame.width - trailingInset())
        let screenFrame = parent.screen?.visibleFrame ?? hostFrame
        // NSTextField's intrinsic width omits the cell's horizontal drawing insets.
        // Include them and round up so the last glyph fits without partial clipping.
        let cellSize = label.cell?.cellSize ?? label.intrinsicContentSize
        let labelSize = NSSize(width: ceil(cellSize.width), height: ceil(cellSize.height))
        let size = NSSize(width: min(labelSize.width + 20, hostFrame.width, screenFrame.width), height: labelSize.height + 12)
        let frame = Self.frame(size: size, hostFrame: hostFrame, parentFrame: parent.frame,
                               screenFrame: screenFrame, mouseLocation: mouseLocation())
        window.appearance = hostView.effectiveAppearance
        label.frame = NSRect(x: 12, y: 6, width: max(0, frame.width - 20), height: labelSize.height)
        guard targetFrame != frame else { return }
        targetFrame = frame
        if animated, window.frame.minX != frame.minX {
            // Only the vertical movement is animated: sideways changes apply instantly.
            move(window, NSRect(origin: NSPoint(x: frame.minX, y: window.frame.minY), size: frame.size), 0)
        }
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0
        move(window, frame, duration)
    }

    /// All inputs use screen coordinates. Always test against the resting frame, so moving
    /// the tooltip away from the mouse doesn't immediately move it back underneath it.
    static func frame(size: NSSize, hostFrame: NSRect, parentFrame: NSRect,
                      screenFrame: NSRect, mouseLocation: NSPoint) -> NSRect {
        var frame = NSRect(origin: NSPoint(x: hostFrame.minX, y: hostFrame.minY), size: size)
        frame.origin.x = min(max(frame.minX, screenFrame.minX), screenFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, screenFrame.minY), screenFrame.maxY - size.height)
        guard frame.insetBy(dx: -8, dy: -8).contains(mouseLocation) else { return frame }

        let belowWindow = parentFrame.minY - size.height
        if belowWindow >= screenFrame.minY {
            frame.origin.y = belowWindow
        } else {
            // Fullscreen, maximized, or near the Dock: keep the URL at the bottom but in the half of the host
            // opposite to the pointer, limited to half of the width so it never lands under the pointer.
            let maxWidth = hostFrame.width / 2
            frame.size.width = min(frame.width, maxWidth)
            let isPointerInLeftHalf = mouseLocation.x < hostFrame.midX
            frame.origin.x = isPointerInLeftHalf ? hostFrame.maxX - frame.width : hostFrame.minX
            frame.origin.x = min(max(frame.minX, screenFrame.minX), screenFrame.maxX - frame.width)
        }
        return frame
    }
}

final class HoveredLinkTooltipWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
