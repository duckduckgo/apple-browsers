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
            ListButtonContent(
                configuration: configuration,
                typography: typography,
                colorPalette: colorPalette,
                optionsListMetrics: optionsListMetrics
            )
        }

        private struct ListButtonContent: View {
            let configuration: ButtonStyle.Configuration
            let typography: OnboardingTheme.Typography
            let colorPalette: OnboardingTheme.ColorPalette
            let optionsListMetrics: OnboardingTheme.ContextualOnboardingMetrics.OptionsListMetrics

            @State private var isHovered = false

            var body: some View {
                configuration.label
                    .font(typography.contextual.controlSmall)
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
                return colorPalette.optionsListIconColor
#else
                return Color(designSystemColor: .accentTextPrimary)
#endif
            }

            private func backgroundColor(isPressed: Bool, isHovered: Bool) -> Color {
#if os(iOS)
                return isPressed ? colorPalette.backgroundAccent : .clear
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

}
