//
//  OnboardingTheme-iOS+Typography.swift
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

public extension OnboardingTheme {

    /// Typography tokens used by onboarding content.
    struct Typography: Equatable {
        /// Largest display title style.
        public let largeTitle: Font
        /// Standard title style.
        public let title: Font
        /// Primary body text style.
        public let body: Font
        /// Standard title style for contextual Flow.
        public let contextualTitle: Font
        /// Standard body style for contextual Flow.
        public let contextualBody: Font
        /// Step progress text style.
        public let progressIndicator: Font
        /// List row title style (E.g Address Bar position picker title).
        public let row: Font
        /// List row detail style (E.g Address Bar position picker subtitle).
        public let rowDetails: Font
        /// Small text and button label style.
        public let small: Font

        /// Creates a typography token set for onboarding.
        public init(
            largeTitle: Font,
            title: Font,
            body: Font,
            contextualTitle: Font,
            contextualBody: Font,
            progressIndicator: Font,
            row: Font,
            rowDetails: Font,
            small: Font
        ) {
            self.largeTitle = largeTitle
            self.title = title
            self.body = body
            self.contextualTitle = contextualTitle
            self.contextualBody = contextualBody
            self.progressIndicator = progressIndicator
            self.row = row
            self.rowDetails = rowDetails
            self.small = small
        }

    }

}

// MARK: - Factory Helpers

public extension OnboardingTheme.Typography {

    /// Typography preset using DuckSans families.
    static let duckSans = OnboardingTheme.Typography(
        largeTitle: makeFont(size: 44, family: .duckSansDisplay, weight: .bold),
        title: makeFont(size: 24, family: .duckSansDisplay, weight: .bold),
        body: makeFont(size: 18, family: .duckSansProduct, weight: .regular),
        contextualTitle: makeFont(size: 20, family: .duckSansDisplay, weight: .bold),
        contextualBody: makeFont(size: 16, family: .duckSansProduct, weight: .regular),
        progressIndicator: makeFont(size: 12, family: .duckSansProduct, weight: .regular),
        row: makeFont(size: 16, family: .duckSansProduct, weight: .medium),
        rowDetails: makeFont(size: 14, family: .duckSansProduct, weight: .regular),
        small: makeFont(size: 14, family: .duckSansProduct, weight: .regular)
    )

    /// System font fallback preset, useful for testing and previews.
    static let system = OnboardingTheme.Typography(
        largeTitle: .system(size: 44, weight: .bold),
        title: .system(size: 24, weight: .bold),
        body: .system(size: 18, weight: .regular),
        contextualTitle: .system(size: 20, weight: .bold),
        contextualBody: .system(size: 16, weight: .regular),
        progressIndicator: .system(size: 12, weight: .regular),
        row: .system(size: 16, weight: .medium),
        rowDetails: .system(size: 14, weight: .regular),
        small: .system(size: 14, weight: .regular)
    )

}
#endif
