//
//  OnboardingTheme+Environment.swift
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

private struct OnboardingThemeKey: EnvironmentKey {
    static let defaultValue = OnboardingTheme.rebranding2026
}

extension EnvironmentValues {

    var onboardingTheme: OnboardingTheme {
        get { self[OnboardingThemeKey.self] }
        set { self[OnboardingThemeKey.self] = newValue }
    }

}

public extension View {
    #if os(iOS)
    /// Applies an onboarding theme and an explicit step progress theme.
    ///
    /// - Parameters:
    ///   - theme: The theme injected in the environment for onboarding views.
    ///   - stepProgressTheme: The step progress theme injected for iOS step progress components.
    /// - Returns: A view configured with the provided themes.
    func applyOnboardingTheme(_ theme: OnboardingTheme, stepProgressTheme: OnboardingStepProgressTheme) -> some View {
        self
            .environment(\.onboardingTheme, theme)
            .environment(\.onboardingStepProgressTheme, stepProgressTheme)
    }
    #elseif os(macOS)
    /// Applies an onboarding theme to the current view hierarchy.
    ///
    /// - Parameter theme: The theme injected in the environment for onboarding views.
    /// - Returns: A view configured with the provided onboarding theme.
    func applyOnboardingTheme(_ theme: OnboardingTheme) -> some View {
        environment(\.onboardingTheme, theme)
    }
    #endif
}
