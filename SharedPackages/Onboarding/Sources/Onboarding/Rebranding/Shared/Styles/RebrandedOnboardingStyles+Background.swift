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
import CombineExtensions
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
    case endOfJourneyNTPChat
    case privacyProTrial

    var alignment: Alignment {
        switch self {
        case .tryASearch, .tryASearchCompleted, .tryVisitingASiteNTP, .trackers, .fireDialog:
            return .bottomTrailing
        case .endOfJourneyNTPChat:
            return .bottomLeading
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
        case .endOfJourneyNTPChat:
            return OnboardingRebrandingImages.Contextual.successChatBackground
        case .privacyProTrial:
            return OnboardingRebrandingImages.Contextual.subscriptionPromoBackground
        }
    }
}

private enum ContextualBackgroundStyleMetrics {
    static let referenceBackgroundImageHeight: CGFloat = 290
    static let referenceBackgroundImageOffset: CGFloat = 90
}

/// Inner-shadow approximation of Figma's "Inline Dax Dialog" effect token — originally two
/// stacked INNER_SHADOW passes (Shadow/Purple `#3E228C @ 6 %` offset (0,-4) blur 8, and
/// Shadow/Blue `#1E42A4 @ 9 %` offset (0,-1) blur 0) — collapsed into a single vertical
/// gradient band painted along the panel's inside-bottom edge. The effect mimics the web
/// view beneath the panel casting a shadow upward onto the contextual onboarding.
///
/// A `LinearGradient` band is used in place of `ShadowStyle.inner(...)` (iOS 16+) so the
/// implementation works on the Onboarding package's iOS 15 deployment target.
private enum ContextualBackgroundShadowMetrics {
    /// Opacity-weighted blend of `Shadow/Purple` (#3E228C @ 6 %) and `Shadow/Blue` (#1E42A4
    /// @ 9 %). Resulting tint ≈ #2B359A; combined alpha ≈ 0.15.
    static let color = Color(red: 43.0 / 255.0, green: 53.0 / 255.0, blue: 154.0 / 255.0).opacity(0.15)
    /// Vertical extent of the inner-shadow band. Inherits Shadow/Purple's blur radius —
    /// Shadow/Blue's pass had zero blur (a 1 px hairline) so it doesn't widen the band.
    static let height: CGFloat = 8
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

        @State private var imageHeight: CGFloat = 0
        @State private var imageBottomY: CGFloat = 0

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
                    .overlay(
                        ZStack(alignment: backgroundType.alignment) {
                            Color.clear
                            backgroundType.image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: maxHeightMetrics)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(key: BackgroundIllustrationHeightPreferenceKey.self, value: proxy.size.height)
                                            .preference(key: BackgroundIllustrationBottomPreferenceKey.self, value: proxy.frame(in: .global).maxY)
                                    }
                                )
                                .offset(y: calculateImageOffset())
                                #if os(iOS)
                                .animation(.easeInOut(duration: 0.3), value: keyboardResponder.keyboardFrame)
                                #endif
                        }
                    )
                    .clipped()
                    .onPreferenceChange(BackgroundIllustrationHeightPreferenceKey.self) { height in
                        imageHeight = height
                    }
                    .onPreferenceChange(BackgroundIllustrationBottomPreferenceKey.self) { bottomY in
                        #if os(iOS)
                        if imageBottomY == 0 || keyboardResponder.keyboardFrame.height == 0 {
                            imageBottomY = bottomY
                        }
                        #endif
                    }

                content
            }
            .ignoresSafeArea(.keyboard)
        }

        // Calculates the vertical offset needed to adjust the background image when the keyboard appears.
        // The offset calculation works as follows:
        // 1. Get the keyboard frame in global coordinates (from KeyboardResponder)
        // 2. Use the captured natural image bottom position (imageBottomY) as stable reference
        // 3. Calculate how much to move the image so it extends 90 pixels (scaled) behind the keyboard
        private func calculateImageOffset() -> CGFloat {
            #if os(iOS)
            // If screen does not respond to keyboard notifications, return default imageOffsetY
            guard keyboardBehavior.isEnabled else { return imageOffsetY }

            // Early exit if image height hasn't been captured yet
            guard imageHeight > 0 else { return imageOffsetY }

            // Inset of the image calculated from the reference image + reference offset scaled for actual image size.
            let keyboardImageOffsetY = ContextualBackgroundStyleMetrics.referenceBackgroundImageOffset * imageHeight / ContextualBackgroundStyleMetrics.referenceBackgroundImageHeight

            // Early exit if no keyboard is visible
            guard keyboardResponder.keyboardFrame.height > 0 else { return keyboardImageOffsetY }

            // Early exit if we haven't captured the natural image position yet
            guard imageBottomY > 0 else { return imageOffsetY }

            let keyboardFrame = keyboardResponder.keyboardFrame

            // Calculate the "effective" current bottom (accounting for the image extending beyond visible area)
            // We subtract the offset because the image is taller than needed to extend behind keyboard
            let currentImageBottom = imageBottomY - keyboardImageOffsetY

            // Calculate where we want the image bottom to be (keyboard top + extension to go behind rounded corners)
            let targetImageBottom = keyboardFrame.minY + keyboardImageOffsetY

            // Calculate how much to move the image
            let offset = targetImageBottom - currentImageBottom

            return offset
            #else
            return imageOffsetY
            #endif
        }

        #if os(iOS)
        private static let maxHeightContextualAssets = MetricBuilder<CGFloat?>(default: nil).iPad(200).iPhone(landscape: 200)
        private static let maxHeightNewTabPageAssets = MetricBuilder<CGFloat?>(default: nil).iPad(290).iPhone(landscape: 290)
        #endif

        var maxHeightMetrics: CGFloat? {
            #if os(iOS)
            switch backgroundType {
            case .tryASearchCompleted, .trackers, .fireDialog, .endOfJourney:
                return Self.maxHeightContextualAssets.build(v: vSizeClass, h: hSizeClass)
            case .tryASearch, .tryVisitingASiteNTP, .endOfJourneyNTP, .endOfJourneyNTPChat, .privacyProTrial:
                return Self.maxHeightNewTabPageAssets.build(v: vSizeClass, h: hSizeClass)
            }
            #else
            return nil
            #endif
        }
    }

    struct AnimatedContextualBackgroundStyle: ViewModifier {
        let backgroundType: ContextualOnboardingBackgroundType

        func body(content: Content) -> some View {
            content
                .modifier(backgroundStyle)
                #if os(iOS)
                // Inner-shadow band painted along the panel's inside-bottom edge. Reads as the
                // web view (sitting beneath the panel in the tab's stack view) casting a shadow
                // upward onto the contextual onboarding. Merges Figma's "Inline Dax Dialog"
                // effect — two stacked INNER_SHADOW passes (Shadow/Purple offset (0,-4) blur 8,
                // and Shadow/Blue offset (0,-1) blur 0) — into a single vertical gradient,
                // since `ShadowStyle.inner(...)` is iOS 16+ and the package targets iOS 15.
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, ContextualBackgroundShadowMetrics.color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: ContextualBackgroundShadowMetrics.height)
                    .allowsHitTesting(false)
                }
                #endif
        }

        private var backgroundStyle: ContextualBackgroundStyle {
            #if os(iOS)
            ContextualBackgroundStyle(
                backgroundType: backgroundType,
                imageOffsetY: 0,
                keyboardBehavior: .ignoreKeyboard
            )
            #elseif os(macOS)
            ContextualBackgroundStyle(
                backgroundType: backgroundType,
                imageOffsetY: 0
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

private struct BackgroundIllustrationBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Contextual Onboarding + View Extension

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
    /// - Parameter backgroundType: The type of background illustration to display.
    func applyAnimatedContextualOnboardingBackground(
        backgroundType: ContextualOnboardingBackgroundType
    ) -> some View {
        self.modifier(
            OnboardingRebranding.OnboardingStyles.AnimatedContextualBackgroundStyle(
                backgroundType: backgroundType
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
