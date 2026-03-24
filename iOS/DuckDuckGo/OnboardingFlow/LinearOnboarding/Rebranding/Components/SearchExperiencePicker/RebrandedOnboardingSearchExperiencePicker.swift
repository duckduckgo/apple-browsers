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

extension OnboardingRebranding.OnboardingView {

    struct OnboardingSearchExperiencePicker: View {
        @ObservedObject var viewModel: OnboardingSearchExperiencePickerViewModel
        @Environment(\.onboardingTheme) private var onboardingTheme
        // Keep both option titles at the same measured height so indicators align
        // whether one title wraps or both remain on a single line.
        @State private var maxOptionTitleHeight: CGFloat = 0

        var body: some View {
            HStack(alignment: .top, spacing: PickerMetrics.optionsSpacing) {
                PickerOption(
                    isSelected: !viewModel.isSearchAndAIChatEnabled.wrappedValue,
                    selectedImage: OnboardingRebrandingImages.SearchExperience.searchOn,
                    unselectedImage: OnboardingRebrandingImages.SearchExperience.searchOff,
                    title: UserText.Onboarding.SearchExperience.searchOnlyOption,
                    accentColor: onboardingTheme.colorPalette.optionsListIconColor,
                    titleMinHeight: maxOptionTitleHeight
                ) {
                    viewModel.isSearchAndAIChatEnabled.wrappedValue = false
                }

                PickerOption(
                    isSelected: viewModel.isSearchAndAIChatEnabled.wrappedValue,
                    selectedImage: OnboardingRebrandingImages.SearchExperience.searchAIOn,
                    unselectedImage: OnboardingRebrandingImages.SearchExperience.searchAIOff,
                    title: UserText.Onboarding.SearchExperience.searchAndDuckAIOption,
                    accentColor: onboardingTheme.colorPalette.optionsListIconColor,
                    titleMinHeight: maxOptionTitleHeight
                ) {
                    viewModel.isSearchAndAIChatEnabled.wrappedValue = true
                }
            }
            // Collect per-option measured title heights and apply the maximum to both.
            .onPreferenceChange(RebrandedOptionTitleHeightPreferenceKey.self) { height in
                maxOptionTitleHeight = height
            }
        }
    }

}

private struct PickerOption: View {
    let isSelected: Bool
    let selectedImage: Image
    let unselectedImage: Image
    let title: String
    let accentColor: Color
    let titleMinHeight: CGFloat
    let action: () -> Void

    @Environment(\.onboardingTheme) private var onboardingTheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: PickerMetrics.contentSpacing) {
                (isSelected ? selectedImage : unselectedImage)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: PickerMetrics.imageHeight, alignment: .top)

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
    static let imageHeight: CGFloat = 72
}

private struct RebrandedOptionTitleHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
