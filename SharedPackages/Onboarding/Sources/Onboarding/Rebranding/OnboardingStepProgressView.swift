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

import SwiftUI
import UIComponents

public struct OnboardingStepProgressView: View {
    //Replace Metrics with @Environment(\.onboardingTheme) var onboardingTheme
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
        HStack(spacing: StepProgressMetrics.contentHorizontalSpacing) {
            DottedStepIndicatorView(
                selectedDot: currentStep,
                totalDots: totalSteps,
                style: .init(
                    selectedDotFillColor: .blue,
                    unselectedDotFillColor: .gray
                )
            )
            Text(verbatim: "\(currentStep) of \(totalSteps)")
                .font(.system(size: StepProgressMetrics.fontSize))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.primary)
        }
        .padding(.leading, StepProgressMetrics.Padding.leading)
        .padding(.trailing, StepProgressMetrics.Padding.trailing)
        .padding(.vertical, StepProgressMetrics.Padding.vertical)
        .overlay(
            RoundedRectangle(cornerRadius: StepProgressMetrics.cornerRadius)
                .inset(by: -StepProgressMetrics.Stroke.inset)
                .stroke(.blue, lineWidth: StepProgressMetrics.Stroke.lineWidth)
        )
    }
}

private enum StepProgressMetrics {
    static let contentHorizontalSpacing: CGFloat = 20
    static let fontSize: CGFloat = 12
    static let cornerRadius: CGFloat = 64

    enum Stroke {
        static let inset: CGFloat = 0.75
        static let lineWidth: CGFloat = 1.5
    }

    enum Padding {
        static let leading: CGFloat = 8
        static let trailing: CGFloat = 10
        static let vertical: CGFloat = 6
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
}
