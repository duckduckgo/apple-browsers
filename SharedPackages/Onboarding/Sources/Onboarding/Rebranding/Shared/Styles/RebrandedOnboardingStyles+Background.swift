//
//  RebrandedOnboardingStyles+Background.swift
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

public enum ContextualOnboardingBackgroundType {
    case tryASearch
    case tryASearchCompleted
    case tryVisitingASiteNTP
    case trackers
    case fireDialog
    case endOfJourney
    case privacyProTrial

    var alignment: Alignment {
        switch self {
        case .tryASearch, .tryASearchCompleted, .tryVisitingASiteNTP, .trackers, .fireDialog:
            return .bottomTrailing
        case .endOfJourney, .privacyProTrial:
            return .center
        }
    }

    var image: Image {
        switch self {
        case .tryASearch:
            return OnboardingRebrandingImages.Contextual.tryASearchBackground
        case .tryASearchCompleted:
            return OnboardingRebrandingImages.Contextual.searchDoneBackground
        case .tryVisitingASiteNTP:
            return OnboardingRebrandingImages.Contextual.tryASiteBackground
        case .trackers:
            return OnboardingRebrandingImages.Contextual.trackerBlockedBackground
        case .fireDialog:
            return OnboardingRebrandingImages.Contextual.trackerBlockedBackground
        case .endOfJourney:
            return OnboardingRebrandingImages.Contextual.endOfJourneyBackground
        case .privacyProTrial:
            return OnboardingRebrandingImages.Contextual.subscriptionPromoBackground
        }
    }
}

extension OnboardingRebranding.OnboardingStyles {

    struct ContextualBackgroundStyle: ViewModifier {
        @Environment(\.horizontalSizeClass) private var hSizeClass
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.onboardingTheme) private var theme

        let backgroundType: ContextualOnboardingBackgroundType
        let imageOffsetY: CGFloat

        func body(content: Content) -> some View {
            ZStack {
                theme.colorPalette.background
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    backgroundType.image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: maxHeightMetrics)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: BackgroundIllustrationHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        )
                        .offset(y: imageOffsetY)
                }
                .frame(maxWidth: .infinity, alignment: backgroundType.alignment)
                .clipped()
                .ignoresSafeArea(.container, edges: ignoresSafeAreaEdges)

                content
            }
        }

        #if os(iOS)
        private static let maxHeightMetricsBuilder = MetricBuilder<CGFloat?>(default: nil).iPad(200).iPhone(landscape: 200)
        // iPhone excludes .bottom to prevent background from being covered by the address bar when it is positioned at the bottom
        private static let ignoreSafeAreaEdgesBuilder = MetricBuilder<Edge.Set>(default: [.horizontal]).iPad([.bottom, .horizontal])
        #endif

        var maxHeightMetrics: CGFloat? {
            #if os(iOS)
            // iOS uses responsive metrics based on device type
            return Self.maxHeightMetricsBuilder.build(v: vSizeClass, h: hSizeClass)
            #else
            // macOS: Fixed value. Customise when implementing macOS contextual onboarding.
            return nil
            #endif
        }

        var ignoresSafeAreaEdges: Edge.Set {
            #if os(iOS)
            // iOS uses responsive metrics based on device type
            return Self.ignoreSafeAreaEdgesBuilder.build(v: vSizeClass, h: hSizeClass)
            #else
            // macOS: Customise when implementing macOS contextual onboarding.
            return .all
            #endif
        }
    }

    struct AnimatedContextualBackgroundStyle: ViewModifier {
        @State private var didAppear: Bool = false
        @State var imageHeight: CGFloat = 0.0

        let backgroundType: ContextualOnboardingBackgroundType
        let animation: Animation
        let delay: TimeInterval

        func body(content: Content) -> some View {
            content
                .modifier(
                    ContextualBackgroundStyle(
                        backgroundType: backgroundType,
                        imageOffsetY: didAppear ? 0 : imageHeight + 16
                    )
                )
                .onPreferenceChange(BackgroundIllustrationHeightPreferenceKey.self) { imageHeight in
                    guard imageHeight > 0 else { return }
                    self.imageHeight = imageHeight
                    guard !didAppear else { return }
                    withAnimation(animation.delay(delay)) {
                        didAppear = true
                    }
                }
        }
    }

}

// MARK: - Helpers

private struct BackgroundIllustrationHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Contextual Onboarding + View Extension

/// Animation configuration used when presenting contextual onboarding background illustrations.
public struct BackgroundAnimationContext {
    /// Animation curve and duration used for the background entrance.
    let animation: Animation
    /// Delay, in seconds, applied before starting the background entrance animation.
    let delay: TimeInterval

    /// Creates a background animation context.
    ///
    /// - Parameters:
    ///   - animation: Animation used for the entrance transition.
    ///   - delay: Delay, in seconds, before the animation starts.
    public init(animation: Animation, delay: TimeInterval) {
        self.animation = animation
        self.delay = delay
    }

    /// Default animation context used by contextual onboarding backgrounds.
    public static let `default` = BackgroundAnimationContext(animation: .easeInOut(duration: 0.3), delay: 0.1)
}

public extension View {

    /// Applies the contextual onboarding background illustration.
    ///
    /// If an animation context is provided, the illustration animates in from the bottom edge.
    @ViewBuilder
    func applyContextualOnboardingBackground(backgroundType: ContextualOnboardingBackgroundType, animationContext: BackgroundAnimationContext? = nil) -> some View {
        if let animationContext {
            self.modifier(OnboardingRebranding.OnboardingStyles.AnimatedContextualBackgroundStyle(backgroundType: backgroundType, animation: animationContext.animation, delay: animationContext.delay))
        } else {
            self.modifier(OnboardingRebranding.OnboardingStyles.ContextualBackgroundStyle(backgroundType: backgroundType, imageOffsetY: 0))
        }
    }

}
