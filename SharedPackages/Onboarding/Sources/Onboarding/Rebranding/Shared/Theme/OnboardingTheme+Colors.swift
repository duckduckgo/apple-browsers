//
//  OnboardingTheme+Colors.swift
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

public extension OnboardingTheme {

    /// Color tokens used by onboarding components.
    struct ColorPalette: Equatable {
        /// Background color used behind onboarding surfaces and contextual illustrations.
        public let background: Color
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

        /// Border color for contextual onboarding multiple option list rows.
        public let optionsListBorderColor: Color
        /// Icon tint color for contextual onboarding option list rows.
        public let optionsListIconColor: Color
        /// Text color for contextual onboarding option list rows.
        public let optionsListTextColor: Color

        /// Primary button background color.
        public let primaryButtonBackgroundColor: Color
        /// Primary button foreground/text color.
        public let primaryButtonTextColor: Color
        /// Secondary button background color.
        public let secondaryButtonBackgroundColor: Color
        /// Secondary button foreground/text color.
        public let secondaryButtonTextColor: Color

        /// Creates a color palette for onboarding surfaces, text, and controls.
        public init(
            background: Color,
            bubbleBorder: Color,
            bubbleBackground: Color,
            bubbleShadow: Color,
            textPrimary: Color,
            textSecondary: Color,
            optionsListBorderColor: Color,
            optionsListIconColor: Color,
            optionsListTextColor: Color,
            primaryButtonBackgroundColor: Color,
            primaryButtonTextColor: Color,
            secondaryButtonBackgroundColor: Color,
            secondaryButtonTextColor: Color
        ) {
            self.background = background
            self.bubbleBorder = bubbleBorder
            self.bubbleBackground = bubbleBackground
            self.bubbleShadow = bubbleShadow
            self.textPrimary = textPrimary
            self.textSecondary = textSecondary
            self.optionsListBorderColor = optionsListBorderColor
            self.optionsListIconColor = optionsListIconColor
            self.optionsListTextColor = optionsListTextColor
            self.primaryButtonBackgroundColor = primaryButtonBackgroundColor
            self.primaryButtonTextColor = primaryButtonTextColor
            self.secondaryButtonBackgroundColor = secondaryButtonBackgroundColor
            self.secondaryButtonTextColor = secondaryButtonTextColor
        }

        /// Backward-compatible initializer for themes that do not define dedicated secondary button colors.
        public init(
            background: Color,
            bubbleBorder: Color,
            bubbleBackground: Color,
            bubbleShadow: Color,
            textPrimary: Color,
            textSecondary: Color,
            optionsListBorderColor: Color,
            optionsListIconColor: Color,
            optionsListTextColor: Color,
            primaryButtonBackgroundColor: Color,
            primaryButtonTextColor: Color
        ) {
            self.init(
                background: background,
                bubbleBorder: bubbleBorder,
                bubbleBackground: bubbleBackground,
                bubbleShadow: bubbleShadow,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                optionsListBorderColor: optionsListBorderColor,
                optionsListIconColor: optionsListIconColor,
                optionsListTextColor: optionsListTextColor,
                primaryButtonBackgroundColor: primaryButtonBackgroundColor,
                primaryButtonTextColor: primaryButtonTextColor,
                secondaryButtonBackgroundColor: primaryButtonBackgroundColor,
                secondaryButtonTextColor: primaryButtonTextColor
            )
        }
    }

}
