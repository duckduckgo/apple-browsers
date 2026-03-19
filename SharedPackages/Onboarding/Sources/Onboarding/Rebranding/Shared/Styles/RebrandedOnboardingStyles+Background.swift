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
import Combine
#if os(iOS)
import MetricBuilder
import UIKit
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

        @StateObject private var keyboardResponder: KeyboardResponder

        private let backgroundType: ContextualOnboardingBackgroundType
        private let imageOffsetY: CGFloat
        private let contentInsetOffKeyboard: CGFloat

        init(backgroundType: ContextualOnboardingBackgroundType, imageOffsetY: CGFloat, keyboardBehavior: KeyboardBehavior) {
            self.backgroundType = backgroundType
            self.imageOffsetY = imageOffsetY
            self.contentInsetOffKeyboard = keyboardBehavior.contentInset
            _keyboardResponder = StateObject(wrappedValue: KeyboardResponder(isEnabled: keyboardBehavior.isEnabled))
        }

        func body(content: Content) -> some View {
            GeometryReader { geometry in
                ZStack {
                    theme.colorPalette.background
                        .ignoresSafeArea()

                    ZStack(alignment: backgroundType.alignment) {
                        Color.clear
                            .ignoresSafeArea()

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
                            .offset(y: calculateImageOffset(for: geometry))
                            .animation(.easeOut(duration: 0.16), value: keyboardResponder.keyboardFrame)
                    }
                    .frame(maxWidth: .infinity, alignment: backgroundType.alignment)
                    .clipped()
                    .ignoresSafeArea(edges: ignoresSafeAreaEdges)

                    content
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            }
            .ignoresSafeArea(.keyboard)
        }

        private func calculateImageOffset(for geometry: GeometryProxy) -> CGFloat {
            #if os(iOS)
            guard keyboardResponder.keyboardFrame.height > 0 else { return imageOffsetY }

            let viewGlobalFrame = geometry.frame(in: .global)

            // Convert keyboard's global Y position to local coordinate space
            let keyboardTopInLocalCoordinates = keyboardResponder.keyboardFrame.height > 0 ? keyboardResponder.keyboardFrame.minY - viewGlobalFrame.minY : 0

            // keyboardTopInLocal is where the keyboard starts in our local coordinate space
            // For bottom-aligned image, current position is at contentHeight
            // We want to move it to keyboardTopInLocal + cornerOverlap (so it extends 30px behind keyboard)
            // Offset = target position - current position
            let targetY = keyboardTopInLocalCoordinates + contentInsetOffKeyboard
            let currentY = geometry.size.height
            let offset = targetY - currentY

            return offset
            #else
            return imageOffsetY
            #endif
        }

        #if os(iOS)
        private static let maxHeightMetricsBuilder = MetricBuilder<CGFloat?>(default: nil).iPad(242).iPhone(landscape: 242)
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
        let keyboardBehavior: KeyboardBehavior

        func body(content: Content) -> some View {
            content
                .modifier(
                    ContextualBackgroundStyle(
                        backgroundType: backgroundType,
                        imageOffsetY: didAppear ? 0 : imageHeight + 16,
                        keyboardBehavior: keyboardBehavior
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

public enum KeyboardBehavior: Equatable {
    case adjustForKeyboard(inset: CGFloat = 20)
    case ignoreKeyboard

    var isEnabled: Bool {
        self != .ignoreKeyboard
    }

    var contentInset: CGFloat {
        switch self {
        case .adjustForKeyboard(inset: let inset):
            return inset
        case .ignoreKeyboard:
            return 0
        }
    }
}

public extension View {

    /// Applies the contextual onboarding background illustration.
    ///
    /// If an animation context is provided, the illustration animates in from the bottom edge.
    @ViewBuilder
    func applyContextualOnboardingBackground(
        backgroundType: ContextualOnboardingBackgroundType,
        animationContext: BackgroundAnimationContext? = nil,
        keyboardBehavior: KeyboardBehavior = .ignoreKeyboard
    ) -> some View {
        if let animationContext {
            self.modifier(OnboardingRebranding.OnboardingStyles.AnimatedContextualBackgroundStyle(backgroundType: backgroundType, animation: animationContext.animation, delay: animationContext.delay, keyboardBehavior: keyboardBehavior))
        } else {
            self.modifier(OnboardingRebranding.OnboardingStyles.ContextualBackgroundStyle(backgroundType: backgroundType, imageOffsetY: 0, keyboardBehavior: keyboardBehavior))
        }
    }

}

final class KeyboardResponder: ObservableObject {
    @Published var keyboardFrame: CGRect = .zero

    private var cancellables: Set<AnyCancellable> = []

    init(isEnabled: Bool = true) {
        guard isEnabled else { return }

        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillShowNotification)
            .map { notification in
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            }
            .assign(to: \.keyboardFrame, onWeaklyHeld: self)
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in
                CGRect.zero
            }
            .assign(to: \.keyboardFrame, onWeaklyHeld: self)
            .store(in: &cancellables)
    }
}
