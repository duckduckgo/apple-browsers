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
    /// Layout metrics for positioning and sizing the dismiss button.
    public let dismissButtonMetrics: DismissButtonMetrics
    /// Layout metrics for the contextual onboarding flow.
    public let contextualOnboardingMetrics: ContextualOnboardingMetrics
    /// Text alignment for linear flow titles.
    public let linearTitleTextAlignment: TextAlignment
    /// Text alignment for linear flow body copy.
    public let linearBodyTextAlignment: TextAlignment
    /// Style used by the primary onboarding button.
    public let primaryButtonStyle: OnboardingButtonStyle
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
    ///   - dismissButtonStyle: Dismiss button style.
    public init(
        typography: Typography,
        colorPalette: ColorPalette,
        bubbleMetrics: BubbleMetrics,
        dismissButtonMetrics: DismissButtonMetrics,
        contextualOnboardingMetrics: ContextualOnboardingMetrics,
        linearTitleTextAlignment: TextAlignment,
        linearBodyTextAlignment: TextAlignment,
        primaryButtonStyle: OnboardingButtonStyle,
        dismissButtonStyle: OnboardingButtonStyle,
    ){
        self.typography = typography
        self.colorPalette = colorPalette
        self.bubbleMetrics = bubbleMetrics
        self.dismissButtonMetrics = dismissButtonMetrics
        self.contextualOnboardingMetrics = contextualOnboardingMetrics
        self.linearTitleTextAlignment = linearTitleTextAlignment
        self.linearBodyTextAlignment = linearBodyTextAlignment
        self.primaryButtonStyle = primaryButtonStyle
        self.dismissButtonStyle = dismissButtonStyle
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
