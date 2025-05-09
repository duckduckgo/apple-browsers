//
//  InitialWindowFrameProvider.swift
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

import Cocoa

/// Provides the initial NSRect for the main window:
/// – 90% of work area (excludes Dock & menu bar)
/// – minimum 300×300, maximum 1920×1080
/// – capped at a 16:9 aspect ratio
/// – centered in the visible frame
struct InitialWindowFrameProvider {
    static func initialFrame(visibleFrame: NSRect? = nil) -> NSRect {
        // Work area (excludes Dock & menu bar)
        let workArea = visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(origin: .zero, size: NSSize(width: 1024, height: 790))
        let topLeft = CGPoint(x: workArea.minX, y: workArea.minY)
        let size = workArea.size

        // 90% of work area
        var width = size.width * 0.90
        var height = size.height * 0.90

        // Enforce minimum 300×300
        width = max(width, 300)
        height = max(height, 300)

        // Cap aspect ratio to 16:9
        let maxAspectRatio: CGFloat = 16.0 / 9.0
        if width / height > maxAspectRatio {
            width = height * maxAspectRatio
        }

        // Clamp to maximum 1600×1200
        width = min(width, 1600)
        height = min(height, 1200)

        // Center within work area
        let originX = max((size.width - width) / 2 + topLeft.x, topLeft.x)
        let originY = max((size.height - height) / 2 + topLeft.y, topLeft.y)
        let origin = CGPoint(x: originX, y: originY)

        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }
}
