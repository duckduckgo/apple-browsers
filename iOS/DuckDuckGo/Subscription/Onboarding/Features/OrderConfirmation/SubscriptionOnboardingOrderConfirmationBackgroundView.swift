//
//  SubscriptionOnboardingOrderConfirmationBackgroundView.swift
//  DuckDuckGo
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

/// The order confirmation screen's background: the wide `Dax-Background` illustration, full-bleed at
/// the bottom-left, with the standing `Dax-Thumbs-Up` character layered on top of it near the
/// bottom-left corner.
///
/// Dax-Thumbs-Up is hidden while `state` is still `.loading`, or once resolved to `.freeTrial`, while
/// the card's measured `calendarFrame` hasn't arrived yet or leaves no room for it (neither below it
/// nor to its left). With `.paid` (confirmed no card), nothing constrains it and it always shows.
struct SubscriptionOnboardingOrderConfirmationBackgroundView: View {
    static let coordinateSpaceName = "subscriptionOnboardingOrderConfirmationPage"

    private enum Metrics {
        /// How far the background shifts down from its safe-area-respecting bottom-aligned position
        /// toward the true screen edge
        static let overhang: CGFloat = 48
        /// `Dax-Background.imageset`'s native size.
        static let backgroundNativeWidth: CGFloat = 959
        static let backgroundAspectRatio: CGFloat = 348.0 / 959.0
        /// `Dax-Thumbs-Up.imageset`'s native size.
        static let thumbsUpSize = CGSize(width: 185, height: 235)
        static let thumbsUpLeadingInset: CGFloat = SubscriptionOnboardingPageInsets.horizontal
    }

    let state: SubscriptionOnboardingOrderConfirmationViewModel.State
    /// The free-trial calendar card's measured frame, in `coordinateSpaceName`
    let calendarFrame: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let pageFrame = proxy.frame(in: .named(Self.coordinateSpaceName))
            let showsThumbsUp = hasRoomForThumbsUp(pageFrame: pageFrame)

            // Full width when the screen is wider than the artwork's native size; otherwise native size,
            // left-aligned, with the excess simply running off the right edge.
            let backgroundWidth = max(proxy.size.width, Metrics.backgroundNativeWidth)
            let backgroundHeight = backgroundWidth * Metrics.backgroundAspectRatio

            ZStack(alignment: .bottomLeading) {
                Image(.daxBackground)
                    .resizable()
                    .frame(width: backgroundWidth, height: backgroundHeight)
                    .offset(y: Metrics.overhang)

                if showsThumbsUp {
                    Image(.daxThumbsUp)
                        .resizable()
                        .frame(width: Metrics.thumbsUpSize.width, height: Metrics.thumbsUpSize.height)
                        .padding(.leading, Metrics.thumbsUpLeadingInset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        // Only the width measurement needs to ignore the safe area
        // The vertical edge stays safe-area-respecting
        .ignoresSafeArea(edges: .horizontal)
        .accessibilityHidden(true)
    }

    /// Whether there's room for Dax-Thumbs-Up below, or to the left of, the calendar card
    private func hasRoomForThumbsUp(pageFrame: CGRect) -> Bool {
        switch state {
        case .loading:
            return false
        case .paid:
            return true
        case .freeTrial:
            guard let calendarFrame else { return false }
            let hasVerticalRoom = pageFrame.maxY - calendarFrame.maxY >= Metrics.thumbsUpSize.height
            let hasHorizontalRoom = calendarFrame.minX - (pageFrame.minX + Metrics.thumbsUpLeadingInset) >= Metrics.thumbsUpSize.width
            return hasVerticalRoom || hasHorizontalRoom
        }
    }
}

#if DEBUG

private func backgroundPreview(state: SubscriptionOnboardingOrderConfirmationViewModel.State, calendarFrame: CGRect? = nil) -> some View {
    SubscriptionOnboardingOrderConfirmationBackgroundView(state: state, calendarFrame: calendarFrame)
        .coordinateSpace(name: SubscriptionOnboardingOrderConfirmationBackgroundView.coordinateSpaceName)
}

#Preview("Loading — thumbs-up hidden") {
    RebrandedPreview {
        backgroundPreview(state: .loading)
    }
}

#Preview("Paid — thumbs-up always shows") {
    RebrandedPreview {
        backgroundPreview(state: .paid)
    }
}

#Preview("Enough height — thumbs-up shows low, left") {
    RebrandedPreview {
        // A calendar card ending well above the bottom of the screen.
        backgroundPreview(state: .previewFreeTrial(), calendarFrame: CGRect(x: 24, y: 200, width: 342, height: 220))
    }
}

#Preview("Not enough height, enough width (iPad-style)") {
    RebrandedPreview {
        // A narrower, centered card (as on a wide/iPad screen) that reaches close to the bottom but
        // leaves room to its left.
        backgroundPreview(state: .previewFreeTrial(), calendarFrame: CGRect(x: 220, y: 500, width: 354, height: 260))
    }
}

#Preview("No room — thumbs-up hidden") {
    RebrandedPreview {
        // A full-width card that both reaches close to the bottom and leaves no room to its left.
        backgroundPreview(state: .previewFreeTrial(), calendarFrame: CGRect(x: 24, y: 500, width: 342, height: 260))
    }
}

#endif
