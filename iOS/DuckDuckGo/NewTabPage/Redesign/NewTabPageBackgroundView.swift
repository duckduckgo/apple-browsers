//
//  NewTabPageBackgroundView.swift
//  DuckDuckGo
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

import DesignResourcesKit
import UIKit

final class NewTabPageBackgroundView: UIView {
    var settings: NewTabPageBackgroundSettings? {
        didSet {
            guard settings != oldValue, let settings else { return }
            if settings.seed != oldValue?.seed {
                scene = NewTabPagePondScene(seed: settings.seed)
            }
            standardImageView.isHidden = settings.isProcedural
            setNeedsDisplay()
        }
    }

    private var scene: NewTabPagePondScene?
    private let standardImageView = UIImageView(image: UIImage(resource: .backgroundPond))

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        contentMode = .redraw
        addSubview(standardImageView)
        standardImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        standardImageView.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard settings?.isProcedural == true, let scene, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: bounds.width, y: bounds.height)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawSky(scene, context: context)
        drawBank(scene.farBank, fill: .bank, context: context)
        drawWater(scene, context: context)
        drawBank(scene.leftBank, fill: .foreground, context: context)
        drawBank(scene.rightBank, fill: .bank, context: context)
        drawMeadow(scene, context: context)
        for plant in scene.plants.sorted(by: { $0.y < $1.y }) {
            drawPlant(plant, context: context)
        }
    }

    private func color(_ color: SingleUseColor.NewTabPagePond, opacity: CGFloat = 1) -> CGColor {
        UIColor(singleUseColor: .newTabPagePond(color)).resolvedColor(with: traitCollection).withAlphaComponent(opacity).cgColor
    }

    private func drawSky(_ scene: NewTabPagePondScene, context: CGContext) {
        context.setFillColor(color(.sky))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: 2.4, y: 1)
        let colors = [color(.haze), color(.sky)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            let center = CGPoint(x: scene.glow.x / 2.4, y: scene.glow.y)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: 0.65, options: .drawsAfterEndLocation)
        }
    }

    private func fill(_ path: CGPath, color: SingleUseColor.NewTabPagePond, context: CGContext) {
        context.addPath(path)
        context.setFillColor(self.color(color))
        context.fillPath()
    }

    private func stroke(_ path: CGPath, color: SingleUseColor.NewTabPagePond, width: CGFloat,
                        opacity: CGFloat = 1, context: CGContext) {
        context.addPath(path)
        context.setStrokeColor(self.color(color, opacity: opacity))
        context.setLineWidth(width)
        context.strokePath()
    }

    private func drawBank(_ points: [CGPoint], fill: SingleUseColor.NewTabPagePond, context: CGContext) {
        self.fill(NewTabPagePondScene.bankPath(for: points), color: fill, context: context)
        stroke(NewTabPagePondScene.contour(for: points), color: .bankOutline, width: 0.0009, context: context)
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(NewTabPagePondScene.bankPath(for: points))
        context.clip()
        for (index, point) in points.dropFirst().dropLast().enumerated() {
            let direction: CGFloat = points[0].x < 0.5 ? -1 : 1
            let line = NewTabPagePondScene.Curve(
                start: CGPoint(x: point.x + direction * 0.035, y: point.y + 0.045),
                control1: CGPoint(x: point.x - direction * 0.04, y: point.y + 0.008),
                control2: CGPoint(x: point.x - direction * 0.055, y: point.y + 0.07),
                end: CGPoint(x: point.x + direction * 0.015, y: point.y + 0.09))
            stroke(line.path, color: .bankOutline, width: 0.0008, opacity: index.isMultiple(of: 2) ? 0.8 : 0.5, context: context)
        }
    }

    private func drawWater(_ scene: NewTabPagePondScene, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let water = NewTabPagePondScene.bankPath(for: scene.shoreline)
        fill(water, color: .water, context: context)
        context.addPath(water)
        context.clip()
        let reflection = NewTabPagePondScene.contour(for: Array(scene.shoreline.prefix(3)))
        let edge = scene.reflectionEdge
        reflection.addCurve(to: edge.end, control1: edge.control1, control2: edge.control2)
        reflection.addLine(to: CGPoint(x: 0, y: edge.end.y))
        reflection.closeSubpath()
        fill(reflection, color: .waterHighlight, context: context)
        stroke(NewTabPagePondScene.contour(for: scene.shoreline), color: .waterLine, width: 0.001, context: context)
        for ripple in scene.ripples {
            stroke(ripple.path, color: .waterLine, width: 0.0006, opacity: 0.55, context: context)
        }
        for (index, glint) in scene.glints.enumerated() {
            context.setFillColor(color(index.isMultiple(of: 3) ? .flower : .waterLine))
            context.fillEllipse(in: glint)
        }
        for (index, pad) in scene.lilyPads.enumerated() {
            drawLilyPad(pad, index: index, context: context)
        }
    }

    private func drawLilyPad(_ frame: CGRect, index: Int, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: frame.midX, y: frame.midY)
        let shadow = CGRect(x: -frame.width * 0.6, y: -frame.height * 0.1, width: frame.width * 1.2, height: frame.height * 1.2)
        context.setFillColor(color(.waterLine, opacity: 0.55))
        context.fillEllipse(in: shadow)
        let pad = CGMutablePath()
        let radiusX = frame.width / 2
        let radiusY = frame.height / 2
        pad.move(to: CGPoint(x: radiusX * 0.7, y: radiusY * 0.7))
        pad.addCurve(to: CGPoint(x: -radiusX, y: 0),
                     control1: CGPoint(x: 0, y: radiusY * 1.5), control2: CGPoint(x: -radiusX, y: radiusY))
        pad.addCurve(to: CGPoint(x: radiusX, y: 0),
                     control1: CGPoint(x: -radiusX, y: -radiusY * 1.4), control2: CGPoint(x: radiusX, y: -radiusY * 1.4))
        pad.addQuadCurve(to: CGPoint(x: radiusX * 0.9, y: radiusY * 0.45), control: CGPoint(x: radiusX, y: radiusY * 0.2))
        pad.addLine(to: CGPoint(x: radiusX * 0.1, y: radiusY * 0.1))
        pad.closeSubpath()
        fill(pad, color: .lilyPad, context: context)
        stroke(pad, color: .lilyPadOutline, width: 0.0009, context: context)
        if index.isMultiple(of: 3) {
            let vein = NewTabPagePondScene.Curve(start: .zero,
                                               control1: CGPoint(x: -radiusX * 0.1, y: -radiusY * 0.5),
                                               control2: CGPoint(x: -radiusX * 0.4, y: -radiusY * 0.6),
                                               end: CGPoint(x: -radiusX * 0.7, y: -radiusY * 0.45))
            stroke(vein.path, color: .bankOutline, width: 0.0006, context: context)
        } else {
            drawLotus(radius: frame.width * 0.22, index: index, context: context)
        }
    }

    private func drawLotus(radius: CGFloat, index: Int, context: CGContext) {
        context.translateBy(x: -radius * 0.15, y: -radius * 0.35)
        for petalIndex in 0 ..< 7 {
            context.saveGState()
            context.rotate(by: CGFloat(petalIndex) * .pi * 2 / 7)
            context.scaleBy(x: 1, y: 0.8)
            let petal = CGMutablePath()
            petal.move(to: CGPoint(x: 0, y: radius * 0.1))
            petal.addCurve(to: CGPoint(x: radius * 0.08, y: -radius),
                           control1: CGPoint(x: -radius * 0.65, y: -radius * 0.4),
                           control2: CGPoint(x: -radius * 0.4, y: -radius * 0.8))
            petal.addCurve(to: .zero, control1: CGPoint(x: radius * 0.5, y: -radius * 0.8),
                           control2: CGPoint(x: radius * 0.55, y: -radius * 0.2))
            petal.closeSubpath()
            fill(petal, color: .flower, context: context)
            stroke(petal, color: .flowerCenter, width: 0.0004, opacity: 0.35, context: context)
            context.restoreGState()
        }
        context.setFillColor(color(index.isMultiple(of: 2) ? .flowerCenter : .reed))
        context.fillEllipse(in: CGRect(x: -radius * 0.28, y: -radius * 0.14, width: radius * 0.56, height: radius * 0.28))
    }

    private func drawPlant(_ plant: NewTabPagePondScene.Plant, context: CGContext) {
        stroke(plant.stem.path, color: .reedOutline, width: 0.0033, context: context)
        stroke(plant.stem.path, color: .reed, width: 0.0017, context: context)
        for direction in [CGFloat(-1), CGFloat(1)] {
            let leaf = CGMutablePath()
            let base = CGPoint(x: plant.x, y: plant.y)
            let tip = CGPoint(x: base.x + direction * 0.035, y: base.y - plant.height * 0.65)
            leaf.move(to: base)
            leaf.addCurve(to: tip, control1: CGPoint(x: base.x + direction * 0.004, y: base.y - plant.height * 0.35),
                          control2: CGPoint(x: tip.x + direction * 0.015, y: tip.y - 0.012))
            leaf.addQuadCurve(to: base, control: CGPoint(x: base.x + direction * 0.015, y: base.y - plant.height * 0.25))
            leaf.closeSubpath()
            fill(leaf, color: direction < 0 ? .lilyPad : .bank, context: context)
            stroke(leaf, color: .bankOutline, width: 0.0007, context: context)
        }
        fill(plant.headPath, color: .reed, context: context)
        stroke(plant.headPath, color: .reedOutline, width: 0.001, context: context)
        context.saveGState()
        defer { context.restoreGState() }
        context.concatenate(plant.headTransform)
        let head = plant.headBounds
        for fraction in [CGFloat(0.25), 0.55, 0.8] {
            let y = head.minY + head.height * fraction
            let band = NewTabPagePondScene.Curve(start: CGPoint(x: head.minX * 0.95, y: y + 0.003),
                                               control1: CGPoint(x: 0, y: y + 0.001),
                                               control2: CGPoint(x: head.maxX, y: y - 0.003),
                                               end: CGPoint(x: head.maxX * 0.95, y: y - 0.005))
            stroke(band.path, color: .reedOutline, width: 0.0007, opacity: 0.7, context: context)
        }
        let highlight = NewTabPagePondScene.Curve(start: CGPoint(x: head.maxX * 0.4, y: head.minY + 0.004),
                                                control1: CGPoint(x: head.maxX * 0.85, y: head.minY + head.height * 0.2),
                                                control2: CGPoint(x: head.maxX * 0.85, y: head.maxY - 0.01),
                                                end: CGPoint(x: head.maxX * 0.5, y: head.maxY - 0.005))
        stroke(highlight.path, color: .reedHighlight, width: 0.001, context: context)
        let whisker = NewTabPagePondScene.Curve(start: CGPoint(x: 0, y: head.minY),
                                              control1: CGPoint(x: 0, y: head.minY - 0.004),
                                              control2: CGPoint(x: -0.002, y: head.minY - 0.008),
                                              end: CGPoint(x: -0.003, y: head.minY - 0.012))
        stroke(whisker.path, color: .reedOutline, width: 0.0007, context: context)
    }

    private func drawMeadow(_ scene: NewTabPagePondScene, context: CGContext) {
        let left = NewTabPagePondScene.bankPath(for: scene.leftBank)
        let right = NewTabPagePondScene.bankPath(for: scene.rightBank)
        for (index, frame) in scene.meadowFlowers.enumerated() {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard left.contains(center) || right.contains(center) else { continue }
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            for petal in 0 ..< 5 {
                context.saveGState()
                context.rotate(by: CGFloat(petal) * .pi * 2 / 5)
                context.setFillColor(color(index.isMultiple(of: 3) ? .reed : .flower))
                context.fillEllipse(in: CGRect(x: -frame.width * 0.16, y: -frame.height * 0.65,
                                              width: frame.width * 0.32, height: frame.height * 0.6))
                context.restoreGState()
            }
            context.setFillColor(color(index.isMultiple(of: 3) ? .flower : .flowerCenter))
            context.fillEllipse(in: CGRect(x: -frame.width * 0.1, y: -frame.height * 0.12,
                                          width: frame.width * 0.2, height: frame.height * 0.24))
            context.restoreGState()
        }
    }
}
