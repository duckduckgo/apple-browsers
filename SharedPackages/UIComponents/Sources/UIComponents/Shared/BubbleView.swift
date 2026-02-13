//
//  BubbleView.swift
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

import SwiftUI

/// Identifies which edge of the bubble the arrow should attach to.
/// Offsets are interpreted relative to the flat edge segment.
public enum BubbleArrowEdge {
    /// Arrow on the top edge (offset runs left → right).
    case top
    /// Arrow on the right edge (offset runs top → bottom).
    case right
    /// Arrow on the bottom edge (offset runs left → right).
    case bottom
    /// Arrow on the left edge (offset runs top → bottom).
    case left

    fileprivate var bubbleEdge: Bubble.Edge {
        switch self {
        case .top: return .top
        case .right: return .right
        case .bottom: return .bottom
        case .left: return .left
        }
    }
}

// MARK: - Bubble Shape Definition

/// A shape representing a rectangular bubble with a directional arrow and rounded corners.
/// Used internally by BubbleView.
struct Bubble: InsettableShape {
    let arrowLength: CGFloat
    let arrowWidth: CGFloat
    let arrowPlacement: ArrowPlacement
    let cornerRadius: CGFloat
    let bend: CGFloat
    let finSideCurve: CGFloat
    let finTipRadius: CGFloat
    let finTipRoundness: CGFloat

    enum ArrowPlacement {
        case percent(CGFloat)
        case edge(Edge, offset: CGFloat)
    }

    func path(in rect: CGRect) -> Path {

        let radius = max(0, cornerRadius)
        guard rect.width >= 2 * radius, rect.height >= 2 * radius else {
            return Path(roundedRect: rect, cornerRadius: radius)
        }

        let (minX, minY) = (rect.minX, rect.minY)
        let (maxX, maxY) = (rect.maxX, rect.maxY)

        let arrowPositionPercent: CGFloat
        switch arrowPlacement {
        case let .percent(value):
            arrowPositionPercent = value
        case let .edge(edge, offset):
            arrowPositionPercent = Bubble.arrowPositionPercent(
                edge: edge,
                offset: offset,
                rect: rect,
                radius: radius,
                arrowWidth: arrowWidth
            )
        }

        let (arrowEdge, arrowCenter) = Bubble.arrowPlacement(
            in: rect,
            radius: radius,
            arrowWidth: arrowWidth,
            arrowPositionPercent: arrowPositionPercent
        )
        let arrowCenterX = arrowCenter.x
        let arrowCenterY = arrowCenter.y

        // Calculate Arrow Base Points (p1, p2)
        let halfArrowWidth = arrowWidth / 2
        var p1, p2: CGPoint
        switch arrowEdge {
        case .top:
            p1 = CGPoint(x: arrowCenterX - halfArrowWidth, y: arrowCenterY)
            p2 = CGPoint(x: arrowCenterX + halfArrowWidth, y: arrowCenterY)
        case .right:
            p1 = CGPoint(x: arrowCenterX, y: arrowCenterY - halfArrowWidth)
            p2 = CGPoint(x: arrowCenterX, y: arrowCenterY + halfArrowWidth)
        case .bottom:
            p1 = CGPoint(x: arrowCenterX + halfArrowWidth, y: arrowCenterY)
            p2 = CGPoint(x: arrowCenterX - halfArrowWidth, y: arrowCenterY)
        case .left:
            p1 = CGPoint(x: arrowCenterX, y: arrowCenterY + halfArrowWidth)
            p2 = CGPoint(x: arrowCenterX, y: arrowCenterY - halfArrowWidth)
        }

        let outwardNormal = Bubble.outwardNormal(for: arrowEdge)
        let tangent = Bubble.edgeTangent(for: arrowEdge)
        let bendOffset = bend * halfArrowWidth
        let tip = CGPoint(x: arrowCenterX + outwardNormal.x * arrowLength + tangent.x * bendOffset,
                          y: arrowCenterY + outwardNormal.y * arrowLength + tangent.y * bendOffset)
        let effectiveTipRadius = finTipRadius

        // Define Rounded Rectangle Corner Points & Arc Centers
        let pointTopLeft = CGPoint(x: minX + radius, y: minY)
        let pointTopRight = CGPoint(x: maxX - radius, y: minY)
        let pointRightBottom = CGPoint(x: maxX, y: maxY - radius)
        let pointBottomLeft = CGPoint(x: minX + radius, y: maxY)
        let pointLeftTop = CGPoint(x: minX, y: minY + radius)

        let centerTopLeft = CGPoint(x: minX + radius, y: minY + radius)
        let centerTopRight = CGPoint(x: maxX - radius, y: minY + radius)
        let centerBottomRight = CGPoint(x: maxX - radius, y: maxY - radius)
        let centerBottomLeft = CGPoint(x: minX + radius, y: maxY - radius)

        // Draw!
        var path = Path()
        path.move(to: pointTopLeft)

        if arrowEdge == .top { path.addLine(to: p1); Bubble.addFin(to: &path, from: p1, to: p2, tip: tip, tipRadius: effectiveTipRadius, tipRoundness: finTipRoundness, sideCurve: finSideCurve, bend: bend) }
        path.addLine(to: pointTopRight)
        if radius > 0 { path.addArc(center: centerTopRight, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }

        if arrowEdge == .right { path.addLine(to: p1); Bubble.addFin(to: &path, from: p1, to: p2, tip: tip, tipRadius: effectiveTipRadius, tipRoundness: finTipRoundness, sideCurve: finSideCurve, bend: bend) }
        path.addLine(to: pointRightBottom)
        if radius > 0 { path.addArc(center: centerBottomRight, radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) }

        if arrowEdge == .bottom { path.addLine(to: p1); Bubble.addFin(to: &path, from: p1, to: p2, tip: tip, tipRadius: effectiveTipRadius, tipRoundness: finTipRoundness, sideCurve: finSideCurve, bend: bend) }
        path.addLine(to: pointBottomLeft)
        if radius > 0 { path.addArc(center: centerBottomLeft, radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false) }

        if arrowEdge == .left { path.addLine(to: p1); Bubble.addFin(to: &path, from: p1, to: p2, tip: tip, tipRadius: effectiveTipRadius, tipRoundness: finTipRoundness, sideCurve: finSideCurve, bend: bend) }
        path.addLine(to: pointLeftTop)
        if radius > 0 { path.addArc(center: centerTopLeft, radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }

        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
         // Basic inset conformance, strokeBorder handles the rest
        return self
    }

    // Make Edge internal (default) so BubbleView can access it
    enum Edge { case top, right, bottom, left }

    private static func arrowPlacement(
        in rect: CGRect,
        radius: CGFloat,
        arrowWidth: CGFloat,
        arrowPositionPercent: CGFloat
    ) -> (edge: Edge, center: CGPoint) {
        let (minX, minY) = (rect.minX, rect.minY)
        let (maxX, maxY) = (rect.maxX, rect.maxY)

        let metrics = flatMetrics(rect: rect, radius: radius, arrowWidth: arrowWidth)
        let adjustedPercent = arrowPositionPercent.truncatingRemainder(dividingBy: 100.0)
        let effectivePercent = min(99.9, max(0.1, adjustedPercent)) / 100.0
        let targetFlatDistance = metrics.flatPerimeter * effectivePercent

        var arrowEdge: Edge = .top
        var arrowCenterX: CGFloat = 0
        var arrowCenterY: CGFloat = 0

        // Determine Edge and Center Point ON THE FLAT SECTION
        if targetFlatDistance <= metrics.flatWidth { // Top Flat Edge
            arrowEdge = .top
            var centerOnFlat = targetFlatDistance
            if metrics.flatWidth > 0 { // Only clamp if there is a flat edge
                centerOnFlat = clampToSafeDistance(
                    centerOnFlat,
                    length: metrics.flatWidth,
                    safeDistance: metrics.safeDistance
                )
            }
            arrowCenterX = minX + radius + centerOnFlat
            arrowCenterY = minY
        } else if targetFlatDistance <= metrics.flatWidth + metrics.flatHeight { // Right Flat Edge
            arrowEdge = .right
            var centerOnFlat = targetFlatDistance - metrics.flatWidth
            if metrics.flatHeight > 0 {
                centerOnFlat = clampToSafeDistance(
                    centerOnFlat,
                    length: metrics.flatHeight,
                    safeDistance: metrics.safeDistance
                )
            }
            arrowCenterX = maxX
            arrowCenterY = minY + radius + centerOnFlat
        } else if targetFlatDistance <= 2 * metrics.flatWidth + metrics.flatHeight { // Bottom Flat Edge
            arrowEdge = .bottom
            var centerOnFlat = targetFlatDistance - (metrics.flatWidth + metrics.flatHeight)
            if metrics.flatWidth > 0 {
                centerOnFlat = clampToSafeDistance(
                    centerOnFlat,
                    length: metrics.flatWidth,
                    safeDistance: metrics.safeDistance
                )
            }
            arrowCenterX = maxX - radius - centerOnFlat
            arrowCenterY = maxY
        } else { // Left Flat Edge
            arrowEdge = .left
            var centerOnFlat = targetFlatDistance - (metrics.flatWidth + metrics.flatHeight + metrics.flatWidth)
            if metrics.flatHeight > 0 {
                centerOnFlat = clampToSafeDistance(
                    centerOnFlat,
                    length: metrics.flatHeight,
                    safeDistance: metrics.safeDistance
                )
            }
            arrowCenterX = minX
            arrowCenterY = maxY - radius - centerOnFlat
        }

        return (arrowEdge, CGPoint(x: arrowCenterX, y: arrowCenterY))
    }

    private static func arrowPositionPercent(
        edge: Edge,
        offset: CGFloat,
        rect: CGRect,
        radius: CGFloat,
        arrowWidth: CGFloat
    ) -> CGFloat {
        // BubbleView positions the arrow center along the flat perimeter, clockwise:
        // Top → Right → Bottom → Left. Offsets here are local:
        // - top/bottom: left → right
        // - left/right: top → bottom
        let metrics = flatMetrics(rect: rect, radius: radius, arrowWidth: arrowWidth)
        let o = max(0.0, min(1.0, offset))

        func offsetDistance(_ length: CGFloat) -> CGFloat {
            let clamped = clampToSafeDistance(
                metrics.safeDistance + o * max(0.0, length - 2 * metrics.safeDistance),
                length: length,
                safeDistance: metrics.safeDistance
            )
            return clamped
        }

        let target: CGFloat
        switch edge {
        case .top:
            target = offsetDistance(metrics.flatWidth)
        case .right:
            target = metrics.flatWidth + offsetDistance(metrics.flatHeight)
        case .bottom:
            target = metrics.flatWidth + metrics.flatHeight + (metrics.flatWidth - offsetDistance(metrics.flatWidth))
        case .left:
            target = metrics.flatWidth + metrics.flatHeight + metrics.flatWidth + (metrics.flatHeight - offsetDistance(metrics.flatHeight))
        }

        let percent = (target / metrics.flatPerimeter) * 100
        return max(0.1, min(99.9, percent))
    }

    private static func flatMetrics(
        rect: CGRect,
        radius: CGFloat,
        arrowWidth: CGFloat
    ) -> (flatWidth: CGFloat, flatHeight: CGFloat, flatPerimeter: CGFloat, safeDistance: CGFloat) {
        let flatWidth = rect.width - 2 * radius
        let flatHeight = rect.height - 2 * radius
        let flatPerimeter = max(0.001, 2 * (flatWidth + flatHeight))
        let safeDistance = arrowWidth / 2 + 1.0
        return (flatWidth, flatHeight, flatPerimeter, safeDistance)
    }

    private static func clampToSafeDistance(
        _ value: CGFloat,
        length: CGFloat,
        safeDistance: CGFloat
    ) -> CGFloat {
        guard length > 0 else { return 0 }
        let safe = min(length / 2, safeDistance)
        return max(safe, min(length - safe, value))
    }

    private static func outwardNormal(for edge: Edge) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: 0, y: -1)
        case .right: return CGPoint(x: 1, y: 0)
        case .bottom: return CGPoint(x: 0, y: 1)
        case .left: return CGPoint(x: -1, y: 0)
        }
    }

    private static func edgeTangent(for edge: Edge) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: 1, y: 0)
        case .right: return CGPoint(x: 0, y: 1)
        case .bottom: return CGPoint(x: -1, y: 0)
        case .left: return CGPoint(x: 0, y: -1)
        }
    }

    private static func addFin(
        to path: inout Path,
        from p1: CGPoint,
        to p2: CGPoint,
        tip: CGPoint,
        tipRadius: CGFloat,
        tipRoundness: CGFloat,
        sideCurve: CGFloat,
        bend: CGFloat
    ) {
        let sideLength1 = distance(p1, tip)
        let sideLength2 = distance(p2, tip)
        guard sideLength1 > 0.001, sideLength2 > 0.001 else {
            path.addLine(to: tip)
            path.addLine(to: p2)
            return
        }

        let maxTipCut = max(0, min(sideLength1, sideLength2) - 0.001)
        let roundness = max(0, min(1, tipRoundness))
        let tipCut = min(maxTipCut * roundness, max(0, tipRadius))
        let curveStrength = max(0, min(1, sideCurve)) * min(sideLength1, sideLength2) * min(1, abs(bend)) * 0.35
        let baseMid = CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
        let baseDX = p2.x - p1.x
        let baseDY = p2.y - p1.y
        let baseLen = sqrt(baseDX * baseDX + baseDY * baseDY)
        let tanX = baseLen > 0.001 ? baseDX / baseLen : 0
        let tanY = baseLen > 0.001 ? baseDY / baseLen : 0
        let bendDir = (tip.x - baseMid.x) * tanX + (tip.y - baseMid.y) * tanY
        let s1 = (p1.x - baseMid.x) * tanX + (p1.y - baseMid.y) * tanY
        let outerIsFirst: Bool
        if abs(bendDir) < 0.001 {
            outerIsFirst = sideLength1 >= sideLength2
        } else {
            outerIsFirst = s1 * bendDir > 0
        }

        let interior1 = interiorNormal(from: p1, to: tip, interiorPoint: p2)
        let interior2 = interiorNormal(from: tip, to: p2, interiorPoint: p1)
        let normal1 = outerIsFirst ? interior1 : CGPoint(x: -interior1.x, y: -interior1.y)
        let normal2 = outerIsFirst ? CGPoint(x: -interior2.x, y: -interior2.y) : interior2

        if tipCut <= 0 {
            if curveStrength > 0.001 {
                let c1 = controlPoint(from: p1, to: tip, normal: normal1, curveAmount: curveStrength)
                path.addQuadCurve(to: tip, control: c1)
                let c2 = controlPoint(from: tip, to: p2, normal: normal2, curveAmount: curveStrength)
                path.addQuadCurve(to: p2, control: c2)
            } else {
                path.addLine(to: tip)
                path.addLine(to: p2)
            }
            return
        }

        let t1 = point(from: tip, toward: p1, distance: tipCut)
        let t2 = point(from: tip, toward: p2, distance: tipCut)

        if curveStrength > 0.001 {
            let c1 = controlPoint(from: p1, to: t1, normal: normal1, curveAmount: curveStrength)
            path.addQuadCurve(to: t1, control: c1)
        } else {
            path.addLine(to: t1)
        }

        let tipSpan = distance(t1, t2)
        if tipSpan > 0.001 {
            let u1 = unitVector(from: t1, toward: tip)
            let u2 = unitVector(from: t2, toward: tip)
            let k = min(tipSpan * 0.6, tipCut * 1.5)
            let cTip1 = CGPoint(x: t1.x + u1.x * k, y: t1.y + u1.y * k)
            let cTip2 = CGPoint(x: t2.x + u2.x * k, y: t2.y + u2.y * k)
            path.addCurve(to: t2, control1: cTip1, control2: cTip2)
        } else {
            path.addLine(to: t2)
        }

        if curveStrength > 0.001 {
            let c2 = controlPoint(from: t2, to: p2, normal: normal2, curveAmount: curveStrength)
            path.addQuadCurve(to: p2, control: c2)
        } else {
            path.addLine(to: p2)
        }
    }

    private static func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }

    private static func point(from origin: CGPoint, toward target: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0.001 else { return origin }
        let ux = dx / length
        let uy = dy / length
        return CGPoint(x: origin.x + ux * distance, y: origin.y + uy * distance)
    }

    private static func unitVector(from origin: CGPoint, toward target: CGPoint) -> CGPoint {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0.001 else { return .zero }
        return CGPoint(x: dx / length, y: dy / length)
    }

    private static func interiorNormal(from start: CGPoint, to end: CGPoint, interiorPoint: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0.001 else { return .zero }
        let leftX = -dy / length
        let leftY = dx / length
        let cross = dx * (interiorPoint.y - start.y) - dy * (interiorPoint.x - start.x)
        let sign: CGFloat = cross >= 0 ? 1 : -1
        return CGPoint(x: leftX * sign, y: leftY * sign)
    }

    private static func controlPoint(from start: CGPoint, to end: CGPoint, normal: CGPoint, curveAmount: CGFloat) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        return CGPoint(x: mid.x + normal.x * curveAmount,
                       y: mid.y + normal.y * curveAmount)
    }

}

// MARK: - Bubble View Definition

/// A view that displays content within a bubble shape, automatically sizing to the content.
public struct BubbleView<Content: View>: View {
    // Content to display inside the bubble
    let content: Content

    // Bubble styling parameters
    let arrowLength: CGFloat
    let arrowWidth: CGFloat
    let arrowPlacement: Bubble.ArrowPlacement
    let cornerRadius: CGFloat
    let bend: CGFloat
    let finSideCurve: CGFloat
    let finTipRadius: CGFloat
    let finTipRoundness: CGFloat
    let fillColor: Color
    let borderColor: Color
    let borderWidth: CGFloat
    let contentPadding: EdgeInsets // Padding around the content

    // Internal bubble shape instance
    private var bubbleShape: Bubble {
        Bubble(arrowLength: arrowLength,
               arrowWidth: arrowWidth,
               arrowPlacement: arrowPlacement,
               cornerRadius: cornerRadius,
               bend: bend,
               finSideCurve: finSideCurve,
               finTipRadius: finTipRadius,
               finTipRoundness: finTipRoundness)
    }

    public var body: some View {
        content
            // Add padding around the content BEFORE applying background/overlay
            .padding(contentPadding)
            // Apply the bubble shape as the background (fill)
            .background(
                bubbleShape.fill(fillColor)
            )
            // Apply the bubble shape as an overlay (border)
            .overlay(
                bubbleShape.strokeBorder(borderColor, lineWidth: borderWidth)
            )
            // Add final padding to ensure arrow/border doesn't get clipped
            .padding(.top, arrowEdge == .top ? finDepth : 0)
            .padding(.bottom, arrowEdge == .bottom ? finDepth : 0)
            .padding(.leading, arrowEdge == .left ? finDepth : 0)
            .padding(.trailing, arrowEdge == .right ? finDepth : 0)
    }

    // Helper to determine which edge the arrow is on based on parameters
    // Needed for final padding adjustment
    private var arrowEdge: Bubble.Edge {
        switch arrowPlacement {
        case let .edge(edge, _):
            return edge
        case let .percent(arrowPositionPercent):
            let radius = max(0, cornerRadius)
            // Estimate width/height (we don't have the final rect here,
            // but we only need rough estimates for edge calculation)
            // A small non-zero value is assumed if radius is large relative to arrowWidth/Height
            let estWidth = max(0.1, 100 - 2 * radius) // Assume a nominal size
            let estHeight = max(0.1, 50 - 2 * radius)
            let flatWidth = estWidth - 2 * radius
            let flatHeight = estHeight - 2 * radius
            let flatPerimeter = max(0.001, 2 * (flatWidth + flatHeight))

            let adjustedPercent = arrowPositionPercent.truncatingRemainder(dividingBy: 100.0)
            let effectivePercent = min(99.9, max(0.1, adjustedPercent)) / 100.0
            let targetFlatDistance = flatPerimeter * effectivePercent

            if targetFlatDistance <= flatWidth {
                return .top
            } else if targetFlatDistance <= flatWidth + flatHeight {
                return .right
            } else if targetFlatDistance <= 2 * flatWidth + flatHeight {
                return .bottom
            } else {
                return .left
            }
        }
    }

    private var finDepth: CGFloat {
        max(0, arrowLength)
    }

     /// Initializer with explicit parameters.
     ///
     /// - Parameters:
     ///   - arrowLength: Length of the arrow pointer.
     ///   - arrowWidth: Width of the arrow pointer's base.
     ///   - arrowPositionPercent: Position (0-100) along the flat edges where the arrow center should be.
     ///   - cornerRadius: Radius for the bubble's corners.
     ///   - bend: Amount of fin bend. `0` is straight; positive bends right when the arrow is on top (clockwise), negative bends left. Values beyond `1` push the tip further along the edge.
     ///   - finSideCurve: Curvature for fin sides. `0` keeps sides straight; higher values curve the long side outward and short side inward.
     ///   - finTipRadius: Radius for rounding the fin tip.
     ///   - finTipRoundness: 0-1 multiplier for tip rounding to avoid distortion. Default: 0 (sharp).
     ///   - fillColor: Background color of the bubble.
     ///   - borderColor: Color of the bubble's border.
     ///   - borderWidth: Width of the bubble's border.
     ///   - contentPadding: Padding between the content and the bubble edge. Defaults to 10 on all edges.
     ///   - content: A closure returning the View to display inside the bubble.
     public init(
         arrowLength: CGFloat = 15,
         arrowWidth: CGFloat = 30,
         arrowPositionPercent: CGFloat = 10,
         cornerRadius: CGFloat = 10,
         bend: CGFloat = 0,
         finSideCurve: CGFloat = 0,
         finTipRadius: CGFloat = .greatestFiniteMagnitude,
         finTipRoundness: CGFloat = 0,
         fillColor: Color = .blue,
         borderColor: Color = .clear,
         borderWidth: CGFloat = 0,
         contentPadding: EdgeInsets = EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10),
         @ViewBuilder content: () -> Content
     ) {
         self.arrowLength = arrowLength
         self.arrowWidth = arrowWidth
         self.arrowPlacement = .percent(arrowPositionPercent)
         self.cornerRadius = cornerRadius
         self.bend = bend
         self.finSideCurve = finSideCurve
         self.finTipRadius = finTipRadius
         self.finTipRoundness = finTipRoundness
         self.fillColor = fillColor
         self.borderColor = borderColor
         self.borderWidth = borderWidth
         self.contentPadding = contentPadding
         self.content = content()
     }

     /// Initializer with explicit parameters.
     ///
     /// - Parameters:
     ///   - arrowLength: Length of the arrow pointer.
     ///   - arrowWidth: Width of the arrow pointer's base.
     ///   - arrowEdge: Edge where the arrow should appear.
     ///   - arrowOffset: Position along the edge (0.0 = start, 0.5 = center, 1.0 = end).
     ///   - cornerRadius: Radius for the bubble's corners.
     ///   - bend: Amount of fin bend. `0` is straight; positive bends right when the arrow is on top (clockwise), negative bends left. Values beyond `1` push the tip further along the edge.
     ///   - finSideCurve: Curvature for fin sides. `0` keeps sides straight; higher values curve the long side outward and short side inward.
     ///   - finTipRadius: Radius for rounding the fin tip.
     ///   - finTipRoundness: 0-1 multiplier for tip rounding to avoid distortion. Default: 0 (sharp).
     ///   - fillColor: Background color of the bubble.
     ///   - borderColor: Color of the bubble's border.
     ///   - borderWidth: Width of the bubble's border.
     ///   - contentPadding: Padding between the content and the bubble edge. Defaults to 10 on all edges.
     ///   - content: A closure returning the View to display inside the bubble.
     public init(
         arrowLength: CGFloat = 15,
         arrowWidth: CGFloat = 30,
         arrowEdge: BubbleArrowEdge,
         arrowOffset: CGFloat,
         cornerRadius: CGFloat = 10,
         bend: CGFloat = 0,
         finSideCurve: CGFloat = 0,
         finTipRadius: CGFloat = .greatestFiniteMagnitude,
         finTipRoundness: CGFloat = 0,
         fillColor: Color = .blue,
         borderColor: Color = .clear,
         borderWidth: CGFloat = 0,
         contentPadding: EdgeInsets = EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10),
         @ViewBuilder content: () -> Content
     ) {
         self.arrowLength = arrowLength
         self.arrowWidth = arrowWidth
         self.arrowPlacement = .edge(arrowEdge.bubbleEdge, offset: arrowOffset)
         self.cornerRadius = cornerRadius
         self.bend = bend
         self.finSideCurve = finSideCurve
         self.finTipRadius = finTipRadius
         self.finTipRoundness = finTipRoundness
         self.fillColor = fillColor
         self.borderColor = borderColor
         self.borderWidth = borderWidth
         self.contentPadding = contentPadding
         self.content = content()
     }
}

// MARK: - Preview

#if DEBUG
struct BubbleView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 30) {
            BubbleView(
                arrowPositionPercent: 10, // Top edge
                fillColor: .green,
                borderColor: .black,
                borderWidth: 1,
                contentPadding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)
            ) {
                Text("Hello, auto-sizing bubble!")
                    .foregroundColor(.white)
            }

            BubbleView(
                 arrowLength: 20,
                 arrowWidth: 40,
                 arrowPositionPercent: 35, // Right edge
                 cornerRadius: 5,
                 bend: 0.4,
                 finSideCurve: 0.6,
                 finTipRadius: .greatestFiniteMagnitude,
                 finTipRoundness: 0.6,
                 fillColor: .orange,
                 borderColor: .black,
                 borderWidth: 2
             ) {
                 VStack {
                     Image(systemName: "star.fill").foregroundColor(.yellow)
                     Text("Content determines size.")
                     Text("Padding adds space.")
                 }
                 .padding(5) // Inner padding for VStack elements
                 .foregroundColor(.black)
             }

            BubbleView(
                 arrowPositionPercent: 80, // Left edge
                 cornerRadius: 0, // Sharp corners
                 fillColor: Color(white: 0.9),
                 borderColor: .gray,
                 borderWidth: 1
             ) {
                 Text("Short text.")
                     .font(.caption)
                     .foregroundColor(.black)
             }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
    }
}
#endif
