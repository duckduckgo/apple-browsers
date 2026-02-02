//
//  OnboardingTheme+Bubble.swift
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

    /// Layout and visual metrics for the onboarding bubble container.
    struct BubbleMetrics: Equatable {
        /// Internal content padding for the bubble.
        public let contentInsets: EdgeInsets
        /// Bubble corner radius.
        public let cornerRadius: CGFloat
        /// Bubble border width.
        public let borderWidth: CGFloat
        /// Shadow blur radius.
        public let shadowRadius: CGFloat
        /// Shadow offset position.
        public let shadowPosition: CGPoint

        /// Creates bubble metrics for onboarding layouts.
        public init(
            contentInsets: EdgeInsets,
            cornerRadius: CGFloat,
            borderWidth: CGFloat,
            shadowRadius: CGFloat,
            shadowPosition: CGPoint
        ) {
            self.contentInsets = contentInsets
            self.cornerRadius = cornerRadius
            self.borderWidth = borderWidth
            self.shadowRadius = shadowRadius
            self.shadowPosition = shadowPosition
        }
    }

}
