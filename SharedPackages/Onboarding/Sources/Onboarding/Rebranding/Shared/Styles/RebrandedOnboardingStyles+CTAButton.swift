//
//  RebrandedOnboardingStyles+CTAButton.swift
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

public extension OnboardingRebranding.OnboardingStyles {

    struct CTAButtonStyle: ButtonStyle {
        private let backgroundColor: Color
        private let pressedBackgroundColor: Color
        private let foregroundColor: Color
        private let font: Font
        private let verticalPadding: CGFloat
        private let horizontalPadding: CGFloat
        private let cornerRadius: CGFloat
        private let minWidth: CGFloat
        private let minHeight: CGFloat

        public init(
            backgroundColor: Color,
            pressedBackgroundColor: Color,
            foregroundColor: Color,
            font: Font,
            verticalPadding: CGFloat = 8,
            horizontalPadding: CGFloat = 24,
            cornerRadius: CGFloat = 100,
            minWidth: CGFloat = 174,
            minHeight: CGFloat = 32
        ) {
            self.backgroundColor = backgroundColor
            self.pressedBackgroundColor = pressedBackgroundColor
            self.foregroundColor = foregroundColor
            self.font = font
            self.verticalPadding = verticalPadding
            self.horizontalPadding = horizontalPadding
            self.cornerRadius = cornerRadius
            self.minWidth = minWidth
            self.minHeight = minHeight
        }

        public func makeBody(configuration: Configuration) -> some View {
            CTAButtonContent(
                configuration: configuration,
                backgroundColor: backgroundColor,
                pressedBackgroundColor: pressedBackgroundColor,
                foregroundColor: foregroundColor,
                font: font,
                verticalPadding: verticalPadding,
                horizontalPadding: horizontalPadding,
                cornerRadius: cornerRadius,
                minWidth: minWidth,
                minHeight: minHeight
            )
        }

        private struct CTAButtonContent: View {
            let configuration: ButtonStyle.Configuration
            let backgroundColor: Color
            let pressedBackgroundColor: Color
            let foregroundColor: Color
            let font: Font
            let verticalPadding: CGFloat
            let horizontalPadding: CGFloat
            let cornerRadius: CGFloat
            let minWidth: CGFloat
            let minHeight: CGFloat

            @State private var isHovered = false

            var body: some View {
                configuration.label
                    .font(font)
                    .foregroundColor(foregroundColor)
                    .padding(.vertical, verticalPadding)
                    .padding(.horizontal, horizontalPadding)
                    .frame(minWidth: minWidth, minHeight: minHeight)
                    .background(resolvedBackgroundColor)
                    .cornerRadius(cornerRadius)
                    .onHover { hovering in
#if os(macOS)
                        isHovered = hovering
#endif
                    }
            }

            private var resolvedBackgroundColor: Color {
                if configuration.isPressed {
                    return pressedBackgroundColor
                }
#if os(macOS)
                if isHovered {
                    return pressedBackgroundColor.opacity(0.85)
                }
#endif
                return backgroundColor
            }
        }
    }

}
