//
//  MouseBlockingBackgroundView.swift
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

/// A view that aggressively blocks ALL mouse events from reaching views behind it (like a webview),
/// forwarding them only to its own subviews. See `MouseEventInterceptingView` for the shared behaviour;
/// this variant adds a bottom passthrough region and resolves against the window's `contentView`.
final class MouseBlockingBackgroundView: MouseEventInterceptingView {

    /// Height from the bottom of the view that should pass events through (not intercept).
    /// Used to allow clicks to reach views behind this one in a specific region.
    var passthroughBottomHeight: CGFloat = 0

    override func shouldPassThroughEvent(at locationInView: NSPoint) -> Bool {
        // In AppKit, y=0 is at the bottom, so a point is in the passthrough strip when y < passthroughBottomHeight.
        passthroughBottomHeight > 0 && locationInView.y < passthroughBottomHeight
    }
}
