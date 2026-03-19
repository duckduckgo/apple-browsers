//
//  OnboardingStepProgressView.swift
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
import UIComponents

public struct OnboardingStepProgressView: View {

    private enum Copy {
        static var of: String {
            NSLocalizedString("onboarding.highlights.browsers.progress.of", bundle: Bundle.module, value: "of", comment: "Delimiter for step/total dots in the rebranded onboarding")
        }
    }

    @Environment(\.onboardingTheme) private var onboardingTheme
    @Environment(\.onboardingStepProgressTheme) private var stepProgressTheme

    let currentStep: Int
    let totalSteps: Int

    public init(currentStep: Int, totalSteps: Int) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
    }

    public init(totalSteps: Int) {
        self.init(currentStep: 1, totalSteps: totalSteps)
    }

    public var body: some View {
        let clampedTotal = max(1, totalSteps)
        let clampedStep = max(1, min(currentStep, clampedTotal))

        HStack(spacing: stepProgressTheme.metrics.contentSpacing) {
            DottedStepIndicatorView(
                selectedDot: clampedStep,
                totalDots: clampedTotal,
                style: .init(
                    dotSpacing: stepProgressTheme.metrics.dotSpacing,
                    selectedDotSize: stepProgressTheme.metrics.selectedDotSize,
                    unselectedDotSize: stepProgressTheme.metrics.unselectedDotSize,
                    selectedDotFillColor: stepProgressTheme.colors.selectedDot,
                    unselectedDotBeforeSelectedFillColor: stepProgressTheme.colors.selectedDot,
                    unselectedDotAfterSelectedFillColor: stepProgressTheme.colors.unselectedDot
                )
            )
            Text(verbatim: "\(clampedStep) \(Copy.of) \(clampedTotal)")
                .font(onboardingTheme.typography.progressIndicator)
                .multilineTextAlignment(stepProgressTheme.textAlignment)
                .foregroundStyle(stepProgressTheme.colors.text)
        }
        .padding(stepProgressTheme.metrics.contentInsets)
        .background(stepProgressTheme.colors.background)
        .clipShape(RoundedRectangle(cornerRadius: stepProgressTheme.metrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: stepProgressTheme.metrics.cornerRadius)
                .inset(by: -stepProgressTheme.metrics.borderInset)
                .stroke(stepProgressTheme.colors.border, lineWidth: stepProgressTheme.metrics.borderWidth)
        )
    }
}

#Preview("Onboarding Step Progress Indicator") {
    struct PreviewWrapper: View {
        @State var currentStep: Int = 1
        let totalSteps = 5

        var body: some View {
            VStack(spacing: 50) {
                OnboardingStepProgressView(
                    currentStep: currentStep,
                    totalSteps: totalSteps
                )
                .frame(width: 200, height: 8)

                Button(action: {
                    currentStep = currentStep < totalSteps ? currentStep + 1 : 1
                }, label: {
                    Text(verbatim: "Update Steps")
                })
            }
        }
    }

    return PreviewWrapper()
        .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
}
#endif
