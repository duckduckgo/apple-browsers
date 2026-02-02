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

#if os(iOS)
import SwiftUI
import DesignResourcesKit

/// A set of style values used by the onboarding UI.
/// Add here any new style used in the onboarding flow.
public struct OnboardingTheme: Equatable {
    /// Typography used across onboarding screens.
    public let typography: Typography
    /// Colors used across onboarding screens.
    public let colorPalette: ColorPalette
    /// Layout and visual metrics for the onboarding bubble container.
    public let bubbleMetrics: BubbleMetrics
    /// Layout and visual metrics for the step progress component.
    public let stepProgressMetrics: StepProgressMetrics
    /// Text alignment for linear flow titles.
    public let linearTitleTextAlignment: TextAlignment
    /// Text alignment for linear flow body copy.
    public let linearBodyTextAlignment: TextAlignment
    /// Text alignment for contextual flow titles.
    public let contextualTitleTextAlignment: TextAlignment
    /// Text alignment for contextual flow body copy.
    public let contextualBodyTextAlignment: TextAlignment
    /// Style used by the primary onboarding button.
    public let primaryButtonStyle: OnboardingButtonStyle

    /// Creates a new onboarding theme.
    ///
    /// - Parameters:
    ///   - typography: Typography to use throughout the onboarding flow.
    ///   - colorPalette: Color palette to use throughout the onboarding flow.
    ///   - bubbleMetrics: Bubble layout and visual metrics.
    ///   - stepProgressMetrics: Step progress layout and visual metrics.
    ///   - linearTitleTextAlignment: Title alignment for linear flows.
    ///   - linearBodyTextAlignment: Body alignment for linear flows.
    ///   - contextualTitleTextAlignment: Title alignment for contextual flows.
    ///   - contextualBodyTextAlignment: Body alignment for contextual flows.
    ///   - primaryButtonStyle: Primary button style.
    public init(
        typography: Typography,
        colorPalette: ColorPalette,
        bubbleMetrics: BubbleMetrics,
        stepProgressMetrics: StepProgressMetrics,
        linearTitleTextAlignment: TextAlignment,
        linearBodyTextAlignment: TextAlignment,
        contextualTitleTextAlignment: TextAlignment,
        contextualBodyTextAlignment: TextAlignment,
        primaryButtonStyle: OnboardingButtonStyle
    ){
        self.typography = typography
        self.colorPalette = colorPalette
        self.bubbleMetrics = bubbleMetrics
        self.stepProgressMetrics = stepProgressMetrics
        self.linearTitleTextAlignment = linearTitleTextAlignment
        self.linearBodyTextAlignment = linearBodyTextAlignment
        self.contextualTitleTextAlignment = contextualTitleTextAlignment
        self.contextualBodyTextAlignment = contextualBodyTextAlignment
        self.primaryButtonStyle = primaryButtonStyle
    }
}

// MARK: - Factory Helpers

public extension OnboardingTheme {

    /// Rebranding 2026 default onboarding theme.
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
#endif
