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
}

extension OnboardingRebranding.OnboardingStyles {

    struct ContextualBackgroundStyle: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme

        let backgroundType: ContextualOnboardingBackgroundType
        let imageOffsetY: CGFloat

        func body(content: Content) -> some View {
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    Image.contextualBackgroundTryASearch
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: BackgroundIllustrationHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        )
                        .offset(y: imageOffsetY)
                }
                .frame(maxWidth: .infinity, alignment: backgroundType.alignment)
                .ignoresSafeArea(.container, edges: [.bottom, .horizontal])

                content
            }
        }

        private var backgroundColor: Color {
            switch colorScheme {
            case .light:
                Color.white
            case .dark:
                Color(red: 19/255, green: 62/255, blue: 124/255)
            @unknown default:
                Color.white
            }
        }
    }

    struct AnimatedContextualBackgroundStyle: ViewModifier {
        @State private var didAppear: Bool = false
        @State var imageHeight: CGFloat = 0.0

        let backgroundType: ContextualOnboardingBackgroundType
        var animation: Animation = .easeIn(duration: 0.3)
        var delay: Double = 0.1

        func body(content: Content) -> some View {
            content
                .modifier(
                    ContextualBackgroundStyle(
                        backgroundType: backgroundType,
                        imageOffsetY: didAppear ? 0 : imageHeight + 16
                    )
                )
                .onAppear {
                    withAnimation(animation.delay(delay)) {
                        didAppear = true
                    }
                }
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

public struct BackgroundAnimationContext {
    let animation: Animation
    let delay: TimeInterval

    public init(animation: Animation, delay: TimeInterval) {
        self.animation = animation
        self.delay = delay
    }

    public static let `default` = BackgroundAnimationContext(animation: .easeInOut(duration: 0.3), delay: 0.1)
}

public extension View {

    @ViewBuilder
    func applyContextualOnboardingBackground(backgroundType: ContextualOnboardingBackgroundType, animationContext: BackgroundAnimationContext? = nil) -> some View {
        if let animationContext {
            self.modifier(OnboardingRebranding.OnboardingStyles.AnimatedContextualBackgroundStyle(backgroundType: backgroundType, animation: animationContext.animation, delay: animationContext.delay))
        } else {
            self.modifier(OnboardingRebranding.OnboardingStyles.ContextualBackgroundStyle(backgroundType: backgroundType, imageOffsetY: 0))
        }
    }

}
