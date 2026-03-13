//
//  TabBackgroundShapeView.swift
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

/// Renders the Tab Background in a single CALayer: This helps us avoid Core Animation artifacts, when animating multiple layers at the concurrently
///
final class TabBackgroundShapeView: NSView {

    var backgroundColor: NSColor = .clear {
        didSet {
            guard oldValue != backgroundColor else {
                return
            }

            needsDisplay = true
        }
    }

    var isDragged: Bool = false {
        didSet {
            guard oldValue != isDragged else {
                return
            }

            needsDisplay = true
        }
    }

    var rampSize: NSSize? {
        didSet {
            guard oldValue != rampSize else {
                return
            }

            needsDisplay = true
        }
    }

    var tabCornerRadius: CGFloat = .zero {
        didSet {
            guard oldValue != tabCornerRadius else {
                return
            }

            needsDisplay = true
        }
    }

    // MARK: - Private Properties

    private var backgroundRoundedCorners: [NSBezierPath.Corners] {
        isDragged ? [.topLeft, .topRight, .bottomLeft, .bottomRight] : [.bottomLeft, .bottomRight]
    }

    private var shouldDisplayRamps: Bool {
        !isDragged
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        backgroundColor.setFill()

        /// # Central Background
        let backgroundPath = NSBezierPath(roundedRect: bounds, forCorners: backgroundRoundedCorners, cornerRadius: tabCornerRadius)
        backgroundPath.fill()

        guard shouldDisplayRamps, let rampSize else {
            return
        }

        /// # Leading Ramp
        context.translateBy(x: rampSize.width * -1, y: 0)

        NSBezierPath
            .leadingRampPath(size: rampSize)
            .fill()

        /// # Trailing Ramp
        context.translateBy(x: bounds.width + rampSize.width, y: 0)

        NSBezierPath
            .trailingRampPath(size: rampSize)
            .fill()
    }
}

private extension NSBezierPath {

    static func trailingRampPath(size: NSSize) -> NSBezierPath {
        let origin = NSPoint(x: size.width, y: 0)
        let center = NSPoint(x: size.width, y: size.height)

        let path = NSBezierPath()
        path.move(to: origin)
        path.line(to: .zero)
        path.appendArc(withCenter: center, radius: size.width, startAngle: 180, endAngle: 270, clockwise: false)
        path.close()
        return path
    }

    static func leadingRampPath(size: NSSize) -> NSBezierPath {
        let output = trailingRampPath(size: size)
        output.transform(using: .flippedHorizontally(width: size.width))
        return output
    }
}

private extension AffineTransform {

    static func flippedHorizontally(width: CGFloat) -> AffineTransform {
        var output = AffineTransform.identity
        output.translate(x: width, y: 0)
        output.scale(x: -1, y: 1)
        return output
    }
}
