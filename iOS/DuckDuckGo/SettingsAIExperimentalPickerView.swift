//
//  AIExperimentalPickerView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
    // isDuckAISelected maps to AI Chat enabled state
    @Binding var isDuckAISelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Search Only (Default)
            Button {
                isDuckAISelected = false
            } label: {
                VStack(spacing: 8) {
                    Image(isDuckAISelected ? .searchExperimentalOff : .searchExperimentalOn)
                        .resizable()
                        .scaledToFit()
                    VStack(spacing: 0) {
                        Text(UserText.settingsAiExperimentalPickerSearchOnly)
                        Text(UserText.settingsAiExperimentalPickerDefault)
                    }
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                    Group {
                        if isDuckAISelected {
                            checkmarkOff
                        } else {
                            checkmarkOn
                        }
                    }
                    .scaledToFit()
                    .frame(height: 20)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                isDuckAISelected = true
            } label: {
                VStack(spacing: 8) {
                    Image(isDuckAISelected ? .aiExperimentalOn : .aiExperimentalOff)
                        .resizable()
                        .scaledToFit()
                    VStack(spacing: 0) {
                        Text(UserText.settingsAiExperimentalPickerSearchAndDuckAI)
                        Text(UserText.settingsAiExperimentalPickerExperimental)
                    }
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                    Group {
                        if isDuckAISelected {
                            checkmarkOn
                        } else {
                            checkmarkOff
                        }
                    }
                    .scaledToFit()
                    .frame(height: 20)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var checkmarkOn: some View {
        let colored = DesignSystemImages.Recolorable.Size24.check

        return Image(uiImage: colored)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(Color(designSystemColor: .accent))
    }

    private var checkmarkOff: some View {
        Image(uiImage: DesignSystemImages.Glyphs.Size24.shapeCircle)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(Color(designSystemColor: .iconsTertitary))

    }
}
