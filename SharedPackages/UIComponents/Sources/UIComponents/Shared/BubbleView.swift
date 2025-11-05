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

// MARK: - Bubble Shape Definition

/// A shape representing a rectangular bubble with a directional arrow and rounded corners.
/// Used internally by BubbleView.
public struct Bubble: InsettableShape {
    let arrowLength: CGFloat
    let arrowWidth: CGFloat
    let arrowPositionPercent: CGFloat
    let cornerRadius: CGFloat

    // swiftlint:disable:next cyclomatic_complexity
    public func path(in rect: CGRect) -> Path {

        let radius = max(0, cornerRadius)
        guard rect.width >= 2 * radius, rect.height >= 2 * radius else {
            return Path(roundedRect: rect, cornerRadius: radius)
        }

        let (minX, minY) = (rect.minX, rect.minY)
        let (width, height) = (rect.width, rect.height)
        let (maxX, maxY) = (rect.maxX, rect.maxY)

        // Calculate Arrow Position on FLAT Edges
        let flatWidth = width - 2 * radius
        let flatHeight = height - 2 * radius
        // Ensure flat perimeter is positive to avoid division by zero or nonsensical calculations
        let flatPerimeter = max(0.001, 2 * (flatWidth + flatHeight)) // Use max to prevent division by zero if no flat area

        let adjustedPercent = arrowPositionPercent.truncatingRemainder(dividingBy: 100.0)
        let effectivePercent = min(99.9, max(0.1, adjustedPercent)) / 100.0
        let targetFlatDistance = flatPerimeter * effectivePercent
        let flatEdgeSafeDistance = arrowWidth / 2 + 1.0

        var arrowEdge: Edge = .top
        var arrowCenterX: CGFloat = 0
        var arrowCenterY: CGFloat = 0

        // Determine Edge and Center Point ON THE FLAT SECTION
        if targetFlatDistance <= flatWidth { // Top Flat Edge
            arrowEdge = .top
            var centerOnFlat = targetFlatDistance
            if flatWidth > 0 { // Only clamp if there is a flat edge
                 centerOnFlat = max(flatEdgeSafeDistance, min(flatWidth - flatEdgeSafeDistance, centerOnFlat))
            }
            arrowCenterX = minX + radius + centerOnFlat
            arrowCenterY = minY
        } else if targetFlatDistance <= flatWidth + flatHeight { // Right Flat Edge
            arrowEdge = .right
            var centerOnFlat = targetFlatDistance - flatWidth
             if flatHeight > 0 {
                 centerOnFlat = max(flatEdgeSafeDistance, min(flatHeight - flatEdgeSafeDistance, centerOnFlat))
            }
            arrowCenterX = maxX
            arrowCenterY = minY + radius + centerOnFlat
        } else if targetFlatDistance <= 2 * flatWidth + flatHeight { // Bottom Flat Edge
            arrowEdge = .bottom
            var centerOnFlat = targetFlatDistance - (flatWidth + flatHeight)
            if flatWidth > 0 {
                 centerOnFlat = max(flatEdgeSafeDistance, min(flatWidth - flatEdgeSafeDistance, centerOnFlat))
            }
            arrowCenterX = maxX - radius - centerOnFlat
            arrowCenterY = maxY
        } else { // Left Flat Edge
            arrowEdge = .left
            var centerOnFlat = targetFlatDistance - (flatWidth + flatHeight + flatWidth)
            if flatHeight > 0 {
                 centerOnFlat = max(flatEdgeSafeDistance, min(flatHeight - flatEdgeSafeDistance, centerOnFlat))
            }
            arrowCenterX = minX
            arrowCenterY = maxY - radius - centerOnFlat
        }

        // Calculate Arrow Points (p1, p2, tip)
        let halfArrowWidth = arrowWidth / 2
        var p1, p2, tip: CGPoint
        switch arrowEdge {
        case .top:    p1 = CGPoint(x: arrowCenterX - halfArrowWidth, y: arrowCenterY); p2 = CGPoint(x: arrowCenterX + halfArrowWidth, y: arrowCenterY); tip = CGPoint(x: arrowCenterX, y: arrowCenterY - arrowLength)
        case .right:  p1 = CGPoint(x: arrowCenterX, y: arrowCenterY - halfArrowWidth); p2 = CGPoint(x: arrowCenterX, y: arrowCenterY + halfArrowWidth); tip = CGPoint(x: arrowCenterX + arrowLength, y: arrowCenterY)
        case .bottom: p1 = CGPoint(x: arrowCenterX + halfArrowWidth, y: arrowCenterY); p2 = CGPoint(x: arrowCenterX - halfArrowWidth, y: arrowCenterY); tip = CGPoint(x: arrowCenterX, y: arrowCenterY + arrowLength)
        case .left:   p1 = CGPoint(x: arrowCenterX, y: arrowCenterY + halfArrowWidth); p2 = CGPoint(x: arrowCenterX, y: arrowCenterY - halfArrowWidth); tip = CGPoint(x: arrowCenterX - arrowLength, y: arrowCenterY)
        }

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

        if arrowEdge == .top { path.addLine(to: p1); path.addLine(to: tip); path.addLine(to: p2) }
        path.addLine(to: pointTopRight)
        if radius > 0 { path.addArc(center: centerTopRight, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }

        if arrowEdge == .right { path.addLine(to: p1); path.addLine(to: tip); path.addLine(to: p2) }
        path.addLine(to: pointRightBottom)
        if radius > 0 { path.addArc(center: centerBottomRight, radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) }

        if arrowEdge == .bottom { path.addLine(to: p1); path.addLine(to: tip); path.addLine(to: p2) }
        path.addLine(to: pointBottomLeft)
        if radius > 0 { path.addArc(center: centerBottomLeft, radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false) }

        if arrowEdge == .left { path.addLine(to: p1); path.addLine(to: tip); path.addLine(to: p2) }
        path.addLine(to: pointLeftTop)
        if radius > 0 { path.addArc(center: centerTopLeft, radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }

        path.closeSubpath()
        return path
    }

    public func inset(by amount: CGFloat) -> some InsettableShape {
         // Basic inset conformance, strokeBorder handles the rest
        return self
    }

    // Make Edge public so BubbleView can access it
    public enum Edge { case top, right, bottom, left }
}

// MARK: - Bubble View Definition

/// A view that displays content within a bubble shape, automatically sizing to the content.
public struct BubbleView<Content: View>: View {
    // Content to display inside the bubble
    let content: Content

    // Bubble styling parameters
    let arrowLength: CGFloat
    let arrowWidth: CGFloat
    let arrowPositionPercent: CGFloat // 0-100, position along FLAT edges
    let cornerRadius: CGFloat
    let fillColor: Color
    let borderColor: Color
    let borderWidth: CGFloat
    let paddingAmount: CGFloat // Padding around the content

    // Internal bubble shape instance
    private var bubbleShape: Bubble {
        Bubble(arrowLength: arrowLength,
               arrowWidth: arrowWidth,
               arrowPositionPercent: arrowPositionPercent,
               cornerRadius: cornerRadius)
    }

    public var body: some View {
        content
            // Add padding around the content BEFORE applying background/overlay
            .padding(paddingAmount)
            // Apply the bubble shape as the background (fill)
            .background(
                bubbleShape.fill(fillColor)
            )
            // Apply the bubble shape as an overlay (border)
            .overlay(
                bubbleShape.strokeBorder(borderColor, lineWidth: borderWidth)
            )
            // Add final padding to ensure arrow/border doesn't get clipped
            .padding(.top, arrowEdge == .top ? arrowLength : 0)
            .padding(.bottom, arrowEdge == .bottom ? arrowLength : 0)
            .padding(.leading, arrowEdge == .left ? arrowLength : 0)
            .padding(.trailing, arrowEdge == .right ? arrowLength : 0)
    }

    // Helper to determine which edge the arrow is on based on parameters
    // Needed for final padding adjustment
    private var arrowEdge: Bubble.Edge {
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

     /// Initializer with explicit parameters.
     ///
     /// - Parameters:
     ///   - arrowLength: Length of the arrow pointer.
     ///   - arrowWidth: Width of the arrow pointer's base.
     ///   - arrowPositionPercent: Position (0-100) along the flat edges where the arrow center should be.
     ///   - cornerRadius: Radius for the bubble's corners.
     ///   - fillColor: Background color of the bubble.
     ///   - borderColor: Color of the bubble's border.
     ///   - borderWidth: Width of the bubble's border.
     ///   - paddingAmount: Padding between the content and the bubble edge. Defaults to 10.
     ///   - content: A closure returning the View to display inside the bubble.
     public init(
         arrowLength: CGFloat = 15,
         arrowWidth: CGFloat = 30,
         arrowPositionPercent: CGFloat = 10,
         cornerRadius: CGFloat = 10,
         fillColor: Color = .blue,
         borderColor: Color = .clear,
         borderWidth: CGFloat = 0,
         paddingAmount: CGFloat = 10,
         @ViewBuilder content: () -> Content
     ) {
         self.arrowLength = arrowLength
         self.arrowWidth = arrowWidth
         self.arrowPositionPercent = arrowPositionPercent
         self.cornerRadius = cornerRadius
         self.fillColor = fillColor
         self.borderColor = borderColor
         self.borderWidth = borderWidth
         self.paddingAmount = paddingAmount
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
                paddingAmount: 15
            ) {
                Text("Hello, auto-sizing bubble!")
                    .foregroundColor(.white)
            }

             BubbleView(
                 arrowLength: 20,
                 arrowWidth: 40,
                 arrowPositionPercent: 35, // Right edge
                 cornerRadius: 5,
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
