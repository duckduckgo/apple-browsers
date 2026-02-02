//
//  OnboardingTheme+Environment.swift
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

    /// Applies an onboarding theme to the current view hierarchy.
    ///
    /// - Parameter theme: The theme injected in the environment for onboarding views.
    /// - Returns: A view configured with the provided onboarding theme.
    func applyOnboardingTheme(_ theme: OnboardingTheme) -> some View {
        environment(\.onboardingTheme, theme)
    }

}
