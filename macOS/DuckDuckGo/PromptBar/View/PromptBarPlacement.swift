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
