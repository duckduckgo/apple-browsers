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

/// A set of style values used by the onboarding UI.
/// Add here any new style used in the onboarding flow.
public struct OnboardingTheme: Equatable {
    /// Typography used across onboarding screens.
    public let typography: Typography
    /// Colors used across onboarding screens.
    public let colorPalette: ColorPalette
    /// Layout and visual metrics for the onboarding bubble container.
    public let bubbleMetrics: BubbleMetrics
    /// Content insets for bubbles in the linear onboarding flow.
    public let linearBubbleMetrics: LinearBubbleMetrics
    /// Layout metrics for positioning and sizing the dismiss button.
    public let dismissButtonMetrics: DismissButtonMetrics
    /// Layout metrics for the contextual onboarding flow.
    public let contextualOnboardingMetrics: ContextualOnboardingMetrics
    /// Layout metrics for the linear onboarding flow.
    public let linearOnboardingMetrics: LinearOnboardingMetrics
    /// Text alignment for linear flow titles.
    public let linearTitleTextAlignment: TextAlignment
    /// Text alignment for linear flow body copy.
    public let linearBodyTextAlignment: TextAlignment
    /// Style used by the primary onboarding button.
    public let primaryButtonStyle: OnboardingButtonStyle
    /// Style used by the secondary onboarding button.
    public let secondaryButtonStyle: OnboardingButtonStyle
    /// Style used by the dismiss onboarding button.
    public let dismissButtonStyle: OnboardingButtonStyle

    /// Creates a new onboarding theme.
    ///
    /// - Parameters:
    ///   - typography: Typography to use throughout the onboarding flow.
    ///   - colorPalette: Color palette to use throughout the onboarding flow.
    ///   - bubbleMetrics: Bubble layout and visual metrics.
    ///   - dismissButtonMetrics: Dismiss button layout and positioning metrics.
    ///   - linearTitleTextAlignment: Title alignment for linear flows.
    ///   - linearBodyTextAlignment: Body alignment for linear flows.
    ///   - contextualTitleTextAlignment: Title alignment for contextual flows.
    ///   - contextualBodyTextAlignment: Body alignment for contextual flows.
    ///   - primaryButtonStyle: Primary button style.
    ///   - secondaryButtonStyle: Secondary button style.
    ///   - dismissButtonStyle: Dismiss button style.
    public init(
        typography: Typography,
        colorPalette: ColorPalette,
        bubbleMetrics: BubbleMetrics,
        linearBubbleMetrics: LinearBubbleMetrics,
        dismissButtonMetrics: DismissButtonMetrics,
        contextualOnboardingMetrics: ContextualOnboardingMetrics,
        linearOnboardingMetrics: LinearOnboardingMetrics,
        linearTitleTextAlignment: TextAlignment,
        linearBodyTextAlignment: TextAlignment,
        primaryButtonStyle: OnboardingButtonStyle,
        secondaryButtonStyle: OnboardingButtonStyle,
        dismissButtonStyle: OnboardingButtonStyle,
    ){
        self.typography = typography
        self.colorPalette = colorPalette
        self.bubbleMetrics = bubbleMetrics
        self.linearBubbleMetrics = linearBubbleMetrics
        self.dismissButtonMetrics = dismissButtonMetrics
        self.contextualOnboardingMetrics = contextualOnboardingMetrics
        self.linearOnboardingMetrics = linearOnboardingMetrics
        self.linearTitleTextAlignment = linearTitleTextAlignment
        self.linearBodyTextAlignment = linearBodyTextAlignment
        self.primaryButtonStyle = primaryButtonStyle
        self.secondaryButtonStyle = secondaryButtonStyle
        self.dismissButtonStyle = dismissButtonStyle
    }

    /// Backward-compatible initializer for themes that only define a single button style.
    public init(
        typography: Typography,
        colorPalette: ColorPalette,
        bubbleMetrics: BubbleMetrics,
        linearBubbleMetrics: LinearBubbleMetrics,
        dismissButtonMetrics: DismissButtonMetrics,
        contextualOnboardingMetrics: ContextualOnboardingMetrics,
        linearOnboardingMetrics: LinearOnboardingMetrics,
        linearTitleTextAlignment: TextAlignment,
        linearBodyTextAlignment: TextAlignment,
        primaryButtonStyle: OnboardingButtonStyle,
        dismissButtonStyle: OnboardingButtonStyle,
    ){
        self.init(
            typography: typography,
            colorPalette: colorPalette,
            bubbleMetrics: bubbleMetrics,
            linearBubbleMetrics: linearBubbleMetrics,
            dismissButtonMetrics: dismissButtonMetrics,
            contextualOnboardingMetrics: contextualOnboardingMetrics,
            linearOnboardingMetrics: linearOnboardingMetrics,
            linearTitleTextAlignment: linearTitleTextAlignment,
            linearBodyTextAlignment: linearBodyTextAlignment,
            primaryButtonStyle: primaryButtonStyle,
            secondaryButtonStyle: primaryButtonStyle,
            dismissButtonStyle: dismissButtonStyle
        )
    }

}

// MARK: - Factory Helpers

public extension OnboardingTheme {
#if os(iOS)
    static let rebranding2026: OnboardingTheme = .iOSRebranding2026
#elseif os(macOS)
    static let rebranding2026: OnboardingTheme = .macOSRebranding2026
#endif
}
