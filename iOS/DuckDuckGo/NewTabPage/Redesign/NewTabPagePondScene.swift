//
//  NewTabPagePondScene.swift
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

import CoreGraphics

struct NewTabPagePondScene: Equatable {
    struct Curve: Equatable {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint

        var path: CGPath {
            let path = CGMutablePath()
            path.move(to: start)
            path.addCurve(to: end, control1: control1, control2: control2)
            return path
        }

        func point(at fraction: CGFloat) -> CGPoint {
            let inverse = 1 - fraction
            return CGPoint(x: inverse * inverse * inverse * start.x + 3 * inverse * inverse * fraction * control1.x
                           + 3 * inverse * fraction * fraction * control2.x + fraction * fraction * fraction * end.x,
                           y: inverse * inverse * inverse * start.y + 3 * inverse * inverse * fraction * control1.y
                           + 3 * inverse * fraction * fraction * control2.y + fraction * fraction * fraction * end.y)
        }
    }

    struct Plant: Equatable {
        let x: CGFloat
        let y: CGFloat
        let height: CGFloat
        let lean: CGFloat

        var stem: Curve {
            let tip = CGPoint(x: x + lean, y: y - height)
            return Curve(start: CGPoint(x: x, y: y),
                         control1: CGPoint(x: x + lean * 0.12, y: y - height * 0.35),
                         control2: CGPoint(x: tip.x - lean * 0.12, y: tip.y + height * 0.12), end: tip)
        }

        var headBounds: CGRect {
            let width = height * 0.09
            return CGRect(x: -width / 2, y: -height * 0.38, width: width, height: height * 0.38 + 0.003)
        }

        var headTransform: CGAffineTransform {
            let length = hypot(lean, height)
            return CGAffineTransform(a: height / length, b: lean / length,
                                     c: -lean / length, d: height / length, tx: stem.end.x, ty: stem.end.y)
        }

        var headPath: CGPath {
            var transform = headTransform
            return CGPath(roundedRect: headBounds, cornerWidth: headBounds.width / 2,
                          cornerHeight: headBounds.width / 2, transform: &transform)
        }
    }

    let glow: CGPoint
    let shoreline: [CGPoint]
    let farBank: [CGPoint]
    let leftBank: [CGPoint]
    let rightBank: [CGPoint]
    let reflectionEdge: Curve
    let ripples: [Curve]
    let glints: [CGRect]
    let lilyPads: [CGRect]
    let plants: [Plant]
    let meadowFlowers: [CGRect]

    init(seed: UInt64) {
        var random = Generator(state: seed)
        glow = CGPoint(x: random.value(in: 0.2 ... 0.8), y: random.value(in: 0.65 ... 0.8))
        let horizon = random.value(in: 0.8 ... 0.825)
        let tilt = random.value(in: -0.018 ... 0.018)
        shoreline = (0 ... 6).map { index in
            let x = CGFloat(index) / 6
            return CGPoint(x: x, y: horizon + sin(x * .pi) * 0.025 + x * tilt + random.value(in: -0.006 ... 0.006))
        }
        let bankHeights: [CGFloat] = [0.085, 0.055, 0.02, 0.006, 0.008, 0.025, 0.035]
        farBank = zip(shoreline, bankHeights).map { point, height in
            CGPoint(x: point.x, y: point.y - height * random.value(in: 0.8 ... 1.2))
        }
        let leftExtent = random.value(in: 0.36 ... 0.46)
        let rightExtent = random.value(in: 0.32 ... 0.42)
        leftBank = (0 ... 5).map { index in
            CGPoint(x: CGFloat(index) / 5 * leftExtent,
                    y: index == 5 ? 1.08 : 0.865 + CGFloat(index) * 0.019 + random.value(in: -0.008 ... 0.008))
        }
        rightBank = (0 ... 5).map { index in
            CGPoint(x: 1 - CGFloat(index) / 5 * rightExtent,
                    y: index == 5 ? 1.08 : 0.84 + pow(CGFloat(index) / 5, 2) * 0.2 + random.value(in: -0.006 ... 0.006))
        }
        reflectionEdge = Curve(start: shoreline[2],
                               control1: CGPoint(x: random.value(in: 0.57 ... 0.7), y: 0.88),
                               control2: CGPoint(x: random.value(in: 0.22 ... 0.3), y: 0.95),
                               end: CGPoint(x: random.value(in: 0.28 ... 0.4), y: 1.05))
        ripples = (0 ..< 2).flatMap { index -> [Curve] in
            let x = random.value(in: 0.45 ... 0.67)
            let y = horizon + 0.025 + CGFloat(index) * 0.075
            let width = random.value(in: 0.1 ... 0.16) * (index == 0 ? 1 : 0.6)
            let depth = random.value(in: 0.015 ... 0.025) * (index == 0 ? 1 : 0.5)
            let start = CGPoint(x: x, y: y)
            let middle = CGPoint(x: x + width * 0.35, y: y + depth)
            return [Curve(start: start, control1: CGPoint(x: x + width * 0.45, y: y + depth * 0.45),
                          control2: CGPoint(x: x + width * 1.15, y: y - depth * 0.8), end: middle),
                    Curve(start: middle, control1: CGPoint(x: x - width * 0.45, y: y + depth * 2.8),
                          control2: CGPoint(x: x + width * 0.5, y: y + depth * 2.3),
                          end: CGPoint(x: x + width * 0.6, y: y + depth * 1.6))]
        }
        glints = (0 ..< 7).map { _ in
            CGRect(x: random.value(in: 0.34 ... 0.77), y: random.value(in: 0.86 ... 0.98),
                   width: random.value(in: 0.004 ... 0.011), height: random.value(in: 0.0015 ... 0.0035))
        }
        let leftShore = Self.bankPath(for: leftBank)
        let rightShore = Self.bankPath(for: rightBank)
        var pads: [CGRect] = []
        let padCount = Int(random.next() % 3 + 4)
        for _ in 0 ..< 80 where pads.count < padCount {
            let y = random.value(in: 0.87 ... 0.975)
            let width = random.value(in: 0.035 ... 0.055) * (0.8 + (y - 0.86) * 3)
            let pad = CGRect(x: random.value(in: 0.32 ... 0.67), y: y, width: width, height: width * 0.28)
            let corners = [CGPoint(x: pad.minX, y: pad.minY), CGPoint(x: pad.maxX, y: pad.minY),
                           CGPoint(x: pad.minX, y: pad.maxY), CGPoint(x: pad.maxX, y: pad.maxY)]
            if !corners.contains(where: { leftShore.contains($0) || rightShore.contains($0) }),
               !pads.contains(where: { $0.insetBy(dx: -0.008, dy: -0.012).intersects(pad) }) {
                pads.append(pad)
            }
        }
        lilyPads = pads.sorted { $0.midY < $1.midY }
        plants = (0 ..< 5).map { index in
            Plant(x: index.isMultiple(of: 2) ? random.value(in: 0.24 ... 0.35) : random.value(in: 0.72 ... 0.8),
                  y: random.value(in: 1.01 ... 1.065), height: random.value(in: 0.12 ... 0.18),
                  lean: random.value(in: -0.065 ... 0.045))
        }
        meadowFlowers = (0 ..< 12).map { index in
            let side = random.value(in: 0.16 ... 0.34)
            let width = random.value(in: 0.014 ... 0.026)
            let isLeft = index.isMultiple(of: 2)
            let shoreY = isLeft ? 0.865 + side / leftExtent * 0.095 : 0.84 + pow(side / rightExtent, 2) * 0.2
            return CGRect(x: isLeft ? side : 1 - side,
                          y: shoreY + random.value(in: 0.014 ... 0.04), width: width, height: width * 0.7)
        }
    }

    static func contour(for points: [CGPoint]) -> CGMutablePath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for (start, end) in zip(points, points.dropFirst()) {
            let middleX = (start.x + end.x) / 2
            path.addCurve(to: end, control1: CGPoint(x: middleX, y: start.y), control2: CGPoint(x: middleX, y: end.y))
        }
        return path
    }

    static func bankPath(for points: [CGPoint]) -> CGPath {
        let path = contour(for: points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: 1.12))
        path.addLine(to: CGPoint(x: first.x, y: 1.12))
        path.closeSubpath()
        return path
    }

    // SplitMix64 keeps seeds stable across launches and OS versions.
    private struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }

        mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
            let fraction = CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53)
            return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        }
    }
}
