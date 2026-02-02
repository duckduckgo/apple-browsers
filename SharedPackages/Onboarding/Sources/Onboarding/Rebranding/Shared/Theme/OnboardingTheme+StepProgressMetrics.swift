//
//  OnboardingTheme+StepProgressMetrics.swift
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

    /// Layout and visual metrics for the step progress component.
    struct StepProgressMetrics: Equatable {
        /// Corner radius for the step progress container.
        public let cornerRadius: CGFloat
        /// Internal content padding.
        public let contentInsets: EdgeInsets
        /// Horizontal spacing between text and dots.
        public let contentSpacing: CGFloat
        /// Inset applied to the border stroke.
        public let borderInset: CGFloat
        /// Border stroke width.
        public let borderWidth: CGFloat
        /// Spacing between dots.
        public let dotSpacing: CGFloat
        /// Size of selected progress dots.
        public let selectedDotSize: CGFloat
        /// Size of unselected progress dots.
        public let unselectedDotSize: CGFloat
        /// Text alignment for the progress label.
        public let textAlignment: TextAlignment

        /// Creates step progress metrics for onboarding layouts.
        public init(
            cornerRadius: CGFloat,
            contentInsets: EdgeInsets,
            contentSpacing: CGFloat,
            borderInset: CGFloat,
            borderWidth: CGFloat,
            dotSpacing: CGFloat,
            selectedDotSize: CGFloat,
            unselectedDotSize: CGFloat,
            textAlignment: TextAlignment
        ) {
            self.cornerRadius = cornerRadius
            self.contentInsets = contentInsets
            self.contentSpacing = contentSpacing
            self.borderInset = borderInset
            self.borderWidth = borderWidth
            self.dotSpacing = dotSpacing
            self.selectedDotSize = selectedDotSize
            self.unselectedDotSize = unselectedDotSize
            self.textAlignment = textAlignment
        }
    }

}
