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

struct SettingsAIExperimentalPickerView: View {
    @Binding var isDuckAISelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: SettingsAIExperimentalPickerViewLayout.optionsHorizontalSpacing) {
            PickerOptionView(
                isSelected: !isDuckAISelected,
                selectedImage: .searchExperimentalOn,
                unselectedImage: .searchExperimentalOff,
                title: UserText.settingsAIPickerSearchOnly
            ) {
                isDuckAISelected = false
            }

            PickerOptionView(
                isSelected: isDuckAISelected,
                selectedImage: .aiExperimentalOn,
                unselectedImage: .aiExperimentalOff,
                title: UserText.settingsAIPickerSearchAndDuckAI
            ) {
                isDuckAISelected = true
            }
        }
        .frame(height: SettingsAIExperimentalPickerViewLayout.viewHeight)
        .frame(maxWidth: SettingsAIExperimentalPickerViewLayout.maxViewWidth)
    }
}

private struct PickerOptionView: View {
    let isSelected: Bool
    let selectedImage: ImageResource
    let unselectedImage: ImageResource
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SettingsAIExperimentalPickerViewLayout.optionContentVerticalSpacing) {
                Image(isSelected ? selectedImage : unselectedImage)
                    .resizable()
                    .scaledToFit()

                Text(title)
                .daxFootnoteRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))

                CheckmarkView(isSelected: isSelected)
                    .scaledToFit()
                    .frame(height: SettingsAIExperimentalPickerViewLayout.checkmarkHeight)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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

private enum SettingsAIExperimentalPickerViewLayout {
    static let optionsHorizontalSpacing: CGFloat = 10
    static let optionContentVerticalSpacing: CGFloat = 8
    static let textStackSpacing: CGFloat = 0
    static let viewHeight: CGFloat = 152
    static let maxViewWidth: CGFloat = 380
    static let checkmarkHeight: CGFloat = 20
}
