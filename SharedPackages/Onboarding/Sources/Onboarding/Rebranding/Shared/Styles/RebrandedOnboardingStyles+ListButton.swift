//
//  RebrandedOnboardingStyles+ListButton.swift
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

    struct ListButtonStyle: ButtonStyle {
        @Environment(\.colorScheme) private var colorScheme

        @State private var isHovered = false

        private let typography: OnboardingTheme.Typography
        private let colorPalette: OnboardingTheme.ColorPalette
        private let optionsListMetrics: OnboardingTheme.ContextualOnboardingMetrics.OptionsListMetrics

        public init(
            typography: OnboardingTheme.Typography,
            colorPalette: OnboardingTheme.ColorPalette,
            optionsListMetrics: OnboardingTheme.ContextualOnboardingMetrics.OptionsListMetrics
        ) {
            self.typography = typography
            self.colorPalette = colorPalette
            self.optionsListMetrics = optionsListMetrics
        }

        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(typography.small)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .foregroundColor(foregroundColor(isPressed: configuration.isPressed, isHovered: isHovered))
                .padding()
                .frame(minWidth: 0, maxWidth: optionsListMetrics.itemMaxWidth, maxHeight: optionsListMetrics.itemMaxHeight)
                .background(backgroundColor(isPressed: configuration.isPressed, isHovered: isHovered))
                .cornerRadius(optionsListMetrics.cornerRadius)
                .contentShape(Rectangle()) // Makes whole button area tappable, when there's no background
                .onHover { hovering in
#if os(macOS)
                    self.isHovered = hovering
#endif
                }
                .overlay(
                    RoundedRectangle(cornerRadius: optionsListMetrics.cornerRadius)
                        .inset(by: optionsListMetrics.borderInset)
                        .stroke(colorPalette.optionsListBorderColor, lineWidth: optionsListMetrics.borderWidth)
                )
        }

        private func foregroundColor(isPressed: Bool, isHovered: Bool) -> Color {
#if os(iOS)
            switch (colorScheme, isPressed, isHovered) {
            case (.light, false, false),
                (.dark, false, false):
                return colorPalette.optionsListIconColor
            case (.light, false, true):
                return .lightHoverBlue
            case (.dark, false, true):
                return .darkHoverBlue
            case (.light, true, _):
                return .lightPressedBlue
            case (.dark, true, _):
                return .darkPressedBlue
            case (_, _, _):
                return .lightRestBlue
            }
#else
            return Color(designSystemColor: .accentTextPrimary)
#endif
        }

        private func backgroundColor(isPressed: Bool, isHovered: Bool) -> Color {
#if os(iOS)
            switch (colorScheme, isPressed, isHovered) {
            case (.light, false, false):
                return .shade(0.01)
            case (.dark, false, false):
                return .tint(0.03)
            case (.light, false, true):
                return .shade(0.03)
            case (.dark, false, true):
                return .tint(0.06)
            case (.light, true, _):
                return .shade(0.06)
            case (.dark, true, _):
                return .tint(0.06)
            case (_, _, _):
                return .clear
            }
#else
            if isPressed {
                return Color(designSystemColor: .controlsFillSecondary)
            }

            if isHovered {
                return Color(designSystemColor: .controlsFillPrimary)
            }

            return .clear
#endif
        }
    }

}
