//
//  PinnedTabRampView.swift
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

/**
 `PinnedTabRampView` and its supporting `RampShape` are used to render the distinctive S-shaped corners
 for pinned tabs in the tab bar. This visual effect is achieved by drawing a quarter-circle "ramp"
 on either side of the tab, which visually connects the tab to the tab bar background in a smooth, modern way.

 The `PinnedTabRampView` can be horizontally flipped to support both left and right corners, and its color
 and size are fully configurable. This view is typically used inside a `ZStack` alongside the main tab
 content, and is only visible for selected (active) pinned tabs when the S-shaped style is enabled.

 The logic and parameters are kept consistent with the AppKit `RampView` for maintainability.
 */
struct RampShape: Shape {
    var rampWidth: CGFloat
    var rampHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rampHeight))
        path.addLine(to: CGPoint(x: rampWidth, y: rampHeight))

        path.addArc(
            center: CGPoint(x: 0, y: 0),
            radius: rampWidth,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

struct PinnedTabRampView: View {
    let rampWidth: CGFloat
    let rampHeight: CGFloat
    let isFlippedHorizontally: Bool
    let foregroundColor: Color

    init(rampWidth: CGFloat, rampHeight: CGFloat, isFlippedHorizontally: Bool = false, foregroundColor: Color) {
        self.rampWidth = rampWidth
        self.rampHeight = rampHeight
        self.foregroundColor = foregroundColor
        self.isFlippedHorizontally = isFlippedHorizontally
    }

    var body: some View {
        RampShape(rampWidth: rampWidth, rampHeight: rampHeight)
            .fill(foregroundColor)
            .frame(width: rampWidth, height: rampHeight)
            .scaleEffect(x: isFlippedHorizontally ? -1 : 1, y: 1)
    }
}
