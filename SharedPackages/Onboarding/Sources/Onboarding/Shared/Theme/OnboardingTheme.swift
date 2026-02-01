//
//  OnboardingTheme.swift
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

// MARK: - OnboardingTheme

public struct OnboardingTheme: Equatable {
    public let typography: Typography
    public let colorPalette: ColorPalette
    public let bubbleMetrics: BubbleMetrics
    public let stepProgressMetrics: StepProgressMetrics
    public let linearTitleTextAlignment: TextAlignment
    public let linearBodyTextAlignment: TextAlignment
    public let contextualTitleTextAlignment: TextAlignment
    public let contextualBodyTextAlignment: TextAlignment
    public let primaryButtonStyle: OnboardingButtonStyle
}

public extension OnboardingTheme {

    static let rebranding2026 = {
        let bubbleCornerRadius = 36.0
        let borderWidth = 1.5

        return OnboardingTheme(
            typography: .system,
            colorPalette: ColorPalette(
                bubbleBorder: Color(singleUseColor: .rebranding(.accentAltPrimary)),
                bubbleBackground: Color(singleUseColor: .rebranding(.surfaceTertiary)),
                bubbleShadow: Color.shade(0.03),
                stepProgressBackground: Color(singleUseColor: .rebranding(.surfaceTertiary)),
                stepProgressBorderColor: Color(singleUseColor: .rebranding(.accentAltPrimary)),
                stepProgressSelectedDot: Color(singleUseColor: .rebranding(.accentPrimary)),
                stepProgressUnselectedDot: Color(singleUseColor: .rebranding(.accentAltPrimary)),
                textPrimary: Color(singleUseColor: .rebranding(.textPrimary)),
                textSecondary: Color(singleUseColor: .rebranding(.textSecondary)),
                primaryButtonBackgroundColor: Color(singleUseColor: .rebranding(.buttonsPrimaryDefault)),
                primaryButtonTextColor: Color(singleUseColor: .rebranding(.buttonsPrimaryText))
            ),
            bubbleMetrics: BubbleMetrics(
                contentInsets: EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20),
                cornerRadius: bubbleCornerRadius,
                borderWidth: borderWidth,
                shadowRadius: 6.0,
                shadowPosition: CGPoint(x: 0, y: 7),
                stepProgressTrailingPadding: bubbleCornerRadius + 4
            ),
            stepProgressMetrics: StepProgressMetrics(
                cornerRadius: 64.0,
                contentInsets: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 10),
                contentSpacing: 20.0,
                borderInset: 0.75,
                borderWidth: borderWidth,
                dotSpacing: 4.0,
                selectedDotSize: 12.0,
                unselectedDotSize: 6.0,
                textAlignment: .trailing
            ),
            linearTitleTextAlignment: .center,
            linearBodyTextAlignment: .center,
            contextualTitleTextAlignment: .leading,
            contextualBodyTextAlignment: .leading,
            primaryButtonStyle: OnboardingButtonStyle(
                id: .primary,
                style: AnyButtonStyle(OnboardingPrimaryButtonStyle())
            )
        )
    }()

}
