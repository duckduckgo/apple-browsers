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
        @State private var imageGlobalFrame: CGRect = .zero

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
                                        .preference(key: BackgroundIllustrationFramePreferenceKey.self, value: proxy.frame(in: .global))
                                        .onPreferenceChange(BackgroundIllustrationFramePreferenceKey.self) { frame in
                                            imageGlobalFrame = frame
                                        }
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
        //   - Inset = 20
        //   - Target position: 600 + 20 = 620
        //   - Offset needed: 620 - 730 = -110 (move up 110 points)
        private func calculateImageOffset(for geometry: GeometryProxy) -> CGFloat {
            #if os(iOS)
            // Early exit if no keyboard is visible
            guard keyboardResponder.keyboardFrame.height > 0 else { return imageOffsetY }

            // Early exit if image frame hasn't been captured yet
            guard !imageGlobalFrame.isEmpty else { return imageOffsetY }

            let keyboardFrame = keyboardResponder.keyboardFrame

            // Check if image and keyboard actually overlap
            // This is crucial for iPad where floating/split keyboards may not overlap the image
            let intersection = imageGlobalFrame.intersection(keyboardFrame)

            // No overlap = no adjustment needed
            // This handles floating keyboards, split keyboards, or keyboards that don't reach the image
            guard !intersection.isNull, intersection.height > 0 else {
                return imageOffsetY
            }

            // Calculate where the image currently is (bottom edge in global coordinates)
            let currentImageBottom = imageGlobalFrame.maxY

            // Calculate where we want the image to be (just above keyboard with inset)
            // The inset allows the image to extend slightly behind the keyboard's rounded corners
            let targetImageBottom = keyboardFrame.minY + contentInsetOffKeyboard

            // Calculate how much to move the image (positive values would move it down)
            let offset = targetImageBottom - currentImageBottom

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
    /// The image will move up so its bottom edge sits at the keyboard's top edge plus the inset.
    /// - Parameter inset: Distance in points to extend the image behind the keyboard's rounded corners. Defaults to 20pt.
    case adjustForKeyboard(inset: CGFloat = 20)

    /// Does not adjust for keyboard - background remains in its original position.
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
    /// This modifier adds a background illustration appropriate for the given onboarding step.
    /// The background can optionally animate in and adjust for keyboard appearance.
    ///
    /// - Parameters:
    ///   - backgroundType: The type of background illustration to display.
    ///   - animationContext: Optional animation configuration. When provided, the illustration animates in from the bottom edge.
    ///   - keyboardBehavior: How the background should respond to keyboard appearance. Defaults to `.ignoreKeyboard`.
    ///
    /// - Note: On iPad, keyboard adjustments only apply when the keyboard overlaps the background image.
    ///   Floating or split keyboards that don't overlap the image will not trigger adjustments.
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

/// Observable object that tracks keyboard frame changes.
///
/// This class listens to keyboard notifications and publishes the keyboard's frame
/// in global screen coordinates. Views can observe these changes to adjust their layout
/// when the keyboard appears or disappears.
final class KeyboardResponder: ObservableObject {
    /// The current keyboard frame in global screen coordinates.
    /// Returns `.zero` when the keyboard is hidden or when keyboard observation is disabled.
    @Published var keyboardFrame: CGRect = .zero

    private var cancellables: Set<AnyCancellable> = []

    /// Creates a keyboard responder.
    ///
    /// - Parameter isEnabled: Whether to observe keyboard notifications. When `false`,
    ///   no notifications are observed and `keyboardFrame` will always be `.zero`.
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
