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
import QuartzCore

/// Renders the Tab Background using a CAShapeLayer so path and fill are updated without CPU-bound draw(_:).
final class TabBackgroundShapeView: NSView {

    private var lastPathSize: NSSize = .zero

    var backgroundColor: NSColor = .clear {
        didSet {
            guard oldValue != backgroundColor else { return }
            shapeLayer.fillColor = backgroundColor.cgColor
        }
    }

    var isDragged: Bool = false {
        didSet {
            guard oldValue != isDragged else { return }
            refreshShapePath()
        }
    }

    var rampSize: NSSize? {
        didSet {
            guard oldValue != rampSize else { return }
            refreshShapePath()
        }
    }

    var tabCornerRadius: CGFloat = .zero {
        didSet {
            guard oldValue != tabCornerRadius else { return }
            refreshShapePath()
        }
    }

    // MARK: - Private

    private let shapeLayer = CAShapeLayer()

    private var backgroundRoundedCorners: [NSBezierPath.Corners] {
        isDragged ? [.topLeft, .topRight, .bottomLeft, .bottomRight] : [.bottomLeft, .bottomRight]
    }

    private var shouldDisplayRamps: Bool {
        !isDragged
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func layout() {
        super.layout()

        refreshShapeBoundsAndPath()
    }
}

// MARK: - Core Graphics Helpers

private extension TabBackgroundShapeView {

    private func refreshShapeBoundsAndPath() {
        guard let layer else {
            return
        }

        if shapeLayer.superlayer == nil {
            layer.addSublayer(shapeLayer)
        }

        if shapeLayer.frame != bounds {
            shapeLayer.frame = bounds
        }

        if lastPathSize != bounds.size {
            refreshShapePath()
            lastPathSize = bounds.size
        }
    }

    private func refreshShapePath() {
        shapeLayer.path = buildBackgroundCGPath()
    }

    private func buildBackgroundCGPath() -> CGPath? {
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let backgroundPath = NSBezierPath(roundedRect: bounds, forCorners: backgroundRoundedCorners, cornerRadius: tabCornerRadius).asCGPath()

        guard shouldDisplayRamps, let rampSize else {
            return backgroundPath
        }

        let outputPath = CGMutablePath()
        outputPath.addPath(backgroundPath)

        let leadingRamp = NSBezierPath.leadingRampPath(size: rampSize).asCGPath()
        outputPath.addPath(leadingRamp, transform: CGAffineTransform(translationX: -rampSize.width, y: 0))

        let trailingRamp = NSBezierPath.trailingRampPath(size: rampSize).asCGPath()
        outputPath.addPath(trailingRamp, transform: CGAffineTransform(translationX: bounds.width, y: 0))

        return outputPath
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
