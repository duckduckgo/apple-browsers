//
//  AIChatSidebarResizeHandleView.swift
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

import AppKit

/// Thin draggable view on the leading edge of the AI Chat sidebar.
///
/// Reports width changes during drag via `onResize`, and notifies
/// `onResizeEnd` when the drag completes so the final width can be persisted.
final class AIChatSidebarResizeHandleView: NSView {

    private enum Constants {
        /// Visual width of the handle (the actual view frame).
        static let handleWidth: CGFloat = 6
        /// Extra points added on each side for hit-testing and cursor tracking.
        static let hitTestPadding: CGFloat = 3
    }

    /// Called continuously during drag with the proposed new sidebar width.
    /// Returns the actual (clamped) width that was applied.
    var onResize: ((_ proposedWidth: CGFloat) -> CGFloat)?

    /// Called once when the drag ends with the final sidebar width.
    var onResizeEnd: ((_ finalWidth: CGFloat) -> Void)?

    /// Returns the current sidebar width at drag start.
    var currentWidthProvider: (() -> CGFloat)?

    private var isDragging: Bool = false
    private var dragStartX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        NSSize(width: Constants.handleWidth, height: NSView.noIntrinsicMetric)
    }

    // MARK: - Hit Testing

    /// Expands the clickable area beyond the narrow visual frame so the handle
    /// is easy to grab even when the cursor drifts a few pixels to either side.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let expanded = frame.insetBy(dx: -Constants.hitTestPadding, dy: 0)
        return expanded.contains(point) ? self : nil
    }

    // MARK: - Cursor Rects

    /// Registers a cursor rect so AppKit keeps the resize cursor visible even
    /// when the mouse is stationary over the handle.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        // Expand the tracking rect so the resize cursor appears before the mouse
        // is precisely over the narrow 6pt strip.
        let expandedRect = bounds.insetBy(dx: -Constants.hitTestPadding, dy: 0)
        let area = NSTrackingArea(
            rect: expandedRect,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        isDragging = true
        NSCursor.resizeLeftRight.push()

        dragStartX = window.mouseLocationOutsideOfEventStream.x
        dragStartWidth = currentWidthProvider?() ?? 0

        // Tight tracking loop: process drag/up events without returning to
        // the run loop, preventing AppKit from resetting the cursor between events.
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break }
            switch nextEvent.type {
            case .leftMouseDragged:
                let currentX = nextEvent.locationInWindow.x
                let proposedWidth = dragStartWidth + (dragStartX - currentX)
                let appliedWidth = onResize?(proposedWidth) ?? proposedWidth
                cursorForDrag(proposedWidth: proposedWidth, appliedWidth: appliedWidth).set()
            case .leftMouseUp:
                let currentX = nextEvent.locationInWindow.x
                let finalWidth = dragStartWidth + (dragStartX - currentX)
                isDragging = false
                NSCursor.pop()
                onResizeEnd?(finalWidth)
                keepTracking = false
            default:
                break
            }
        }
    }

    /// Dragging left widens the sidebar, dragging right narrows it.
    /// When clamped at max, only narrowing (right) is possible; at min, only widening (left).
    private func cursorForDrag(proposedWidth: CGFloat, appliedWidth: CGFloat) -> NSCursor {
        if proposedWidth - appliedWidth > 0.5 {
            return .resizeRight
        } else if appliedWidth - proposedWidth > 0.5 {
            return .resizeLeft
        }
        return .resizeLeftRight
    }
}
