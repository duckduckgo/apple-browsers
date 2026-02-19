//
//  OnboardingTheme+ContextualFlow.swift
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

    /// Layout and text-alignment metrics used by contextual onboarding screens.
    struct ContextualOnboardingMetrics: Equatable {

        /// Outer padding applied to the contextual onboarding content container.
        public let containerPadding: EdgeInsets

        /// Spacing between the copy block and CTA content.
        public let contentSpacing: CGFloat

        /// Vertical spacing between title and body text in the copy block.
        public let titleBodyVerticalSpacing: CGFloat
        /// Insets applied to the title/body copy block.
        public let titleBodyInset: EdgeInsets

        /// Text alignment for contextual flow titles.
        public let contextualTitleTextAlignment: TextAlignment
        /// Text alignment for contextual flow body copy.
        public let contextualBodyTextAlignment: TextAlignment

        /// Metrics used to lay out contextual option list rows.
        /// [Figma Selector  Buttons](https://www.figma.com/design/wMxBpe0mKrRS0nVhtwMGO7/%F0%9F%9A%80-Onboarding-Components--2026-?node-id=2-1521)
        public let optionsListMetrics: OptionsListMetrics
        /// [Figma Selector  Buttons](https://www.figma.com/design/wMxBpe0mKrRS0nVhtwMGO7/%F0%9F%9A%80-Onboarding-Components--2026-?node-id=2-1521)
        public let optionsListButtonStyle: OnboardingButtonStyle

        /// Maximum width for the contextual dialog container.
        /// When `nil`, the container uses full available width.
        public let maxContainerWidth: CGFloat?

        /// Time delay (in seconds) before the contextual content starts to fade in.
        /// This creates a brief pause after the dialog appears before animating the content.
        public let contentFadeInDelay: TimeInterval

        /// Duration (in seconds) of the fade-in animation for contextual content.
        /// Controls how quickly the content transitions from invisible to fully visible.
        public let contentFadeInDuration: TimeInterval

        public init(
            containerPadding: EdgeInsets,
            contentSpacing: CGFloat,
            titleBodyVerticalSpacing: CGFloat,
            titleBodyInset: EdgeInsets,
            contextualTitleTextAlignment: TextAlignment,
            contextualBodyTextAlignment: TextAlignment,
            optionsListMetrics: OptionsListMetrics,
            optionsListButtonStyle: OnboardingButtonStyle,
            maxContainerWidth: CGFloat? = nil,
            contentFadeInDelay: TimeInterval = 0.3,
            contentFadeInDuration: TimeInterval = 0.25
        ) {
            self.containerPadding = containerPadding
            self.contentSpacing = contentSpacing
            self.titleBodyVerticalSpacing = titleBodyVerticalSpacing
            self.titleBodyInset = titleBodyInset
            self.contextualTitleTextAlignment = contextualTitleTextAlignment
            self.contextualBodyTextAlignment = contextualBodyTextAlignment
            self.optionsListMetrics = optionsListMetrics
            self.optionsListButtonStyle = optionsListButtonStyle
            self.maxContainerWidth = maxContainerWidth
            self.contentFadeInDelay = contentFadeInDelay
            self.contentFadeInDuration = contentFadeInDuration
        }
    }

}

// MARK: ContextualOnboardingMetrics + OptionsList

public extension OnboardingTheme.ContextualOnboardingMetrics {

    /// Layout metrics for individual contextual onboarding option list rows.
    struct OptionsListMetrics: Equatable {
        /// Corner radius for a single option list row.
        public let cornerRadius: CGFloat
        /// Border width for a single option list row.
        public let borderWidth: CGFloat
        /// Inset applied when stroking the row border.
        public let borderInset: CGFloat
        /// Rendered size of the leading icon in a row.
        public let iconSize: CGSize
        /// Maximum height for a single option list row.
        public let itemMaxHeight: CGFloat
        /// Maximum width for a single option list row.
        public let itemMaxWidth: CGFloat?
        /// Vertical spacing between adjacent option list rows.
        public let interItemSpacing: CGFloat?
        /// Horizontal spacing between icon and text within a row.
        public let innerContentHorizontalSpacing: CGFloat?

        public init(
            cornerRadius: CGFloat,
            borderWidth: CGFloat,
            borderInset: CGFloat,
            iconSize: CGSize,
            itemMaxHeight: CGFloat,
            itemMaxWidth: CGFloat? = .infinity,
            interItemSpacing: CGFloat? = nil,
            innerContentHorizontalSpacing: CGFloat? = nil
        ) {
            self.cornerRadius = cornerRadius
            self.borderWidth = borderWidth
            self.borderInset = borderInset
            self.iconSize = iconSize
            self.itemMaxHeight = itemMaxHeight
            self.itemMaxWidth = itemMaxWidth
            self.interItemSpacing = interItemSpacing
            self.innerContentHorizontalSpacing = innerContentHorizontalSpacing
        }
    }

}
