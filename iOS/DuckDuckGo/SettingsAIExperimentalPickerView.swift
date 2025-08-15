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
        HStack(alignment: .top, spacing: 16) {
            PickerOptionView(
                isSelected: !isDuckAISelected,
                selectedImage: .searchExperimentalOn,
                unselectedImage: .searchExperimentalOff,
                title: UserText.settingsAiExperimentalPickerSearchOnly,
                subtitle: UserText.settingsAiExperimentalPickerDefault
            ) {
                isDuckAISelected = false
            }

            PickerOptionView(
                isSelected: isDuckAISelected,
                selectedImage: .aiExperimentalOn,
                unselectedImage: .aiExperimentalOff,
                title: UserText.settingsAiExperimentalPickerSearchAndDuckAI,
                subtitle: UserText.settingsAiExperimentalPickerExperimental
            ) {
                isDuckAISelected = true
            }
        }
    }
}

private struct PickerOptionView: View {
    let isSelected: Bool
    let selectedImage: ImageResource
    let unselectedImage: ImageResource
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(isSelected ? selectedImage : unselectedImage)
                    .resizable()
                    .scaledToFit()

                VStack(spacing: 0) {
                    Text(title)
                    Text(subtitle)
                }
                .daxFootnoteRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))

                CheckmarkView(isSelected: isSelected)
                    .scaledToFit()
                    .frame(height: 20)
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
