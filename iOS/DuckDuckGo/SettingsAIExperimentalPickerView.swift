//
//  SettingsAIExperimentalPickerView.swift
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

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import UIComponents
import Core

struct SettingsAIExperimentalPickerView: View {
    @Binding var isDuckAISelected: Bool
    // Keep both option titles at the same measured height so indicators align
    // whether one title wraps or both remain on a single line.
    @State private var maxOptionTitleHeight: CGFloat = 0

    init(isDuckAISelected: Binding<Bool>) {
        self._isDuckAISelected = isDuckAISelected
    }

    var body: some View {
        HStack(alignment: .top, spacing: SettingsAIExperimentalPickerViewLayout.optionsHorizontalSpacing) {
            PickerOptionView(
                isSelected: !isDuckAISelected,
                selectedImage: shouldUseIPadAssets ? .iPadSettingsSearchWithoutAIActive : .searchExperimentalOn,
                unselectedImage: shouldUseIPadAssets ? .iPadSettingsSearchWithoutAI : .searchExperimentalOff,
                title: UserText.Onboarding.SearchExperience.searchOnlyOption,
                showNewBadge: false,
                titleMinHeight: maxOptionTitleHeight
            ) {
                isDuckAISelected = false
            }
            .frame(maxWidth: .infinity, alignment: .top)

            PickerOptionView(
                isSelected: isDuckAISelected,
                selectedImage: shouldUseIPadAssets ? .iPadSettingsSearchWithAIActive : .aiExperimentalOn,
                unselectedImage: shouldUseIPadAssets ? .iPadSettingsSearchWithAI : .aiExperimentalOff,
                title: UserText.Onboarding.SearchExperience.searchAndDuckAIOption,
                showNewBadge: false,
                titleMinHeight: maxOptionTitleHeight
            ) {
                isDuckAISelected = true
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        // Collect per-option measured title heights and apply the maximum to both.
        .onPreferenceChange(OptionTitleHeightPreferenceKey.self) { height in
            maxOptionTitleHeight = height
        }
        .frame(height: SettingsAIExperimentalPickerViewLayout.viewHeight)
        .frame(maxWidth: SettingsAIExperimentalPickerViewLayout.maxViewWidth)
    }

    private var shouldUseIPadAssets: Bool {
        isIPadAIToggleOn && UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isIPadAIToggleOn: Bool {
        AppDependencyProvider.shared.featureFlagger.isFeatureOn(.iPadAIToggle)
    }
}

private struct PickerOptionView: View {
    let isSelected: Bool
    let selectedImage: ImageResource
    let unselectedImage: ImageResource
    let title: String
    let showNewBadge: Bool
    let titleMinHeight: CGFloat
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: SettingsAIExperimentalPickerViewLayout.optionContentVerticalSpacing) {
                Image(isSelected ? selectedImage : unselectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: shouldUseVerticalLayout ? SettingsAIExperimentalPickerViewLayout.imageHeight : nil, alignment: .top)

                textAndBadgeView
                    // Equalize title block height between the two options.
                    .frame(minHeight: titleMinHeight, alignment: .top)

                CheckmarkView(isSelected: isSelected)
                    .scaledToFit()
                    .frame(height: SettingsAIExperimentalPickerViewLayout.checkmarkHeight)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var textAndBadgeView: some View {
        if shouldUseVerticalLayout {
            measuredTitleBlock {
                VStack(spacing: 4) {
                    Text(title)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if showNewBadge {
                        BadgeView(text: UserText.settingsItemNewBadge)
                    }
                }
            }
        } else {
            measuredTitleBlock {
                HStack(spacing: 6) {
                    Text(title)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    if showNewBadge {
                        BadgeView(text: UserText.settingsItemNewBadge)
                    }
                }
            }
        }
    }

    private func measuredTitleBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                GeometryReader { geometry in
                    // Report measured title block height to parent for equalization.
                    Color.clear.preference(
                        key: OptionTitleHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
    }

    private var shouldUseVerticalLayout: Bool {
        dynamicTypeSize.isAccessibilitySize || dynamicTypeSize > .large
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

private struct OptionTitleHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum SettingsAIExperimentalPickerViewLayout {
    static let optionsHorizontalSpacing: CGFloat = 10
    static let optionContentVerticalSpacing: CGFloat = 8
    static let textStackSpacing: CGFloat = 0
    static let viewHeight: CGFloat = 152
    static let maxViewWidth: CGFloat = 380
    static let checkmarkHeight: CGFloat = 20
    static let imageHeight: CGFloat = 88
}
