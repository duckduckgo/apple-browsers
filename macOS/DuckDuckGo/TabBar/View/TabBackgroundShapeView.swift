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

    var tabRampSize: NSSize? {
        didSet {
            guard oldValue != tabRampSize else { return }
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

        if shouldDisplayRamps, let tabRampSize {
            return .tabBackground(in: bounds, cornerRadius: tabCornerRadius, rampSize: tabRampSize)
        }

        return displaysTopRoundedCorners ?
            .tabBackground(in: bounds, cornerRadius: tabCornerRadius) :
            CGPath(roundedRect: bounds, cornerWidth: tabCornerRadius, cornerHeight: tabCornerRadius, transform: nil)
    }
}

// MARK: - Path Builders

private extension CGPath {

    static func tabBackground(in rect: CGRect, cornerRadius: CGFloat, rampSize: NSSize? = nil) -> CGPath {
        let cornerRadius = max(0, min(cornerRadius, rect.width * 0.5, rect.height * 0.5))

        let path = CGMutablePath()

        // Bottom Edge
        if let rampSize {
            path.move(to: CGPoint(x: rect.minX - rampSize.width, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX + rampSize.width, y: rect.minY))

            // Trailing Ramp
            let trailingRampCenter = CGPoint(x: rect.maxX + rampSize.width, y: rampSize.height)
            path.addArc(center: trailingRampCenter, radius: rampSize.width, startAngle: .pi * 1.5, endAngle: .pi, clockwise: true)
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        // Right Edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))

        // Top-Right Corner
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
                     radius: cornerRadius)

        // Top Edge
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))

        // Top-Left Corner
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
                     radius: cornerRadius)

        // Left Edge
        if let rampSize {
            path.addLine(to: CGPoint(x: rect.minX, y: rampSize.height))

            // Leading Ramp
            let leadingRampCenter = CGPoint(x: rect.minX - rampSize.width, y: rampSize.height)
            path.addArc(center: leadingRampCenter, radius: rampSize.width, startAngle: 0, endAngle: .pi * 1.5, clockwise: true)
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}
