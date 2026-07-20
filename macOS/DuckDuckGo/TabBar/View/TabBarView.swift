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

    private var windowDraggingView: WindowDraggingView? {
        subviews.first { $0 is WindowDraggingView && !$0.isHidden } as? WindowDraggingView
    }

    // Empty tab-bar chrome should drag the window; the scroll/collection views swallow those
    // clicks, so redirect them to the dragging view. Tabs and buttons resolve to their own views.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }

        // Only redirect the initial click; drag-and-drop destination resolution is also hitTest-based.
        guard NSApp.currentEvent?.type == .leftMouseDown else { return hit }

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
