//
//  OnboardingTheme+Colors.swift
//  Onboarding
//
//  Created by Alessandro Boron on 2/2/2026.
//

import SwiftUI

public extension OnboardingTheme {

    /// Color tokens used by onboarding components.
    struct ColorPalette: Equatable {
        /// Bubble border color.
        public let bubbleBorder: Color
        /// Bubble background color.
        public let bubbleBackground: Color
        /// Bubble shadow color.
        public let bubbleShadow: Color

        /// Primary text color.
        public let textPrimary: Color
        /// Secondary text color.
        public let textSecondary: Color

        /// Primary button background color.
        public let primaryButtonBackgroundColor: Color
        /// Primary button foreground/text color.
        public let primaryButtonTextColor: Color

        /// Creates a color palette for onboarding surfaces, text, and controls.
        public init(
            bubbleBorder: Color,
            bubbleBackground: Color,
            bubbleShadow: Color,
            textPrimary: Color, textSecondary: Color,
            primaryButtonBackgroundColor: Color,
            primaryButtonTextColor: Color
        ) {
            self.bubbleBorder = bubbleBorder
            self.bubbleBackground = bubbleBackground
            self.bubbleShadow = bubbleShadow
            self.textPrimary = textPrimary
            self.textSecondary = textSecondary
            self.primaryButtonBackgroundColor = primaryButtonBackgroundColor
            self.primaryButtonTextColor = primaryButtonTextColor
        }
    }

}
