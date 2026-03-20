//
//  OnboardingTheme-macOS+Typography.swift
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

#if os(macOS)
import SwiftUI

public extension OnboardingTheme {

    /// Typography tokens used by onboarding content.
    struct Typography: Equatable {
        /// Contextual-specific typography extension point.
        /// Intentionally empty for now while contextual flow continues using shared tokens.
        public struct Contextual: Equatable {
            /// Standard title style for contextual Flow.
            public let title: Font
            /// Standard body style for contextual Flow.
            public let body: Font
            /// Standard style for list button for contextual Flow.
            public let controlSmall: Font

            public init(
                title: Font,
                body: Font,
                controlSmall: Font
            ) {
                self.title = title
                self.body = body
                self.controlSmall = controlSmall
            }
        }

        /// Typography used by contextual onboarding flow.
        public let contextual: Contextual

        /// Creates a typography token set for onboarding.
        public init(
            contextual: Contextual,
        ) {
            self.contextual = contextual
        }

        public init(
            contextualTitle: Font,
            contextualBody: Font,
            contextualControlSmall: Font
        ) {
            self.contextual = Contextual(
                title: contextualTitle,
                body: contextualBody,
                controlSmall: contextualControlSmall
            )
        }
    }

}

// MARK: - Factory Helpers

public extension OnboardingTheme.Typography {

    /// Typography preset using DuckSans families.
    static let duckSans = OnboardingTheme.Typography(
        contextualTitle: makeFont(size: 24, family: .duckSansDisplay, weight: .bold),
        contextualBody: makeFont(size: 18, family: .duckSansProduct, weight: .regular),
        contextualControlSmall: makeFont(size: 15, family: .duckSansProduct, weight: .bold)
    )

    /// System font fallback preset, useful for testing and previews.
    static let system = OnboardingTheme.Typography(
        contextualTitle: .system(size: 24, weight: .bold),
        contextualBody: .system(size: 18, weight: .regular),
        contextualControlSmall: .system(size: 15, weight: .bold)
    )

}
#endif
