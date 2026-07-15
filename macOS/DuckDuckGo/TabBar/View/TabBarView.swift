//
//  TabBarView.swift
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

final class TabBarView: MouseOverView {

    /// The full-width window-dragging view sitting at the bottom of the z-order.
    private var windowDraggingView: WindowDraggingView? {
        subviews.first { $0 is WindowDraggingView && !$0.isHidden } as? WindowDraggingView
    }

    /// The tab bar is hosted in the window's title bar, so its empty chrome should drag the
    /// window like the rest of the title bar. The scroll view and collection view swallow those
    /// clicks (`TabBarScrollView.mouseDownCanMoveWindow == false`) and sit above the base
    /// `WindowDraggingView` in the z-order, which breaks dragging in the gap before the first tab
    /// when no tabs are pinned (with pinned tabs, that gap is the draggable pinned-tabs container).
    /// Redirect background clicks to the window-dragging view so dragging works there too.
    /// Clicks on actual tabs resolve to `TabBarItemCellView`, and buttons to their own views, so
    /// only genuinely empty areas are redirected.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }

        if hit is TabBarScrollView || hit is NSClipView || hit is TabBarCollectionView,
           let windowDraggingView {
            return windowDraggingView
        }

        return hit
    }

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityIdentifier() -> String {
        return "Tabs"
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .group
    }

    override func accessibilityTitle() -> String? {
        "Tab Bar"
    }

    override func accessibilityRoleDescription() -> String? {
        "Tab Bar"
    }

    override func accessibilityChildren() -> [Any]? {
        var result: [Any] = []
        for subview in self.subviews where subview.isVisible {
            if subview.isAccessibilityElement() {
                result.append(subview)
            } else {
                result.append(contentsOf: subview.accessibilityChildren() ?? [])
            }
        }
        return result
    }

}
