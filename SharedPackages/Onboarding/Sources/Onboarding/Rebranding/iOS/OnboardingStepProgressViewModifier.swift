//
//  OnboardingStepProgressViewModifier.swift
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

private struct OnboardingStepProgressViewModifier: ViewModifier {
    @Environment(\.onboardingStepProgressTheme) private var stepProgressTheme

    let currentStep: Int
    let totalSteps: Int
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                OnboardingStepProgressView(currentStep: currentStep, totalSteps: totalSteps)
                    .alignmentGuide(VerticalAlignment.top) { $0.height / 2 }
                    .alignmentGuide(HorizontalAlignment.trailing) { $0.width + stepProgressTheme.trailingPadding }
                    .opacity(isVisible ? 1 : 0)
                    .accessibilityHidden(!isVisible) // Hide from VoiceOver when not visible
            }
    }
}

public extension View {

    /// Adds a step progress indicator to the top-trailing corner of the view.
    ///
    /// - Parameters:
    ///   - currentStep: The current step number (1-based indexing).
    ///   - totalSteps: The total number of steps in the flow.
    ///   - isVisible: Whether the step progress indicator should be visible. Default is `true`.
    /// - Returns: A view with a step progress indicator overlay.
    func onboardingStepProgress(currentStep: Int, totalSteps: Int, isVisible: Bool = true) -> some View {
        self.modifier(OnboardingStepProgressViewModifier(currentStep: currentStep, totalSteps: totalSteps, isVisible: isVisible))
    }

}
#endif
