//
//  OnboardingSearchExperiencePicker.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

#if os(iOS)
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

extension OnboardingRebranding {
    struct OnboardingSearchExperiencePicker: View {
        @ObservedObject var viewModel: OnboardingSearchExperiencePickerViewModel

        var body: some View {
            SettingsAIExperimentalPickerView(
                isDuckAISelected: viewModel.isSearchAndAIChatEnabled)
        }
    }
}

private struct SettingsAIExperimentalPickerView: View {
    @Binding var isDuckAISelected: Bool

    init(isDuckAISelected: Binding<Bool>) {
        self._isDuckAISelected = isDuckAISelected
    }

    var body: some View {
        HStack(alignment: .top, spacing: SearchExperiencePickerLayout.optionsHorizontalSpacing) {
            PickerOptionView(
                isSelected: !isDuckAISelected,
                systemImageName: "magnifyingglass",
                title: OnboardingRebranding.UserText.Onboarding.SearchExperience.searchOnlyOption
            ) {
                isDuckAISelected = false
            }

            PickerOptionView(
                isSelected: isDuckAISelected,
                systemImageName: "sparkles",
                title: OnboardingRebranding.UserText.Onboarding.SearchExperience.searchAndDuckAIOption
            ) {
                isDuckAISelected = true
            }
        }
        .frame(height: SearchExperiencePickerLayout.viewHeight)
        .frame(maxWidth: SearchExperiencePickerLayout.maxViewWidth)
    }
}

private struct PickerOptionView: View {
    let isSelected: Bool
    let systemImageName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SearchExperiencePickerLayout.optionContentVerticalSpacing) {
                Image(systemName: systemImageName)
                    .font(.system(size: SearchExperiencePickerLayout.imageSize, weight: .semibold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Text(title)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                CheckmarkView(isSelected: isSelected)
                    .scaledToFit()
                    .frame(height: SearchExperiencePickerLayout.checkmarkHeight)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct CheckmarkView: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            Image(uiImage: DesignSystemImages.Recolorable.Size24.check)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Color(designSystemColor: .accent))
        } else {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.shapeCircle)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Color(designSystemColor: .iconsTertiary))
        }
    }
}

private enum SearchExperiencePickerLayout {
    static let optionsHorizontalSpacing: CGFloat = 10
    static let optionContentVerticalSpacing: CGFloat = 8
    static let viewHeight: CGFloat = 152
    static let maxViewWidth: CGFloat = 380
    static let checkmarkHeight: CGFloat = 20
    static let imageSize: CGFloat = 36
}
#endif
