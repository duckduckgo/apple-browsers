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

/// Spotlight-style placement. Pure geometry, so it tests without a window or a real display.
enum PromptBarPlacement {

    static let preferredWidth: CGFloat = 680

    static let horizontalScreenMargin: CGFloat = 24

    static let topOffsetRatio: CGFloat = 0.22

    static func frame(forContentHeight contentHeight: CGFloat, in visibleFrame: NSRect) -> NSRect {
        let width = min(preferredWidth, max(0, visibleFrame.width - horizontalScreenMargin * 2))
        let height = min(contentHeight, visibleFrame.height)

        let originX = visibleFrame.minX + ((visibleFrame.width - width) / 2).rounded()
        let preferredTop = visibleFrame.maxY - (visibleFrame.height * topOffsetRatio).rounded()
        let top = min(visibleFrame.maxY, max(preferredTop, visibleFrame.minY + height))

        return NSRect(x: originX, y: top - height, width: width, height: height)
    }

    /// `relativePosition` is the top-left corner as a fraction of `visibleFrame`, so it carries across screens.
    /// The result is clamped to stay on screen.
    static func frame(forContentHeight contentHeight: CGFloat, in visibleFrame: NSRect, relativePosition: CGPoint) -> NSRect {
        var frame = frame(forContentHeight: contentHeight, in: visibleFrame)
        let left = visibleFrame.minX + (relativePosition.x * visibleFrame.width).rounded()
        let top = visibleFrame.maxY - (relativePosition.y * visibleFrame.height).rounded()
        frame.origin.x = min(max(left, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(top, visibleFrame.minY + frame.height), visibleFrame.maxY) - frame.height
        return frame
    }

    static func relativePosition(of frame: NSRect, in visibleFrame: NSRect) -> CGPoint {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return .zero }
        return CGPoint(x: (frame.minX - visibleFrame.minX) / visibleFrame.width,
                       y: (visibleFrame.maxY - frame.maxY) / visibleFrame.height)
    }
}

@MainActor
protocol PromptBarScreenProviding {
    var targetVisibleFrame: NSRect { get }
}

@MainActor
struct MouseLocationScreenProvider: PromptBarScreenProviding {

    var targetVisibleFrame: NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }
}
