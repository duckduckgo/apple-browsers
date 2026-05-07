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
        private let hoverBackgroundColor: Color
        private let pressedBackgroundColor: Color
        private let disabledBackgroundColor: Color
        private let foregroundColor: Color
        private let disabledForegroundColor: Color
        private let font: Font
        private let verticalPadding: CGFloat
        private let horizontalPadding: CGFloat
        private let cornerRadius: CGFloat
        private let minWidth: CGFloat
        private let minHeight: CGFloat

        public init(
            backgroundColor: Color,
            hoverBackgroundColor: Color? = nil,
            pressedBackgroundColor: Color,
            disabledBackgroundColor: Color? = nil,
            foregroundColor: Color,
            disabledForegroundColor: Color? = nil,
            font: Font,
            verticalPadding: CGFloat = 8,
            horizontalPadding: CGFloat = 24,
            cornerRadius: CGFloat = 100,
            minWidth: CGFloat = 174,
            minHeight: CGFloat = 32
        ) {
            self.backgroundColor = backgroundColor
            // Hover falls back to pressed — preserves the old single-pressed-color behavior for callers that don't specify.
            self.hoverBackgroundColor = hoverBackgroundColor ?? pressedBackgroundColor
            self.pressedBackgroundColor = pressedBackgroundColor
            self.disabledBackgroundColor = disabledBackgroundColor ?? backgroundColor.opacity(0.4)
            self.foregroundColor = foregroundColor
            self.disabledForegroundColor = disabledForegroundColor ?? foregroundColor.opacity(0.6)
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
                hoverBackgroundColor: hoverBackgroundColor,
                pressedBackgroundColor: pressedBackgroundColor,
                disabledBackgroundColor: disabledBackgroundColor,
                foregroundColor: foregroundColor,
                disabledForegroundColor: disabledForegroundColor,
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
            let hoverBackgroundColor: Color
            let pressedBackgroundColor: Color
            let disabledBackgroundColor: Color
            let foregroundColor: Color
            let disabledForegroundColor: Color
            let font: Font
            let verticalPadding: CGFloat
            let horizontalPadding: CGFloat
            let cornerRadius: CGFloat
            let minWidth: CGFloat
            let minHeight: CGFloat

            @Environment(\.isEnabled) private var isEnabled
            @State private var isHovered = false

            var body: some View {
                configuration.label
                    .font(font)
                    .foregroundColor(isEnabled ? foregroundColor : disabledForegroundColor)
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
                if !isEnabled {
                    return disabledBackgroundColor
                }
                if configuration.isPressed {
                    return pressedBackgroundColor
                }
#if os(macOS)
                if isHovered {
                    return hoverBackgroundColor
                }
#endif
                return backgroundColor
            }
        }
    }

}
