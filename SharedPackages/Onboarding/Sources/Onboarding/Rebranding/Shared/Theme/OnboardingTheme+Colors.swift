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
