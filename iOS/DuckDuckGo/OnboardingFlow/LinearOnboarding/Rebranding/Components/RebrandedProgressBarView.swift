//
//  RebrandedProgressBarView.swift
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
import DesignResourcesKit
import Onboarding

extension OnboardingRebranding.OnboardingView {

    struct OnboardingProgressIndicator: View {
        let stepInfo: LegacyOnboardingViewState.Intro.StepInfo

        var body: some View {
            VStack(spacing: ProgressIndicatorMetrics.verticalSpacing) {
                HStack {
                    Spacer()
                    Text(verbatim: "\(stepInfo.currentStep) / \(stepInfo.totalSteps)")
                        .onboardingProgressTitleStyle()
                        .padding(.trailing, ProgressIndicatorMetrics.textPadding)
                }
                RebrandedOnboardingView.ProgressBarView(progress: percentage)
                    .frame(width: ProgressIndicatorMetrics.progressBarSize.width, height: ProgressIndicatorMetrics.progressBarSize.height)
            }
            .fixedSize()
        }

        private var percentage: Double {
            guard stepInfo.totalSteps > 0 else { return 0 }
            return Double(stepInfo.currentStep) / Double(stepInfo.totalSteps) * 100
        }
    }

    struct ProgressBarView: View {
        @Environment(\.colorScheme) private var colorScheme

        let progress: Double

        var body: some View {
            Capsule()
                .foregroundStyle(backgroundColor)
                .overlay(
                    GeometryReader { proxy in
                        RebrandedOnboardingView.ProgressBarGradient()
                            .clipShape(Capsule().inset(by: ProgressBarMetrics.strokeWidth / 2))
                            .frame(width: progress * proxy.size.width / 100)
                            .animation(.easeInOut, value: progress)
                    }
                )
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: ProgressBarMetrics.strokeWidth)
                )
        }

        private var backgroundColor: Color {
            colorScheme == .light ? ProgressBarMetrics.backgroundLight : ProgressBarMetrics.backgroundDark
        }

        private var borderColor: Color {
            colorScheme == .light ? ProgressBarMetrics.borderLight : ProgressBarMetrics.borderDark
        }

    }

    struct ProgressBarGradient: View {
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

}

private enum ProgressIndicatorMetrics {
    static let verticalSpacing: CGFloat = 8
    static let textPadding: CGFloat = 4
    static let progressBarSize = CGSize(width: 64, height: 4)
}

private enum ProgressBarMetrics {
    static let backgroundLight: Color = .shade(0.06)
    static let borderLight: Color = .shade(0.18)
    static let backgroundDark: Color = .tint(0.09)
    static let borderDark: Color = .tint(0.18)
    static let strokeWidth: CGFloat = 1
}
