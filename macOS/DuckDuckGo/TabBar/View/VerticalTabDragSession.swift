//
//  VerticalTabDragSession.swift
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
import AppKitExtensions
import Combine

/// Tracks the drag in screen coordinates so leaving the sidebar's scroll view doesn't end it.
@MainActor
final class VerticalTabDragSession: ObservableObject {
    private weak var sidebarView: NSView?
    private let model: VerticalTabsViewModel
    @Published private var draggedTabID: TabIdentifier?
    private var preview: NSPanel?
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var onDragEnded: (() -> Void)?
    var isDragging: Bool { draggedTabID != nil }
    private(set) var isPointerOverSidebar = false

    init(sidebarView: NSView, model: VerticalTabsViewModel) {
        self.sidebarView = sidebarView
        self.model = model
    }

    func beginDragging(_ id: TabIdentifier) {
        guard let window = sidebarView?.window else { return }
        cancel()
        draggedTabID = id

        // The originating SwiftUI row can scroll out of the lazy stack before mouse-up.
        NSEvent.addLocalCancellableMonitor(forEventsMatching: [.leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDragged:
                update(at: Self.screenPoint(for: event))
            case .leftMouseUp:
                end(at: Self.screenPoint(for: event))
            case .keyDown where event.keyEquivalent == .escape:
                cancel()
                return nil
            default:
                break
            }
            return event
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification))
            .sink { [weak self] _ in self?.cancel() }
            .store(in: &cancellables)
        update(at: NSApp.currentEvent.map(Self.screenPoint(for:)) ?? NSEvent.mouseLocation)
    }

    private static func screenPoint(for event: NSEvent) -> NSPoint {
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    private func sidebarContains(_ screenPoint: NSPoint) -> Bool {
        guard let sidebarView, let window = sidebarView.window else { return false }
        return sidebarView.visibleRect.contains(sidebarView.convert(window.convertPoint(fromScreen: screenPoint), from: nil))
    }

    func update(at screenPoint: NSPoint) {
        guard let id = draggedTabID, let window = sidebarView?.window else { return }
        isPointerOverSidebar = sidebarContains(screenPoint)
        guard !window.frame.contains(screenPoint), model.canTearOffTab(id) else {
            hidePreview()
            return
        }
        if preview == nil, let image = model.dragPreview(for: id) {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: image.size), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.contentView = NSImageView(image: image)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.animationBehavior = .none
            panel.level = .floating
            panel.setAccessibilityElement(false)
            preview = panel
            refreshTask = Task { [weak self, weak panel, model] in
                guard let image = await model.refreshDragPreview(for: id), !Task.isCancelled,
                      let self, let panel, preview === panel, let imageView = panel.contentView as? NSImageView else { return }
                imageView.image = image
                panel.setContentSize(image.size)
                position(panel, at: NSEvent.mouseLocation)
            }
        }
        guard let preview else { return }
        position(preview, at: screenPoint)
        if preview.parent == nil {
            window.addChildWindow(preview, ordered: .above)
        }
    }

    private func position(_ panel: NSPanel, at point: NSPoint) {
        let size = panel.frame.size
        var topLeft = NSPoint(x: point.x - size.width / 2, y: point.y - 8)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let frame = screen.visibleFrame
            topLeft.x = min(max(topLeft.x, frame.minX), frame.maxX - size.width)
            topLeft.y = min(max(topLeft.y, frame.minY + size.height), frame.maxY)
        }
        panel.setFrameTopLeftPoint(topLeft)
    }

    func end(at screenPoint: NSPoint) {
        let id = draggedTabID
        let sourceFrame = sidebarView?.window?.frame
        isPointerOverSidebar = sidebarContains(screenPoint)
        cancel()
        if let id, let sourceFrame, !sourceFrame.contains(screenPoint) {
            model.tearOffTab(id, at: screenPoint)
        }
    }

    func cancel() {
        guard isDragging else { return }
        draggedTabID = nil
        cancellables.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
        hidePreview()
        preview = nil
        onDragEnded?()
    }

    private func hidePreview() {
        guard let preview, let parent = preview.parent else { return }
        parent.removeChildWindow(preview)
        preview.orderOut(nil)
    }
}
