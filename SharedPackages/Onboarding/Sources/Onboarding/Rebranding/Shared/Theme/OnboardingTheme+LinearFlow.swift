//
//  OnboardingTheme+LinearFlow.swift
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

#if os(iOS)
import MetricBuilder
#endif

public extension OnboardingTheme {

    /// Layout metrics used by the linear onboarding flow.
    struct LinearOnboardingMetrics: Equatable {
        public static func == (lhs: LinearOnboardingMetrics, rhs: LinearOnboardingMetrics) -> Bool {
            #if os(iOS)
            // `dialogVerticalOffsetPercentage` is intentionally excluded from equality.
            // MetricBuilder is a reference type and does not conform to Equatable.
            #endif
            lhs.contentOuterSpacing == rhs.contentOuterSpacing &&
            lhs.contentInnerSpacing == rhs.contentInnerSpacing &&
            lhs.buttonSpacing == rhs.buttonSpacing &&
            lhs.bubbleMaxWidth == rhs.bubbleMaxWidth &&
            lhs.bubbleTailOffset == rhs.bubbleTailOffset &&
            lhs.topMarginRatio == rhs.topMarginRatio &&
            lhs.minTopMargin == rhs.minTopMargin &&
            lhs.maxTopMargin == rhs.maxTopMargin &&
            lhs.progressBarTrailingPadding == rhs.progressBarTrailingPadding &&
            lhs.progressBarTopPadding == rhs.progressBarTopPadding &&
            lhs.rebrandingBadgeLeadingPadding == rhs.rebrandingBadgeLeadingPadding &&
            lhs.rebrandingBadgeTopPadding == rhs.rebrandingBadgeTopPadding &&
            lhs.actionsSpacing == rhs.actionsSpacing
        }

        /// Outer spacing between major content sections.
        public let contentOuterSpacing: CGFloat
        /// Inner spacing between elements within a section.
        public let contentInnerSpacing: CGFloat
        /// Spacing between vertically stacked buttons.
        public let buttonSpacing: CGFloat
        /// Spacing between the actions and the content.
        public let actionsSpacing: CGFloat
        /// Maximum width for linear onboarding bubbles.
        public let bubbleMaxWidth: CGFloat
        /// Horizontal offset for the bubble tail position (0.0–1.0).
        public let bubbleTailOffset: CGFloat
        /// Ratio used to compute the top margin from the available height.
        public let topMarginRatio: CGFloat
        /// Minimum top margin.
        public let minTopMargin: CGFloat
        /// Maximum top margin.
        public let maxTopMargin: CGFloat
        /// Trailing padding for the progress bar.
        public let progressBarTrailingPadding: CGFloat
        /// Top padding for the progress bar.
        public let progressBarTopPadding: CGFloat
        /// Leading padding for the rebranding badge.
        public let rebrandingBadgeLeadingPadding: CGFloat
        /// Top padding for the rebranding badge.
        public let rebrandingBadgeTopPadding: CGFloat

        #if os(iOS)
        /// Vertical offset percentage for the dialog, resolved at runtime based on device size class.
        public let dialogVerticalOffsetPercentage: MetricBuilder<CGFloat>
        #endif

        #if os(iOS)
        public init(
            contentOuterSpacing: CGFloat,
            contentInnerSpacing: CGFloat,
            buttonSpacing: CGFloat,
            bubbleMaxWidth: CGFloat,
            bubbleTailOffset: CGFloat,
            topMarginRatio: CGFloat,
            minTopMargin: CGFloat,
            maxTopMargin: CGFloat,
            progressBarTrailingPadding: CGFloat,
            progressBarTopPadding: CGFloat,
            rebrandingBadgeLeadingPadding: CGFloat,
            rebrandingBadgeTopPadding: CGFloat,
            dialogVerticalOffsetPercentage: MetricBuilder<CGFloat>,
            actionsSpacing: CGFloat,
        ) {
            self.contentOuterSpacing = contentOuterSpacing
            self.contentInnerSpacing = contentInnerSpacing
            self.buttonSpacing = buttonSpacing
            self.bubbleMaxWidth = bubbleMaxWidth
            self.bubbleTailOffset = bubbleTailOffset
            self.topMarginRatio = topMarginRatio
            self.minTopMargin = minTopMargin
            self.maxTopMargin = maxTopMargin
            self.progressBarTrailingPadding = progressBarTrailingPadding
            self.progressBarTopPadding = progressBarTopPadding
            self.rebrandingBadgeLeadingPadding = rebrandingBadgeLeadingPadding
            self.rebrandingBadgeTopPadding = rebrandingBadgeTopPadding
            self.dialogVerticalOffsetPercentage = dialogVerticalOffsetPercentage
            self.actionsSpacing = actionsSpacing
        }
        #else
        public init(
            contentOuterSpacing: CGFloat,
            contentInnerSpacing: CGFloat,
            buttonSpacing: CGFloat,
            bubbleMaxWidth: CGFloat,
            bubbleTailOffset: CGFloat,
            topMarginRatio: CGFloat,
            minTopMargin: CGFloat,
            maxTopMargin: CGFloat,
            progressBarTrailingPadding: CGFloat,
            progressBarTopPadding: CGFloat,
            rebrandingBadgeLeadingPadding: CGFloat,
            rebrandingBadgeTopPadding: CGFloat,
            actionsSpacing: CGFloat = 20
        ) {
            self.contentOuterSpacing = contentOuterSpacing
            self.contentInnerSpacing = contentInnerSpacing
            self.buttonSpacing = buttonSpacing
            self.bubbleMaxWidth = bubbleMaxWidth
            self.bubbleTailOffset = bubbleTailOffset
            self.topMarginRatio = topMarginRatio
            self.minTopMargin = minTopMargin
            self.maxTopMargin = maxTopMargin
            self.progressBarTrailingPadding = progressBarTrailingPadding
            self.progressBarTopPadding = progressBarTopPadding
            self.rebrandingBadgeLeadingPadding = rebrandingBadgeLeadingPadding
            self.rebrandingBadgeTopPadding = rebrandingBadgeTopPadding
            self.actionsSpacing = actionsSpacing
        }
        #endif
    }

}
