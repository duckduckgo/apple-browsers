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
    private let animate: (NSWindow, CGFloat, TimeInterval, @escaping () -> Void) -> Void
    private var hoveredURL: URL?
    private var hasShownTooltip = false
    private var isFadingOut = false
    private var visibilityUpdateID = UUID()
    private var positionUpdateID = UUID()
    private var workItem: DispatchWorkItem?
    private var positionWorkItem: DispatchWorkItem?
    private var windowObservers = [NSObjectProtocol]()
    private var appearanceObservation: NSKeyValueObservation?

    init(hostView: NSView, backgroundColor: NSColor,
         makeWindow: () -> NSWindow = { HoveredLinkTooltipWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true) },
         mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
         animate: @escaping (NSWindow, CGFloat, TimeInterval, @escaping () -> Void) -> Void = { window, opacity, duration, completion in
             NSAnimationContext.runAnimationGroup { context in
                 context.duration = duration
                 window.animator().alphaValue = opacity
             } completionHandler: {
                 completion()
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
        self.animate = animate
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
        window.setAccessibilityIdentifier("HoveredLinkTooltip.window")
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
        }
    }

    func update(url: URL?) {
        cancelPendingUpdates()
        hoveredURL = url

        guard let url else {
            guard window.isVisible else { return }
            scheduleVisibilityUpdate(after: 0.1) { $0.fadeOut() }
            return
        }

        label.stringValue = url.absoluteString
        if window.isVisible {
            updatePosition()
        } else if hasShownTooltip {
            // Crossing a gap between links must not restart the initial reveal delay.
            show()
        } else {
            scheduleVisibilityUpdate(after: 0.5) { $0.show() }
        }
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

    private func show() {
        guard hoveredURL != nil else { return }
        hide()
        guard let hostView, let parent = hostView.window, parent.isKeyWindow, parent.isVisible else { return }
        layout()
        window.alphaValue = 1
        parent.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
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
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
            windowObservers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                self?.reset()
            })
        }
    }

    func updatePosition() {
        guard hoveredURL != nil, window.isVisible else { return }
        layout()
    }

    private func layout() {
        guard let hostView, let parent = hostView.window else { return }
        let hostFrame = parent.convertToScreen(hostView.convert(hostView.bounds, to: nil))
        let screenFrame = parent.screen?.visibleFrame ?? hostFrame
        // NSTextField's intrinsic width omits the cell's horizontal drawing insets.
        // Include them and round up so the last glyph fits without partial clipping.
        let cellSize = label.cell?.cellSize ?? label.intrinsicContentSize
        let labelSize = NSSize(width: ceil(cellSize.width), height: ceil(cellSize.height))
        let size = NSSize(width: min(labelSize.width + 20, hostFrame.width, screenFrame.width), height: labelSize.height + 12)
        let frame = Self.frame(size: size, hostFrame: hostFrame, parentFrame: parent.frame,
                               screenFrame: screenFrame, mouseLocation: mouseLocation())
        window.appearance = hostView.effectiveAppearance
        window.setFrame(frame, display: true)
        label.frame = NSRect(x: 12, y: 6, width: max(0, size.width - 20), height: labelSize.height)
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
            // Fullscreen, maximized, or near the Dock: keep the URL above the pointer.
            frame.origin.y = min(max(frame.maxY, mouseLocation.y + 16), screenFrame.maxY - size.height)
        }
        return frame
    }
}

final class HoveredLinkTooltipWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
