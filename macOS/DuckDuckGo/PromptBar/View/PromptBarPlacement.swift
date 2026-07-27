//
//  PromptBarPlacement.swift
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

/// Where the Prompt Bar sits on screen: horizontally centered, near the top, Spotlight-style.
/// Pure geometry so the placement rules can be tested without a window or a real display.
enum PromptBarPlacement {

    /// Preferred width. Narrower screens fall back to the widest width the margins allow.
    static let preferredWidth: CGFloat = 680

    static let horizontalScreenMargin: CGFloat = 24

    /// Gap between the screen's top edge and the bar's top edge, as a fraction of screen height.
    static let topOffsetRatio: CGFloat = 0.22

    /// - Parameters:
    ///   - contentHeight: Height the content currently needs; grows with text and attachments.
    ///   - visibleFrame: `NSScreen.visibleFrame` of the target screen, so menu bar and Dock are excluded.
    static func frame(forContentHeight contentHeight: CGFloat, in visibleFrame: NSRect) -> NSRect {
        let width = min(preferredWidth, max(0, visibleFrame.width - horizontalScreenMargin * 2))
        // Never taller than the screen allows, so a long prompt can't push the bar off-screen.
        let height = min(contentHeight, visibleFrame.height)

        let originX = visibleFrame.minX + ((visibleFrame.width - width) / 2).rounded()
        let preferredTop = visibleFrame.maxY - (visibleFrame.height * topOffsetRatio).rounded()
        // Clamp so growth downwards stays inside the visible frame.
        let top = min(visibleFrame.maxY, max(preferredTop, visibleFrame.minY + height))

        return NSRect(x: originX, y: top - height, width: width, height: height)
    }
}

/// The screen the Prompt Bar should open on.
@MainActor
protocol PromptBarScreenProviding {
    var targetVisibleFrame: NSRect { get }
}

/// Opens on the screen holding the pointer, which is where the user's attention is.
@MainActor
struct MouseLocationScreenProvider: PromptBarScreenProviding {

    var targetVisibleFrame: NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }
}
