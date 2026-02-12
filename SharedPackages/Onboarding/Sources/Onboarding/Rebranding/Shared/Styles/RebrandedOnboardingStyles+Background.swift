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

public enum ContextualOnboardingBackgroundType {
    case tryASearch
    case tryASearchCompleted
    case tryVisitingASite
    case trackers
    case fireDialog
    case endOfJourney
    case privacyProTrial

    var alignment: Alignment {
        switch self {
        case .tryASearch, .tryASearchCompleted, .tryVisitingASite, .trackers, .fireDialog, .endOfJourney:
            return .trailing
        case .privacyProTrial:
            return .center
        }
    }

    var image: Image {
        switch self {
        case .tryASearch:
            return OnboardingRebranding.OnboardingImages.Contextual.tryASearchBackground
        case .tryASearchCompleted:
            return OnboardingRebranding.OnboardingImages.Contextual.tryASearchBackground
        case .tryVisitingASite:
            return OnboardingRebranding.OnboardingImages.Contextual.tryASearchBackground
        case .trackers:
            return OnboardingRebranding.OnboardingImages.Contextual.tryASearchBackground
        case .fireDialog:
            return OnboardingRebranding.OnboardingImages.Contextual.tryASearchBackground
        case .endOfJourney:
            return OnboardingRebranding.OnboardingImages.Contextual.tryASearchBackground
        case .privacyProTrial:
            return OnboardingRebranding.OnboardingImages.Contextual.tryASearchBackground
        }
    }
}

extension OnboardingRebranding.OnboardingStyles {

    struct ContextualBackgroundStyle: ViewModifier {
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
                .ignoresSafeArea(.container, edges: [.bottom, .horizontal])

                content
            }
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
        value = nextValue()
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

    @ViewBuilder
    /// Applies the contextual onboarding background illustration.
    ///
    /// If an animation context is provided, the illustration animates in from the bottom edge.
    func applyContextualOnboardingBackground(backgroundType: ContextualOnboardingBackgroundType, animationContext: BackgroundAnimationContext? = nil) -> some View {
        if let animationContext {
            self.modifier(OnboardingRebranding.OnboardingStyles.AnimatedContextualBackgroundStyle(backgroundType: backgroundType, animation: animationContext.animation, delay: animationContext.delay))
        } else {
            self.modifier(OnboardingRebranding.OnboardingStyles.ContextualBackgroundStyle(backgroundType: backgroundType, imageOffsetY: 0))
        }
    }

}
