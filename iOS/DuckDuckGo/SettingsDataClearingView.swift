//
//  SettingsDataClearingView.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import Core
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

struct SettingsDataClearingView: View {

    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var isShowingBurnAlert: Bool = false

    var body: some View {
        List {
            Section {
                // Fire Button Animation
                SettingsPickerCellView(useImprovedPicker: viewModel.useImprovedPicker,
                                       label: UserText.settingsFirebutton,
                                       options: FireButtonAnimationType.allCases,
                                       selectedOption: viewModel.fireButtonAnimationBinding)
            }

            Section {
                // Fireproof Sites
                SettingsCellView(label: UserText.settingsFireproofSites,
                                  action: { viewModel.presentLegacyView(.fireproofSites) },
                                 disclosureIndicator: true,
                                 isButton: true)

                // Automatically Clear Data
                SettingsCellView(label: UserText.settingsClearData,
                                  action: { viewModel.presentLegacyView(.autoclearData) },
                                  accessory: .rightDetail(viewModel.state.autoclearDataEnabled
                                                         ? UserText.autoClearAccessoryOn
                                                         : UserText.autoClearAccessoryOff),
                                  disclosureIndicator: true,
                                  isButton: true)
            }

            if viewModel.isAIChatEnabled && viewModel.isDuckAiDataClearingEnabled {
                Section {
                    SettingsCellView(label: UserText.settingsClearAIChatHistory,
                                     accessory: .toggle(isOn: viewModel.autoClearAIChatHistoryBinding))
                } footer: {
                    Text(UserText.settingsClearAIChatHistoryFooter)
                }
            }
            
            if viewModel.isForgetAllInSettingsEnabled {
                Section(footer: Text(footnoteText)) {
                    SettingsCellView(action: {
                        Pixel.fire(pixel: .forgetAllPressedSettings)
                        isShowingBurnAlert = true
                    }, customView: {
                        AnyView(
                            HStack(alignment: .center) {
                                Image(uiImage: DesignSystemImages.Glyphs.Size24.fireSolid)
                                    .tintIfAvailable(Color(designSystemColor: .icons))
                                Text(forgetAllTitle)
                                    .foregroundStyle(Color(designSystemColor: .accent))
                                Spacer()
                            }
                        )
                    }, isButton: true)
                    .accessibilityIdentifier("Settings.DataClearing.Button.ForgetAll")
                    .forgetDataConfirmationDialog(isPresented: $isShowingBurnAlert,
                                                  onConfirm: viewModel.forgetAll)
                }
            }
        }
        .applySettingsListModifiers(title: UserText.dataClearing,
                                    displayMode: .inline,
                                    viewModel: viewModel)
        .onFirstAppear {
            Pixel.fire(pixel: .settingsDataClearingOpen)
        }
    }

    private var forgetAllTitle: String {
        let shouldIncludeAIChat = viewModel.appSettings.autoClearAIChatHistory

        return shouldIncludeAIChat ? UserText.actionForgetAllWithAIChat : UserText.actionForgetAll
    }

    private var footnoteText: String {
        let shouldIncludeAIChat = viewModel.appSettings.autoClearAIChatHistory

        return shouldIncludeAIChat ? UserText.settingsDataClearingForgetAllWithAiChatFootnote : UserText.settingsDataClearingForgetAllFootnote
    }
}
