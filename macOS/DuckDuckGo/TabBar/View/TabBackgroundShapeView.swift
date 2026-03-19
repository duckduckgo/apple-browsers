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
            applyBackgroundColor()
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

    private lazy var shapeLayer: CAShapeLayer = {
        let output = CAShapeLayer()
        output.masksToBounds = false
        return output
    }()

    private var displaysTopRoundedCorners: Bool {
        !isDragged
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackgroundColor()
    }
}

// MARK: - Core Graphics Helpers

private extension TabBackgroundShapeView {

    func applyBackgroundColor() {
        NSAppearance.withAppAppearance {
            shapeLayer.fillColor = backgroundColor.cgColor
        }
    }

    func refreshShapeBoundsAndPath() {
        guard let layer else {
            return
        }

        if shapeLayer.superlayer == nil {
            layer.addSublayer(shapeLayer)
            layer.masksToBounds = false
        }

        if shapeLayer.frame != bounds {
            shapeLayer.frame = bounds
        }

        if lastPathSize != bounds.size {
            refreshShapePath()
            lastPathSize = bounds.size
        }
    }

    func refreshShapePath() {
        shapeLayer.path = buildBackgroundCGPath()
    }

    func buildBackgroundCGPath() -> CGPath? {
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let backgroundPath: CGPath = displaysTopRoundedCorners ?
            CGPath.topRoundedRect(in: bounds, radius: tabCornerRadius) :
            CGPath(roundedRect: bounds, cornerWidth: tabCornerRadius, cornerHeight: tabCornerRadius, transform: nil)

        guard shouldDisplayRamps, let rampSize else {
            return backgroundPath
        }

        let outputPath = CGMutablePath()

        outputPath.addPath(backgroundPath)
        outputPath.addPath(.leadingRamp(size: rampSize), transform: CGAffineTransform(translationX: -rampSize.width, y: 0))
        outputPath.addPath(.trailingRamp(size: rampSize), transform: CGAffineTransform(translationX: bounds.width, y: 0))

        return outputPath
    }
}

// MARK: - Ramp Paths

private extension CGPath {

    static func leadingRamp(size: NSSize) -> CGPath {
        let trailing = trailingRamp(size: size)
        let flipped = CGMutablePath()
        flipped.addPath(trailing, transform: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -size.width, y: 0))
        return flipped
    }

    static func trailingRamp(size: NSSize) -> CGPath {
        let origin = CGPoint(x: size.width, y: 0)
        let center = CGPoint(x: size.width, y: size.height)

        let path = CGMutablePath()
        path.move(to: origin)
        path.addLine(to: .zero)
        path.addArc(center: center, radius: size.width, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
        path.closeSubpath()
        return path
    }

    static func topRoundedRect(in rect: CGRect, radius: CGFloat) -> CGPath {
        let radius = max(0, min(radius, rect.width * 0.5, rect.height * 0.5))
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        let path = CGMutablePath()

        // Bottom-Left + Bottom-Right
        path.move(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))

        // Up Right
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))

        // Top-Right + Across + Top-Left
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - radius, y: maxY), radius: radius)
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - radius), radius: radius)

        // Down Left
        path.addLine(to: CGPoint(x: minX, y: minY))
        path.closeSubpath()
        return path
    }
}
