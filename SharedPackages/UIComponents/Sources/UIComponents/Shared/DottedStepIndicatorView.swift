//
//  DottedStepIndicatorView.swift
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

import SwiftUI

/// A horizontal step indicator that displays progress through a multi-step flow using dots.
public struct DottedStepIndicatorView: View {
    /// The index of the currently selected dot (1-based indexing)
    let selectedDot: Int
    /// The total number of dots to display
    let totalDots: Int
    /// Visual styling configuration for the indicator
    let style: Style

    /// Creates a dotted step indicator.
    ///
    /// - Parameters:
    ///   - selectedDot: The currently selected step (1-based). Values outside the valid range are clamped to 1...totalDots.
    ///   - totalDots: The total number of steps. Minimum value is 1.
    ///   - style: Visual styling configuration. Defaults to `Style()` with standard appearance.
    public init(selectedDot: Int, totalDots: Int, style: Style = Style()) {
        // Ensure at least 1 dot
        self.totalDots = max(1, totalDots)
        // Clamp 1...totalDots
        self.selectedDot = max(1, min(selectedDot, self.totalDots))
        self.style = style
    }

    public var body: some View {
        HStack(spacing: style.dotSpacing) {
            ForEach(1...totalDots, id: \.self) { index in
                let size = selectedDot == index ? style.selectedDotSize : style.unselectedDotSize
                let color = selectedDot == index ? style.selectedDotFillColor : style.unselectedDotFillColor
                Capsule()
                    .fill(color)
                    .frame(width: size, height: size)
                    .animation(style.animation, value: selectedDot)
            }
        }
    }

}

public extension DottedStepIndicatorView {

    /// Visual styling configuration for the dotted step indicator.
    struct Style {
        /// Horizontal spacing between dots
        let dotSpacing: CGFloat
        /// Size (width and height) of the selected dot
        let selectedDotSize: CGFloat
        /// Size (width and height) of unselected dots
        let unselectedDotSize: CGFloat
        /// Fill colour of the selected dot
        let selectedDotFillColor: Color
        /// Fill colour of unselected dots
        let unselectedDotFillColor: Color
        /// Animation used when transitioning between steps
        let animation: Animation

        /// Creates a style configuration for the dotted step indicator.
        ///
        /// - Parameters:
        ///   - dotSpacing: Horizontal spacing between dots. Default is 4.0.
        ///   - selectedDotSize: Size of the selected dot. Default is 12.0.
        ///   - unselectedDotSize: Size of unselected dots. Default is 6.0.
        ///   - selectedDotFillColor: Fill color for the selected dot. Default is `.primary`.
        ///   - unselectedDotFillColor: Fill color for unselected dots. Default is `.primary`.
        ///   - animation: Animation for step transitions. Default is `.default`.
        public init(
            dotSpacing: CGFloat = 4.0,
            selectedDotSize: CGFloat = 12.0,
            unselectedDotSize: CGFloat = 6.0,
            selectedDotFillColor: Color = .primary,
            unselectedDotFillColor: Color = .primary,
            animation: Animation = .default
        ) {
            self.dotSpacing = dotSpacing
            self.selectedDotSize = selectedDotSize
            self.unselectedDotSize = unselectedDotSize
            self.selectedDotFillColor = selectedDotFillColor
            self.unselectedDotFillColor = unselectedDotFillColor
            self.animation = animation
        }
    }

}

#Preview("Dotted Step Indicator View") {
    struct PreviewWrapper: View {
        @State var selectedDot = 1
        let totalSteps = 5

        var body: some View {
            VStack(spacing: 50) {
                DottedStepIndicatorView(
                    selectedDot: selectedDot,
                    totalDots: 5,
                    style: .init(
                        selectedDotFillColor: .blue,
                        unselectedDotFillColor: .blue.opacity(0.5)
                    )
                )
                .frame(width: 200, height: 8)

                Button(action: {
                    selectedDot = selectedDot < totalSteps ? selectedDot + 1 : 1
                }, label: {
                    Text(verbatim: "Update Steps")
                })
            }
        }
    }

    return PreviewWrapper()
}
