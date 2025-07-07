//
//  NSWindowExtension.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

extension NSWindow {

    var frameInWindowCoordinates: NSRect {
        NSRect(origin: .zero, size: frame.size)
    }

    func setFrameOrigin(droppingPoint: NSPoint) {
        setFrameOrigin(frame.frameOrigin(fromDroppingPoint: droppingPoint))
    }

    func setFrameOrigin(cascadedFrom window: NSWindow) {
        setFrameTopLeftPoint(cascadeTopLeft(from: window.frame.topLeft))
    }

    private static let lastLeftHitKey = "_lastLeftHit"
    var lastLeftHit: NSView? {
        return try? NSException.catch {
            self.value(forKey: Self.lastLeftHitKey) as? NSView
        }
    }

    func evilHackToClearLastLeftHitInWindow() {
        guard let oldValue = self.lastLeftHit else { return }
        let oldValueRetainCount = CFGetRetainCount(oldValue)
        defer {
            // compensate unbalanced release call
            if CFGetRetainCount(oldValue) < oldValueRetainCount {
                _=Unmanaged.passUnretained(oldValue).retain()
            }
        }
        NSException.try {
            autoreleasepool {
                self.setValue(nil, forKey: Self.lastLeftHitKey)
            }
        }
    }

    /// Checks if the given window is part of a specific window parent-child hierarchy or is the window itself.
    /// - Returns: A Boolean value indicating whether the window is part of the hierarchy.
    func isInHierarchy(of window: NSWindow) -> Bool {
        sequence(first: self) {
            $0.parent ?? $0.sheetParent
        }.contains {
            $0 === window
        }
    }

    /// Determines if the window is approximately half the width of the screen
    /// with some tolerance for system margins (useful for detecting split screen in fullscreen mode)
    var isApproximatelyHalfScreenWide: Bool {
        guard let screen = screen else { return false }

        let windowWidth = frame.width
        let screenWidth = screen.frame.width
        let windowHeight = frame.height
        let screenHeight = screen.frame.height

        // Check if window width is approximately half screen width
        // Allow some tolerance for system margins (e.g., 1278 of 1280 for 2560 screen)
        let isApproximatelyHalfWidth = abs(windowWidth - screenWidth / 2) < 20 // Allow 20px tolerance
        let isSignificantHeight = windowHeight > screenHeight * 0.8 // Height should be at least 80% of screen

        return isApproximatelyHalfWidth && isSignificantHeight
    }

}
