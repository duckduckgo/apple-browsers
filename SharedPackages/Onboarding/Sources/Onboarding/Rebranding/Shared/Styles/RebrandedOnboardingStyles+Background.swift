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
    case endOfJourneyNTP
    case privacyProTrial

    var alignment: Alignment {
        switch self {
        case .tryASearch, .tryASearchCompleted, .tryVisitingASiteNTP, .trackers, .fireDialog:
            return .bottomTrailing
        case .endOfJourney, .endOfJourneyNTP, .privacyProTrial:
            return .bottom
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
        case .endOfJourneyNTP:
            return OnboardingRebrandingImages.Contextual.endOfJourneyBackgroundNewTab
        case .privacyProTrial:
            return OnboardingRebrandingImages.Contextual.subscriptionPromoBackground
        }
    }
}

private enum ContextualBackgroundStyleMetrics {
    static let referenceBackgroundImageHeight: CGFloat = 290
    static let referenceBackgroundImageOffset: CGFloat = 90
    static let backgroundImageKeyboardAnimation = Animation.easeOut(duration: 0.16)
}

extension OnboardingRebranding.OnboardingStyles {

    struct ContextualBackgroundStyle: ViewModifier {
        @Environment(\.horizontalSizeClass) private var hSizeClass
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.onboardingTheme) private var theme

        #if os(iOS)
        @StateObject private var keyboardResponder: KeyboardResponder
        private let keyboardBehavior: KeyboardBehavior
        #endif

        @State private var imageGlobalFrame: CGRect = .zero

        private let backgroundType: ContextualOnboardingBackgroundType
        private let imageOffsetY: CGFloat

        #if os(iOS)
        init(backgroundType: ContextualOnboardingBackgroundType, imageOffsetY: CGFloat, keyboardBehavior: KeyboardBehavior) {
            self.backgroundType = backgroundType
            self.keyboardBehavior = keyboardBehavior
            self.imageOffsetY = imageOffsetY
            _keyboardResponder = StateObject(wrappedValue: KeyboardResponder(isEnabled: keyboardBehavior.isEnabled))
        }
        #elseif os(macOS)
        init(backgroundType: ContextualOnboardingBackgroundType, imageOffsetY: CGFloat) {
            self.backgroundType = backgroundType
            self.imageOffsetY = imageOffsetY
        }
        #endif

        func body(content: Content) -> some View {
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
                                            .preference(key: BackgroundIllustrationFramePreferenceKey.self, value: proxy.frame(in: .global))
                                    }
                                )
                                .offset(y: calculateImageOffset())
                        #if os(iOS)
                                .animation(ContextualBackgroundStyleMetrics.backgroundImageKeyboardAnimation, value: keyboardResponder.keyboardFrame)
                        #endif

                    }
                    .frame(maxWidth: .infinity, alignment: backgroundType.alignment)
                    .clipped()
                    .ignoresSafeArea(edges: ignoresSafeAreaEdges)
                    .onPreferenceChange(BackgroundIllustrationFramePreferenceKey.self) { frame in
                        imageGlobalFrame = frame
                    }

                    content
                }
                .ignoresSafeArea(.keyboard)
        }

        // Calculates the vertical offset needed to adjust the background image when the keyboard appears.
        // The offset calculation works as follows:
        // 1. Get the keyboard frame in global coordinates (from KeyboardResponder)
        // 2. Get the image frame in global coordinates (captured via preference key)
        // 3. Calculate intersection to detect if keyboard overlaps the image
        // 4. If overlap exists, calculate offset to move image's bottom edge to keyboard's top edge
        //
        // Example scenario:
        //   - Image bottom at Y=730 (imageGlobalFrame.maxY)
        //   - Keyboard top at Y=600 (keyboardFrame.minY)
        //   - Offset = From reference image
        //   - Target position = 600 + offset
        //   - Offset needed: 600 + offset - 730
        private func calculateImageOffset() -> CGFloat {
            #if os(iOS)
            // If screen does not respond to keyboard notifications, return default imageOffsetY
            guard keyboardBehavior.isEnabled else { return imageOffsetY }

            // Inset of the image calculated from the reference image + reference offset scaled for actual image size.
            let keyboardImageOffsetY = ContextualBackgroundStyleMetrics.referenceBackgroundImageOffset * imageGlobalFrame.size.height / ContextualBackgroundStyleMetrics.referenceBackgroundImageHeight

            // Early exit if no keyboard is visible
            guard keyboardResponder.keyboardFrame.height > 0 else { return keyboardImageOffsetY }

            // Early exit if image frame hasn't been captured yet
            guard imageGlobalFrame != .zero else { return imageOffsetY }

            let keyboardFrame = keyboardResponder.keyboardFrame

            // Check if image and keyboard actually overlap
            // This is handle the scenario on iPad where floating/split keyboards may not overlap the image
            let intersection = imageGlobalFrame.intersection(keyboardFrame)

            // No overlap = no adjustment needed
            // This handles floating keyboards, split keyboards, or keyboards that don't reach the image
            guard !intersection.isNull, intersection.height > 0 else {
                return keyboardImageOffsetY
            }

            // Calculate where the image currently is (bottom edge in global coordinates) + image offset Y.
            // The image illustration is a tall version used to have the image extends behind the rounded corner of the keyboards.
            // The Y offset is subtracted from the image maxY because otherwise when the keyboard comes up the difference between keyboard minY and image maxY would consider the portion of the image that is pushed beyond the view and it would be lifted too much.
            let currentImageBottom = imageGlobalFrame.maxY - keyboardImageOffsetY

            // Calculate where we want the image to be (just above keyboard with offset)
            // The offset allows the image to extend slightly behind the keyboard's rounded corners
            let targetImageBottom = keyboardFrame.minY + keyboardImageOffsetY

            // Calculate how much to move the image
            let offset = targetImageBottom - currentImageBottom

            return offset
            #else
            return imageOffsetY
            #endif
        }

        #if os(iOS)
        private static let maxHeightContextualAssets = MetricBuilder<CGFloat?>(default: nil).iPad(200).iPhone(landscape: 200) // Contextual assets have smaller height than new tab page ones.
        private static let maxHeightNewTabPageAssets = MetricBuilder<CGFloat?>(default: nil).iPad(290).iPhone(landscape: 290)
        // iPhone excludes .bottom to prevent background from being covered by the address bar when it is positioned at the bottom
        private static let ignoreSafeAreaEdgesBuilder = MetricBuilder<Edge.Set>(default: [.horizontal]).iPad([.bottom, .horizontal])
        #endif

        var maxHeightMetrics: CGFloat? {
            #if os(iOS)
            // iOS uses responsive metrics based on device type
            switch backgroundType {
            case .tryASearchCompleted, .trackers, .fireDialog, .endOfJourney:
                return Self.maxHeightContextualAssets.build(v: vSizeClass, h: hSizeClass)
            case .tryASearch, .tryVisitingASiteNTP, .endOfJourneyNTP, .privacyProTrial:
                return Self.maxHeightNewTabPageAssets.build(v: vSizeClass, h: hSizeClass)
            }
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
                    backgroundStyle
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

        private var backgroundStyle: ContextualBackgroundStyle {
            #if os(iOS)
            ContextualBackgroundStyle(
                backgroundType: backgroundType,
                imageOffsetY: didAppear ? 0 : imageHeight + 16,
                keyboardBehavior: keyboardBehavior
            )
            #elseif os(macOS)
            ContextualBackgroundStyle(
                backgroundType: backgroundType,
                imageOffsetY: didAppear ? 0 : imageHeight + 16
            )
            #endif
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

private struct BackgroundIllustrationFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
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

/// Defines how the contextual onboarding background should respond to keyboard appearance.
public enum KeyboardBehavior: Equatable {
    /// Adjusts the background image position when the keyboard appears to keep it visible.
    /// The image will move up so its bottom edge sits at the keyboard's top edge plus an offset calculated dynamically based on the image size.
    case adjustForKeyboard

    /// Does not adjust for keyboard - background remains in its original position.
    case ignoreKeyboard

    var isEnabled: Bool {
        self != .ignoreKeyboard
    }
}

public extension View {

    /// Applies a keyboard-aware background for new tab page onboarding dialogs.
    ///
    /// This modifier is designed for onboarding dialogs shown on the new tab page where
    /// keyboard interaction is expected (e.g., search input). The background will automatically
    /// adjust its position when the keyboard appears to remain visible.
    ///
    /// The background appears immediately without entrance animation.
    ///
    /// - Parameter backgroundType: The type of background illustration to display.
    func applyNewTabOnboardingBackground(
        backgroundType: ContextualOnboardingBackgroundType
    ) -> some View {
        #if os(iOS)
            self.modifier(
                OnboardingRebranding.OnboardingStyles.ContextualBackgroundStyle(
                    backgroundType: backgroundType,
                    imageOffsetY: 0,
                    keyboardBehavior: .adjustForKeyboard
                )
            )
        #elseif os(macOS)
            self.modifier(
                OnboardingRebranding.OnboardingStyles.ContextualBackgroundStyle(
                    backgroundType: backgroundType,
                    imageOffsetY: 0
                )
            )
        #endif
    }

    /// Applies an animated background for contextual onboarding dialogs.
    ///
    /// This modifier is designed for onboarding dialogs shown during browsing (contextual).
    /// The background animates in from the bottom edge with a fade/slide effect.
    ///
    /// No keyboard adjustment is performed as these dialogs don't typically involve keyboard interaction.
    ///
    /// - Parameters:
    ///   - backgroundType: The type of background illustration to display.
    ///   - animationContext: Animation configuration. Defaults to `.default`.
    func applyAnimatedContextualOnboardingBackground(
        backgroundType: ContextualOnboardingBackgroundType,
        animationContext: BackgroundAnimationContext = .default
    ) -> some View {
        self.modifier(
            OnboardingRebranding.OnboardingStyles.AnimatedContextualBackgroundStyle(
                backgroundType: backgroundType,
                animation: animationContext.animation,
                delay: animationContext.delay,
                keyboardBehavior: .ignoreKeyboard
            )
        )
    }

}

#if os(iOS)
/// Observable object that tracks keyboard frame changes.
///
/// This class listens to keyboard notifications and publishes the keyboard's frame
/// in global screen coordinates. Views can observe these changes to adjust their layout
/// when the keyboard appears or disappears.
public final class KeyboardResponder: ObservableObject {
    /// The current keyboard frame in global screen coordinates.
    /// Returns `.zero` when the keyboard is hidden or when keyboard observation is disabled.
    @Published public private(set) var keyboardFrame: CGRect = .zero

    private var cancellables: Set<AnyCancellable> = []

    /// Creates a keyboard responder.
    ///
    /// - Parameter isEnabled: Whether to observe keyboard notifications. When `false`,
    ///   no notifications are observed and `keyboardFrame` will always be `.zero`.
    public init(isEnabled: Bool = true) {
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
#endif
