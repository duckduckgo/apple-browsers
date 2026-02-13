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

        var body: some View {
            HStack(alignment: .top, spacing: PickerMetrics.optionsSpacing) {
                PickerOption(
                    isSelected: !viewModel.isSearchAndAIChatEnabled.wrappedValue,
                    selectedImage: OnboardingRebrandingImages.SearchExperience.searchOn,
                    unselectedImage: OnboardingRebrandingImages.SearchExperience.searchOff,
                    title: UserText.settingsAIPickerSearchOnly,
                    accentColor: onboardingTheme.colorPalette.optionsListIconColor
                ) {
                    viewModel.isSearchAndAIChatEnabled.wrappedValue = false
                }

                PickerOption(
                    isSelected: viewModel.isSearchAndAIChatEnabled.wrappedValue,
                    selectedImage: OnboardingRebrandingImages.SearchExperience.searchAIOn,
                    unselectedImage: OnboardingRebrandingImages.SearchExperience.searchAIOff,
                    title: UserText.settingsAIPickerSearchAndDuckAI,
                    accentColor: onboardingTheme.colorPalette.optionsListIconColor
                ) {
                    viewModel.isSearchAndAIChatEnabled.wrappedValue = true
                }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: PickerMetrics.contentSpacing) {
                (isSelected ? selectedImage : unselectedImage)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: PickerMetrics.imageHeight)

                Text(title)
                    .font(.system(size: PickerMetrics.labelFontSize))
                    .foregroundColor(Color(UIColor.label.withAlphaComponent(0.96)))
                    .multilineTextAlignment(.center)

                RadioIndicator(isSelected: isSelected, accentColor: accentColor)
                    .frame(width: PickerMetrics.radioSize, height: PickerMetrics.radioSize)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct RadioIndicator: View {
    let isSelected: Bool
    let accentColor: Color

    var body: some View {
        if isSelected {
            ZStack {
                Circle()
                    .fill(accentColor)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        } else {
            Circle()
                .fill(Color.black.opacity(0.06))
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.3), lineWidth: 1.5)
                )
        }
    }
}

private enum PickerMetrics {
    static let optionsSpacing: CGFloat = 8
    static let contentSpacing: CGFloat = 8
    static let imageHeight: CGFloat = 72
    static let labelFontSize: CGFloat = 12
    static let radioSize: CGFloat = 24
}
