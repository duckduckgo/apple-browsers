//
//  OnboardingViewModifiers.swift
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

// MARK: - Step Progress

private struct OnboardingStepProgressViewModifier: ViewModifier {
    // Replace values with @Environment(\.onboardingTheme) var onboardingTheme
    private let cornerRadius = 36.0
    private let stepProgressTrailingPadding = 4.0

    let currentStep: Int
    let totalSteps: Int

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                OnboardingStepProgressView(currentStep: currentStep, totalSteps: totalSteps)
                    .alignmentGuide(VerticalAlignment.top) { $0.height / 2 }
                    .alignmentGuide(HorizontalAlignment.trailing) { $0.width + cornerRadius + stepProgressTrailingPadding }
            }
    }
}

public extension View {

    /// Adds a step progress indicator to the top-trailing corner of the view.
    ///
    /// - Parameters:
    ///   - currentStep: The current step number (1-based indexing).
    ///   - totalSteps: The total number of steps in the flow.
    /// - Returns: A view with a step progress indicator overlay.
    func onboardingStepProgress(currentStep: Int, totalSteps: Int) -> some View {
        self.modifier(OnboardingStepProgressViewModifier(currentStep: currentStep, totalSteps: totalSteps))
    }

}

// MARK: - Dismiss Button

private struct OnboardingDismissButtonViewModifier: ViewModifier {
    // Replace values with @Environment(\.onboardingTheme) var onboardingTheme
    private let onboardingDismissButtonInternalPadding = 8.0
    private let onboardingDismissButtonPadding = 4.0

    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                OnboardingDismissButton(action: onDismiss)
                    .alignmentGuide(VerticalAlignment.top) { _ in onboardingDismissButtonInternalPadding + onboardingDismissButtonPadding }
                    .alignmentGuide(HorizontalAlignment.trailing) { $0.width - onboardingDismissButtonInternalPadding - onboardingDismissButtonPadding }
            }
    }
}

public extension View {

    /// Adds a dismiss button to the top-trailing corner of the view to dismiss the onboarding dialog.
    ///
    /// - Parameter onDismiss: A closure that's called when the dismiss button is tapped.
    /// - Returns: A view with a dismiss button overlay.
    func onboardingDismissable(_ onDismiss: @escaping () -> Void) -> some View {
        self.modifier(OnboardingDismissButtonViewModifier(onDismiss: onDismiss))
    }

}
