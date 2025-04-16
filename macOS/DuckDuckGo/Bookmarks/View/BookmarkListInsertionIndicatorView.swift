//
//  BookmarkListInsertionIndicatorView.swift
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

/// A view that draws a custom drop insertion indicator for the Bookmarks/Bookmarks Bar Menu outline view
final class BookmarkListInsertionIndicatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let indicatorRect = NSRect(x: 7, y: bounds.midY - 1, width: bounds.width - 11, height: 2)
        // draw rounded corners rect
        NSColor.controlAccentColor.set()
        let path = NSBezierPath(roundedRect: indicatorRect, xRadius: 1, yRadius: 1)
        path.fill()
    }
}
