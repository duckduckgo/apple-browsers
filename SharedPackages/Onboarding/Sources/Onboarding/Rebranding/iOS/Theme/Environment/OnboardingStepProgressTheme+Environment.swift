//
//  OnboardingStepProgressTheme+Environment.swift
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

private struct OnboardingStepProgressThemeKey: EnvironmentKey {
    static let defaultValue = OnboardingStepProgressTheme.rebranding2026
}

public extension EnvironmentValues {

    var onboardingStepProgressTheme: OnboardingStepProgressTheme {
        get { self[OnboardingStepProgressThemeKey.self] }
        set { self[OnboardingStepProgressThemeKey.self] = newValue }
    }

}

public extension View {

    /// Applies an onboarding step progress theme to the current view hierarchy.
    ///
    /// - Parameter theme: The step progress theme injected in the environment.
    /// - Returns: A view configured with the provided step progress theme.
    func applyOnboardingStepProgressTheme(_ theme: OnboardingStepProgressTheme) -> some View {
        environment(\.onboardingStepProgressTheme, theme)
    }

}
#endif
