//
//  RampView.swift
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

/**
 `RampView` is an `NSView` subclass used to render the distinctive S-shaped corners
 for standard (unpinned) tabs in the tab bar. This effect is achieved by drawing a quarter-circle
 "ramp" on either side of the tab, visually connecting the tab to the tab bar background
 in a smooth, modern way.

 The `RampView` can be horizontally flipped to support both left and right corners, and its color
 and size are fully configurable. It is typically added as a subview to the tab cell view and is only
 visible for selected (active) tabs when the S-shaped style is enabled.

 The logic and parameters are kept consistent with the SwiftUI `PinnedTabRampView` for maintainability.
 */
final class RampView: NSView {

    enum Consts {
        static let rampWidth: CGFloat = 10
        static let rampHeight: CGFloat = 10
    }

    var isFlippedHorizontally: Bool = false
    var rampColor: NSColor = .surfacePrimary

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        if isFlippedHorizontally {
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }

        rampColor.setFill()

        let path = NSBezierPath()
        path.move(to: NSPoint(x: Consts.rampWidth, y: 0))
        path.line(to: NSPoint(x: 0, y: 0))
        path.appendArc(
            withCenter: NSPoint(x: Consts.rampWidth, y: Consts.rampHeight),
            radius: Consts.rampWidth,
            startAngle: 180,
            endAngle: 270,
            clockwise: false
        )

        path.close()
        path.fill()

        context.restoreGState()
    }
}
