//
//  SubscriptionOnboardingHeaderView.swift
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
import DesignResourcesKit
import UIComponents

/// The centered header for a post-subscription onboarding section screen: an optional 64×64 ``Graphic``
/// above a required title and an optional explanation. The explanation is rendered as Markdown, so it can
/// carry a tappable inline link; because every link leads to the current section's info screen, a tap
/// simply fires `onInfoLinkTap` (the flow opens that screen). When `onInfoLinkTap` is nil, links defer to
/// the system URL handler. Mirrors the layout of `SettingsDescriptionView`.
struct SubscriptionOnboardingHeaderView: View {
    private enum Metrics {
        static let graphicSize: CGFloat = 64
        static let graphicBottomSpacing: CGFloat = 40
        static let explanationTopSpacing: CGFloat = 4
    }

    private let visual: Graphic?
    private let title: String
    private let explanation: String?
    private let onInfoLinkTap: (() -> Void)?

    init(visual: Graphic? = nil,
         title: String,
         explanation: String? = nil,
         onInfoLinkTap: (() -> Void)? = nil) {
        self.visual = visual
        self.title = title
        self.explanation = explanation
        self.onInfoLinkTap = onInfoLinkTap
    }

    var body: some View {
        VStack(spacing: 0) {
            if let visual {
                GraphicView(visual: visual, size: Metrics.graphicSize)
                    .accessibilityHidden(true)
                    .padding(.bottom, Metrics.graphicBottomSpacing)
            }

            Text(title)
                .daxTitle1()
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textPrimary))

            if let explanation {
                explanationView(explanation)
                    .padding(.top, Metrics.explanationTopSpacing)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension SubscriptionOnboardingHeaderView {
    /// The explanation renders Markdown (so `[label](url)` becomes a tappable link). Every link leads to
    /// the current section's info screen, so any tap fires `onInfoLinkTap`; when it's nil the tap defers to
    /// the system URL handler.
    func explanationView(_ explanation: String) -> some View {
        Text(LocalizedStringKey(explanation))
            .daxSubheadRegular()
            .multilineTextAlignment(.center)
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .tintIfAvailable(Color(designSystemColor: .accentPrimary))
            .environment(\.openURL, OpenURLAction { _ in
                guard let onInfoLinkTap else { return .systemAction }
                onInfoLinkTap()
                return .handled
            })
    }
}

#if DEBUG

private struct SubscriptionOnboardingHeaderViewPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 48) {
                SubscriptionOnboardingHeaderView(
                    title: "Title only")

                SubscriptionOnboardingHeaderView(
                    visual: .image(Image(systemName: "checkmark.shield.fill")),
                    title: "Title with explanation",
                    explanation: "A short explanation that wraps onto a couple of lines under the title.")

                SubscriptionOnboardingHeaderView(
                    title: "No graphic",
                    explanation: "This variation omits the graphic, so the title sits at the top of the header.")

                SubscriptionOnboardingHeaderView(
                    visual: .image(Image(systemName: "checkmark.shield.fill")),
                    title: "Title with a link",
                    explanation: "An explanation with a tappable [Learn More](learn-more) link.",
                    onInfoLinkTap: {})
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingHeaderViewPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingHeaderViewPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingHeaderViewPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
