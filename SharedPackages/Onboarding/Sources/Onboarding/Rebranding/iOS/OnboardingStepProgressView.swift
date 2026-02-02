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
    @Environment(\.onboardingTheme) private var onboardingTheme

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
        HStack(spacing: onboardingTheme.stepProgressMetrics.contentSpacing) {
            DottedStepIndicatorView(
                selectedDot: currentStep,
                totalDots: totalSteps,
                style: .init(
                    dotSpacing: onboardingTheme.stepProgressMetrics.dotSpacing,
                    selectedDotSize: onboardingTheme.stepProgressMetrics.selectedDotSize,
                    unselectedDotSize: onboardingTheme.stepProgressMetrics.unselectedDotSize,
                    selectedDotFillColor: onboardingTheme.colorPalette.stepProgressSelectedDot,
                    unselectedDotFillColor: onboardingTheme.colorPalette.stepProgressUnselectedDot
                )
            )
            Text(verbatim: "\(currentStep) of \(totalSteps)")
                .font(onboardingTheme.typography.progressIndicator)
                .multilineTextAlignment(onboardingTheme.stepProgressMetrics.textAlignment)
                .foregroundStyle(onboardingTheme.colorPalette.textPrimary)
        }
        .padding(.leading, onboardingTheme.stepProgressMetrics.contentInsets.leading)
        .padding(.trailing, onboardingTheme.stepProgressMetrics.contentInsets.trailing)
        .padding(.top, onboardingTheme.stepProgressMetrics.contentInsets.top)
        .padding(.bottom, onboardingTheme.stepProgressMetrics.contentInsets.bottom)
        .background(onboardingTheme.colorPalette.bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: onboardingTheme.stepProgressMetrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: onboardingTheme.stepProgressMetrics.cornerRadius)
                .inset(by: -onboardingTheme.stepProgressMetrics.borderInset)
                .stroke(onboardingTheme.colorPalette.stepProgressBorderColor, lineWidth: onboardingTheme.stepProgressMetrics.borderWidth)
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
        .applyOnboardingTheme(.rebranding2026)
}
#endif
