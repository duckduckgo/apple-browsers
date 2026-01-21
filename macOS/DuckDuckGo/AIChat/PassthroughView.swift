//
//  PassthroughView.swift
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

import Cocoa

/// A view that can pass through hit testing in a configurable bottom region.
/// Used to allow clicks to reach views behind this one in a specific area.
final class PassthroughView: NSView {

    /// Height from bottom of view that should pass events through (not intercept).
    var passthroughBottomHeight: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)

        // Check if point is in passthrough region (bottom of view)
        // In AppKit, y=0 is at the bottom
        if passthroughBottomHeight > 0 && localPoint.y < passthroughBottomHeight {
            return nil
        }

        return super.hitTest(point)
    }
}
