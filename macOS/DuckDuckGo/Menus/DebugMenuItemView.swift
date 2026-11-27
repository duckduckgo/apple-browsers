//
//  DebugMenuItemView.swift
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

/// Handles secondary clicks before native menu action dispatch, which otherwise dismisses the menu.
@MainActor
final class DebugMenuItemView: NSView {
    var key: String
    private weak var favorites: DebugMenuFavorites?

    init(key: String, favorites: DebugMenuFavorites) {
        self.key = key
        self.favorites = favorites
        var minimumWidth: CGFloat = 300
        if let item = favorites.source(for: key) {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
            let titleWidth = (item.title as NSString).size(withAttributes: attributes).width
            let shortcutWidth = (DebugMenuItemView.shortcut(for: item) as NSString).size(withAttributes: attributes).width
            minimumWidth = max(minimumWidth, titleWidth + shortcutWidth + CGFloat(item.indentationLevel) * 12 + 90)
        }
        // AppKit captures the minimum width when this view is assigned to its menu item.
        // Leave subsequent sizing to its width autoresizing mask so rows fill the menu.
        super.init(frame: NSRect(x: 0, y: 0, width: minimumWidth, height: 24))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item = enclosingMenuItem else { return }
        let highlighted = item.isHighlighted && item.isEnabled
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        let color: NSColor = !item.isEnabled ? .disabledControlTextColor : highlighted ? .selectedMenuItemTextColor : .labelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: color]
        let titleX: CGFloat = item.image == nil ? 24 : 44
        let titlePoint = NSPoint(x: titleX + CGFloat(item.indentationLevel) * 12, y: 4)
        (item.title as NSString).draw(at: titlePoint, withAttributes: attributes)
        if let image = item.image {
            image.draw(in: NSRect(x: 24, y: 4, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: item.isEnabled ? 1 : 0.4)
        }
        if item.state != .off {
            ((item.state == .on ? "✓" : "−") as NSString).draw(at: NSPoint(x: 8, y: 4), withAttributes: attributes)
        }
        var trailingX = bounds.maxX - 22
        if item.submenu != nil {
            ("›" as NSString).draw(at: NSPoint(x: trailingX, y: 4), withAttributes: attributes)
            trailingX -= 20
        }
        let shortcut = Self.shortcut(for: item) as NSString
        shortcut.draw(at: NSPoint(x: trailingX - shortcut.size(withAttributes: attributes).width, y: 4), withAttributes: attributes)
    }

    override func rightMouseDown(with event: NSEvent) {}

    override func rightMouseUp(with event: NSEvent) {
        favorites?.toggle(key)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        performAction()
    }

    @discardableResult
    private func performAction() -> Bool {
        guard let item = enclosingMenuItem, item.isEnabled, let action = item.action,
              let sourceAction = favorites?.source(for: key)?.action,
              NSStringFromSelector(sourceAction) != NSStringFromSelector(#selector(NSMenu.submenuAction(_:))) else { return false }
        item.menu?.cancelTrackingWithoutAnimation()
        let performed = NSApp.sendAction(action, to: item.target, from: item)
        favorites?.refresh()
        return performed
    }

    override func accessibilityLabel() -> String? {
        enclosingMenuItem?.title
    }

    override func accessibilityPerformPress() -> Bool {
        performAction()
    }

    private static func shortcut(for item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let flags = item.keyEquivalentModifierMask
        return (flags.contains(.control) ? "⌃" : "")
            + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "")
            + (flags.contains(.command) ? "⌘" : "")
            + item.keyEquivalent.uppercased()
    }
}
