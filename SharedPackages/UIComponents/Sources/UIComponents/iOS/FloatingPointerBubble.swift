//
//  FloatingPointerBubble.swift
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

#if os(iOS)

import SwiftUI
import DesignResourcesKit

/// A pill with an up-arrow on top that gently bounces to point at the element beneath it.
/// Styling is caller-configurable; the defaults use design-system colours so it can be dropped
/// in anywhere without extra setup.
public struct FloatingPointerBubble: View {

    private let text: String
    private let font: Font
    private let backgroundColor: Color
    private let foregroundColor: Color
    private let pillCornerRadius: CGFloat

    @State private var isBouncing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        text: String,
        // No dax token at 17pt medium.
        font: Font = .system(size: 17, weight: .medium),
        backgroundColor: Color = Color(designSystemColor: .accentPrimary),
        foregroundColor: Color = Color(designSystemColor: .buttonsWhite),
        pillCornerRadius: CGFloat = 16
    ) {
        self.text = text
        self.font = font
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.pillCornerRadius = pillCornerRadius
    }

    public var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .padding(.top, FloatingPointerBubbleShape.arrowHeight)
            .background(
                FloatingPointerBubbleShape(pillCornerRadius: pillCornerRadius)
                    .fill(backgroundColor)
            )
            .compositingGroup()
            .offset(y: isBouncing ? -8 : 0)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: isBouncing
            )
            .onAppear {
                guard !reduceMotion else { return }
                isBouncing = true
            }
    }
}

/// Single continuous outline combining an up-arrow at top with a pill at bottom.
private struct FloatingPointerBubbleShape: Shape {

    /// Vertical space the arrow occupies above the pill (apex to shaft base), in rect coordinates.
    static let arrowHeight: CGFloat = arrowPath.boundingRect.maxY

    var pillCornerRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        Path { path in
            let pillTopY = rect.minY + Self.arrowHeight
            let pillHeight = rect.maxY - pillTopY
            let radius = min(pillCornerRadius, pillHeight / 2)

            // ----- Pill (resizable: tracks the label's width and height) -----
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: pillTopY, width: rect.width, height: pillHeight),
                cornerSize: CGSize(width: radius, height: radius)
            )

            // ----- Arrow (fixed size, centered on top) -----
            path.addPath(
                Self.arrowPath,
                transform: CGAffineTransform(translationX: rect.midX - Self.arrowCenterX, y: rect.minY)
            )
        }
    }

    /// Horizontal center of the arrow.
    private static let arrowCenterX: CGFloat = arrowPath.boundingRect.midX

    /// Arrow subpath: apex at y~0, shaft base at y~33, so it slots directly above the pill top.
    private static let arrowPath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 61.5859, y: 0.585786))
        path.addCurve(to: CGPoint(x: 64.4141, y: 0.585786),
                      control1: CGPoint(x: 62.367, y: -0.195262),
                      control2: CGPoint(x: 63.633, y: -0.195262))
        path.addLine(to: CGPoint(x: 77.1426, y: 13.3133))
        path.addCurve(to: CGPoint(x: 77.1426, y: 16.1424),
                      control1: CGPoint(x: 77.9235, y: 14.0944),
                      control2: CGPoint(x: 77.9236, y: 15.3614))
        path.addCurve(to: CGPoint(x: 74.3135, y: 16.1424),
                      control1: CGPoint(x: 76.3616, y: 16.9234),
                      control2: CGPoint(x: 75.0945, y: 16.9234))
        path.addLine(to: CGPoint(x: 65, y: 6.82797))
        path.addLine(to: CGPoint(x: 65, y: 32.9998))
        path.addLine(to: CGPoint(x: 61, y: 32.9998))
        path.addLine(to: CGPoint(x: 61, y: 6.82797))
        path.addLine(to: CGPoint(x: 51.6865, y: 16.1424))
        path.addCurve(to: CGPoint(x: 48.8574, y: 16.1424),
                      control1: CGPoint(x: 50.9055, y: 16.9234),
                      control2: CGPoint(x: 49.6384, y: 16.9234))
        path.addCurve(to: CGPoint(x: 48.8574, y: 13.3133),
                      control1: CGPoint(x: 48.0764, y: 15.3614),
                      control2: CGPoint(x: 48.0765, y: 14.0944))
        path.addLine(to: CGPoint(x: 61.5859, y: 0.585786))
        path.closeSubpath()
        return path
    }()
}

#Preview("Tap allow") {
    FloatingPointerBubble(text: "Tap allow")
        .padding()
        .background(Color(designSystemColor: .surfaceTertiary))
}

#Preview("Dark") {
    FloatingPointerBubble(text: "Tap allow")
        .padding()
        .background(Color(designSystemColor: .surfaceTertiary))
        .preferredColorScheme(.dark)
}

#endif
