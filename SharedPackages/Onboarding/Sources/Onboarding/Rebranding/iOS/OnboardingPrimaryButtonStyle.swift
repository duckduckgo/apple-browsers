//
//  OnboardingPrimaryButtonStyle.swift
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

// MARK: - Button Styles

// NOTE: Keep this style colocated with onboarding while rebranding is validated in this flow instead of DuckUI.
// This avoids exposing a partially adopted visual style to the rest of the app.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    private let typography: OnboardingTheme.Typography
    private let colorPalette: OnboardingTheme.ColorPalette

    init(typography: OnboardingTheme.Typography, colorPalette: OnboardingTheme.ColorPalette) {
        self.typography = typography
        self.colorPalette = colorPalette
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(typography.body)
            .foregroundColor(colorPalette.primaryButtonTextColor)
            .padding(.vertical)
            .padding(.horizontal, nil)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 40)
            .background(colorPalette.primaryButtonBackgroundColor)
            .cornerRadius(64.0)
    }

}
#endif
