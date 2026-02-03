//
//  RebrandedProgressBarView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
import Onboarding

struct RebrandedOnboardingProgressIndicator: View {
    
    struct StepInfo {
        let currentStep: Int
        let totalSteps: Int

        fileprivate var percentage: Double {
            guard totalSteps > 0 else { return 0 }
            return Double(currentStep) / Double(totalSteps) * 100
        }
    }

    let stepInfo: StepInfo

    var body: some View {
        VStack(spacing: RebrandedOnboardingProgressMetrics.verticalSpacing) {
            HStack {
                Spacer()
                Text(verbatim: "\(stepInfo.currentStep) / \(stepInfo.totalSteps)")
                    .onboardingProgressTitleStyle()
                    .padding(.trailing, RebrandedOnboardingProgressMetrics.textPadding)
            }
            RebrandedProgressBarView(progress: stepInfo.percentage)
                .frame(width: RebrandedOnboardingProgressMetrics.progressBarSize.width, height: RebrandedOnboardingProgressMetrics.progressBarSize.height)
        }
        .fixedSize()
    }
}

private enum RebrandedOnboardingProgressMetrics {
    static let verticalSpacing: CGFloat = 8
    static let textPadding: CGFloat = 4
    static let progressBarSize = CGSize(width: 64, height: 4)
}

struct RebrandedProgressBarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let progress: Double

    var body: some View {
        Capsule()
            .foregroundStyle(backgroundColor)
            .overlay(
                GeometryReader { proxy in
                    RebrandedProgressBarGradient()
                        .clipShape(Capsule().inset(by: RebrandedProgressBarMetrics.strokeWidth / 2))
                        .frame(width: progress * proxy.size.width / 100)
                        .animation(.easeInOut, value: progress)
                }
            )
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: RebrandedProgressBarMetrics.strokeWidth)
            )
    }

    private var backgroundColor: Color {
        colorScheme == .light ? RebrandedProgressBarMetrics.backgroundLight : RebrandedProgressBarMetrics.backgroundDark
    }

    private var borderColor: Color {
        colorScheme == .light ? RebrandedProgressBarMetrics.borderLight : RebrandedProgressBarMetrics.borderDark
    }

}

private enum RebrandedProgressBarMetrics {
    static let backgroundLight: Color = .shade(0.06)
    static let borderLight: Color = .shade(0.18)
    static let backgroundDark: Color = .tint(0.09)
    static let borderDark: Color = .tint(0.18)
    static let strokeWidth: CGFloat = 1
}

struct RebrandedProgressBarGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors: [Color]
        switch colorScheme {
        case .light:
            colors = lightGradientColors
        case .dark:
            colors = darkGradientColors
        @unknown default:
            colors = lightGradientColors
        }

        return LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var lightGradientColors: [Color] {
        [
            Color(baseColor: .blue50),
            Color(baseColor: .purple40),
            Color(baseColor: .red50)
        ]
    }

    private var darkGradientColors: [Color] {
        [
            Color(baseColor: .blue50),
            Color(baseColor: .purple40),
            Color(baseColor: .red50)
        ]
    }
}

#Preview("Onboarding Progress Indicator") {
    struct PreviewWrapper: View {
        @State var stepInfo = RebrandedOnboardingProgressIndicator.StepInfo(currentStep: 1, totalSteps: 3)

        var body: some View {
            VStack(spacing: 100) {
                RebrandedOnboardingProgressIndicator(stepInfo: stepInfo)

                Button(action: {
                    let nextStep = stepInfo.currentStep < stepInfo.totalSteps ? stepInfo.currentStep + 1 : 1
                    stepInfo = RebrandedOnboardingProgressIndicator.StepInfo(currentStep: nextStep, totalSteps: stepInfo.totalSteps)
                }, label: {
                    Text(verbatim: "Update Progress")
                })
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Progress Bar") {
    RebrandedProgressBarView(progress: 80)
        .frame(width: 200, height: 8)
}
