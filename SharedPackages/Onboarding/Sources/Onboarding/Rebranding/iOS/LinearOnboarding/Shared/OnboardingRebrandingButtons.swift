//
//  OnboardingRebrandingButtons.swift
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

#if os(iOS)
import SwiftUI

extension OnboardingRebranding {

    struct PrimaryButton: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        let title: String
        let isEnabled: Bool
        let action: () -> Void

        init(title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
            self.title = title
            self.isEnabled = isEnabled
            self.action = action
        }

        var body: some View {
            Button(action: action) {
                Text(title)
            }
            .buttonStyle(
                RebrandingPrimaryButtonStyle(
                    typography: onboardingTheme.typography,
                    colorPalette: onboardingTheme.colorPalette
                )
            )
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.6)
        }
    }

    struct SecondaryButton: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        let title: String
        let action: () -> Void

        init(title: String, action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(onboardingTheme.typography.small)
                    .foregroundColor(onboardingTheme.colorPalette.textSecondary)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private struct RebrandingPrimaryButtonStyle: ButtonStyle {
        let typography: OnboardingTheme.Typography
        let colorPalette: OnboardingTheme.ColorPalette

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .font(typography.small)
                .foregroundColor(colorPalette.primaryButtonTextColor)
                .padding(.vertical)
                .padding(.horizontal, nil)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 40)
                .background(colorPalette.primaryButtonBackgroundColor)
                .cornerRadius(64.0)
        }
    }
}
#endif
