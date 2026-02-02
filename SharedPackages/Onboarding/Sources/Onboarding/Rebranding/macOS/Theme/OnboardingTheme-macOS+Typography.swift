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
        /// Standard title style.
        public let title: Font
        /// Primary body text style.
        public let body: Font

        /// Creates a typography token set for onboarding.
        public init(
            title: Font,
            body: Font
        ) {
            self.title = title
            self.body = body
        }
    }

}

// MARK: - Factory Helpers

public extension OnboardingTheme.Typography {

    /// Typography preset using DuckSans families.
    static let duckSans = OnboardingTheme.Typography(
        title: makeFont(size: 24, family: .duckSansDisplay, weight: .bold),
        body: makeFont(size: 18, family: .duckSansProduct, weight: .regular)
    )

    /// System font fallback preset, useful for testing and previews.
    static let system = OnboardingTheme.Typography(
        title: .system(size: 24, weight: .bold),
        body: .system(size: 18, weight: .regular)
    )

}
#endif
