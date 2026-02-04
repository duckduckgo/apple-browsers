//
//  OnboardingTheme+Buttons.swift
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

// MARK: OnboardingTheme

public extension OnboardingTheme {

    /// Layout metrics used by the dismiss button style and overlay positioning.
    struct DismissButtonMetrics: Equatable {
        /// Outer frame size of the dismiss button.
        public let buttonSize: CGSize
        /// Offset applied from the bubble's top-trailing corner to place the dismiss button.
        ///
        /// Positive `x` moves the button inward from the trailing edge.
        /// Positive `y` moves the button downward from the top edge.
        public let offsetRelativeToBubble: CGPoint
        /// Internal padding applied to the dismiss button's icon within its circular container.
        public let contentPadding: CGFloat

        /// Creates dismiss button layout metrics.
        ///
        /// - Parameters:
        ///   - buttonSize: Outer frame size of the dismiss button.
        ///   - offsetRelativeToBubble: Positional offset from the bubble's top-trailing corner.
        ///   - contentPadding: Internal icon padding inside the circular button.
        public init(buttonSize: CGSize, offsetRelativeToBubble: CGPoint, contentPadding: CGFloat) {
            self.buttonSize = buttonSize
            self.offsetRelativeToBubble = offsetRelativeToBubble
            self.contentPadding = contentPadding
        }
    }
}

// MARK: - Style Helpers

/// Semantic identifiers for onboarding button styles.
public enum OnboardingButtonStyleID {
    /// Primary call-to-action button style.
    case primary
    /// Secondary call-to-action button style.
    case secondary
    /// List row button style.
    case list
    /// Dismiss button style
    case dismiss
}

/// Type-erased, equatable wrapper for onboarding button styles.
public struct OnboardingButtonStyle: Equatable {
    /// Semantic identifier used for equality and style selection.
    public let id: OnboardingButtonStyleID
    /// Type-erased SwiftUI button style implementation.
    public let style: AnyButtonStyle

    /// Creates an onboarding button style token.
    public init(id: OnboardingButtonStyleID, style: AnyButtonStyle) {
        self.id = id
        self.style = style
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Helpers

/// Type-erased adapter that stores any `ButtonStyle`.
public struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    public init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { AnyView(style.makeBody(configuration: $0)) }
    }

    public func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}
