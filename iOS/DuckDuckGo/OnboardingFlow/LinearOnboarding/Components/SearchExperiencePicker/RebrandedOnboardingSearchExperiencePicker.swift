//
//  RebrandedOnboardingSearchExperiencePicker.swift
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
import Onboarding

extension OnboardingView {

    struct OnboardingSearchExperiencePicker: View {
        @Binding var isDuckAISelected: Bool
        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        // Keep both option titles at the same measured height so indicators align
        // whether one title wraps or both remain on a single line.
        @State private var maxOptionTitleHeight: CGFloat = 0

        init(isDuckAISelected: Binding<Bool>) {
            self._isDuckAISelected = isDuckAISelected
        }

        var body: some View {
            HStack(alignment: .top, spacing: PickerMetrics.optionsSpacing) {
                PickerOption(
                    isSelected: !isDuckAISelected,
                    title: UserText.Onboarding.SearchExperience.searchOnlyOption,
                    accentColor: onboardingTheme.colorPalette.optionsListIconColor,
                    titleMinHeight: maxOptionTitleHeight,
                    action: { isDuckAISelected = false }
                ) {
                    (isDuckAISelected
                        ? OnboardingRebrandingImages.SearchExperience.searchOff
                        : OnboardingRebrandingImages.SearchExperience.searchOn)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(height: PickerMetrics.imageHeight, alignment: .top)
                }

                PickerOption(
                    isSelected: isDuckAISelected,
                    title: UserText.Onboarding.SearchExperience.searchAndDuckAIOption,
                    accentColor: onboardingTheme.colorPalette.optionsListIconColor,
                    titleMinHeight: maxOptionTitleHeight,
                    action: { isDuckAISelected = true }
                ) {
                    if reduceMotion {
                        // Static fallback when the user has requested reduced motion.
                        (isDuckAISelected
                            ? OnboardingRebrandingImages.SearchExperience.searchAIOn
                            : OnboardingRebrandingImages.SearchExperience.searchAIOff)
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(height: PickerMetrics.imageHeight, alignment: .top)
                    } else {
                        SearchExperienceToggleAnimationView(isDuckAISelected: isDuckAISelected)
                            .frame(height: PickerMetrics.imageHeight, alignment: .top)
                    }
                }
            }
            // Collect per-option measured title heights and apply the maximum to both.
            .onPreferenceChange(RebrandedOptionTitleHeightPreferenceKey.self) { height in
                maxOptionTitleHeight = height
            }
        }
    }

}

private struct PickerOption<ImageContent: View>: View {
    let isSelected: Bool
    let title: String
    let accentColor: Color
    let titleMinHeight: CGFloat
    let action: () -> Void
    let imageContent: () -> ImageContent

    init(isSelected: Bool,
         title: String,
         accentColor: Color,
         titleMinHeight: CGFloat,
         action: @escaping () -> Void,
         @ViewBuilder imageContent: @escaping () -> ImageContent) {
        self.isSelected = isSelected
        self.title = title
        self.accentColor = accentColor
        self.titleMinHeight = titleMinHeight
        self.action = action
        self.imageContent = imageContent
    }

    @Environment(\.onboardingTheme) private var onboardingTheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: PickerMetrics.contentSpacing) {
                imageContent()

                measuredTitleBlock {
                    Text(title)
                        .font(onboardingTheme.typography.small)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Equalize title block height between the two options.
                .frame(minHeight: titleMinHeight, alignment: .top)

                OnboardingRebranding.RadioIndicator(isSelected: isSelected, accentColor: accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func measuredTitleBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                GeometryReader { geometry in
                    // Report measured title block height to parent for equalization.
                    Color.clear.preference(
                        key: RebrandedOptionTitleHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
    }
}

private enum PickerMetrics {
    static let optionsSpacing: CGFloat = 8
    static let contentSpacing: CGFloat = 8
    // Animation canvas is 128×80; static images were updated to match.
    static let imageHeight: CGFloat = 80
}

private struct RebrandedOptionTitleHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
