//
//  OnboardingStepProgressTheme.swift
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

/// iOS-only style tokens for the onboarding step progress component.
public struct OnboardingStepProgressTheme: Equatable {
    /// Layout metrics for the step progress component.
    public let metrics: Metrics
    /// Colors  for the step progress component.
    public let colors: Colors
    /// Text alignment for the progress label.
    public let textAlignment: TextAlignment
    /// Trailing offset used when overlaying step progress on the bubble.
    public let trailingPadding: CGFloat

    public init(
        metrics: Metrics,
        colors: Colors,
        textAlignment: TextAlignment,
        trailingPadding: CGFloat
    ) {
        self.metrics = metrics
        self.colors = colors
        self.textAlignment = textAlignment
        self.trailingPadding = trailingPadding
    }
}

public extension OnboardingStepProgressTheme {

    /// Layout metrics for the step progress component.
    struct Metrics: Equatable {
        public let cornerRadius: CGFloat
        public let contentInsets: EdgeInsets
        public let contentSpacing: CGFloat
        public let borderInset: CGFloat
        public let borderWidth: CGFloat
        public let dotSpacing: CGFloat
        public let selectedDotSize: CGFloat
        public let unselectedDotSize: CGFloat

        public init(
            cornerRadius: CGFloat,
            contentInsets: EdgeInsets,
            contentSpacing: CGFloat,
            borderInset: CGFloat,
            borderWidth: CGFloat,
            dotSpacing: CGFloat,
            selectedDotSize: CGFloat,
            unselectedDotSize: CGFloat
        ) {
            self.cornerRadius = cornerRadius
            self.contentInsets = contentInsets
            self.contentSpacing = contentSpacing
            self.borderInset = borderInset
            self.borderWidth = borderWidth
            self.dotSpacing = dotSpacing
            self.selectedDotSize = selectedDotSize
            self.unselectedDotSize = unselectedDotSize
        }
    }

    /// Color tokens for the step progress component.
    struct Colors: Equatable {
        public let background: Color
        public let border: Color
        public let selectedDot: Color
        public let unselectedDot: Color
        public let text: Color

        public init(
            background: Color,
            border: Color,
            selectedDot: Color,
            unselectedDot: Color,
            text: Color
        ) {
            self.background = background
            self.border = border
            self.selectedDot = selectedDot
            self.unselectedDot = unselectedDot
            self.text = text
        }
    }
}

public extension OnboardingStepProgressTheme {

    /// Rebranding 2026 default style for the onboarding step progress component.
    static let rebranding2026 = OnboardingStepProgressTheme(
        metrics: .init(
            cornerRadius: 64.0,
            contentInsets: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 10),
            contentSpacing: 20.0,
            borderInset: 0.75,
            borderWidth: 1.5,
            dotSpacing: 4.0,
            selectedDotSize: 12.0,
            unselectedDotSize: 6.0
        ),
        colors: .init(
            background: Color(singleUseColor: .rebranding(.surfaceTertiary)),
            border: Color(singleUseColor: .rebranding(.accentAltPrimary)),
            selectedDot: Color(singleUseColor: .rebranding(.accentPrimary)),
            unselectedDot: Color(singleUseColor: .rebranding(.accentAltPrimary)),
            text: Color(singleUseColor: .rebranding(.textPrimary))
        ),
        textAlignment: .trailing,
        trailingPadding: 40.0
    )
}
#endif
