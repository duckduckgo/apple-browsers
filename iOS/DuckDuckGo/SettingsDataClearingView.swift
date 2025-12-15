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

    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @ObservedObject var viewModel: DataClearingSettingsViewModel
    @State private var isShowingBurnAlert: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header section
            if viewModel.newUIEnabled {
                DataClearingHeaderView()
            }
            
            List {
                Section {
                    // Fire Button Animation
                    SettingsPickerCellView(useImprovedPicker: settingsViewModel.useImprovedPicker,
                                           label: UserText.settingsFirebutton,
                                           options: FireButtonAnimationType.allCases,
                                           selectedOption: settingsViewModel.fireButtonAnimationBinding)
                }

                Section {
                    // Fireproof Sites
                    SettingsCellView(label: UserText.settingsFireproofSites,
                                      action: { settingsViewModel.presentLegacyView(.fireproofSites) },
                                     disclosureIndicator: true,
                                     isButton: true)

                    // Automatically Clear Data
                    SettingsCellView(label: UserText.settingsClearData,
                                      action: { settingsViewModel.presentLegacyView(.autoclearData) },
                                      accessory: .rightDetail(settingsViewModel.state.autoclearDataEnabled
                                                             ? UserText.autoClearAccessoryOn
                                                             : UserText.autoClearAccessoryOff),
                                      disclosureIndicator: true,
                                      isButton: true)
                }

                if settingsViewModel.isAIChatEnabled && settingsViewModel.isDuckAiDataClearingEnabled {
                    Section {
                        SettingsCellView(label: UserText.settingsClearAIChatHistory,
                                         accessory: .toggle(isOn: settingsViewModel.autoClearAIChatHistoryBinding))
                    } footer: {
                        Text(UserText.settingsClearAIChatHistoryFooter)
                    }
                }
                
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
                                                  onConfirm: settingsViewModel.forgetAll)
                }
            }
            .applySettingsListModifiers(title: UserText.dataClearing,
                                        displayMode: .inline,
                                        viewModel: settingsViewModel)
        }
        .background(Color(designSystemColor: .background))
        .onFirstAppear {
            Pixel.fire(pixel: .settingsDataClearingOpen)
        }
    }

    private var forgetAllTitle: String {
        let shouldIncludeAIChat = settingsViewModel.appSettings.autoClearAIChatHistory

        return shouldIncludeAIChat ? UserText.actionForgetAllWithAIChat : UserText.actionForgetAll
    }

    private var footnoteText: String {
        let shouldIncludeAIChat = settingsViewModel.appSettings.autoClearAIChatHistory

        return shouldIncludeAIChat ? UserText.settingsDataClearingForgetAllWithAiChatFootnote : UserText.settingsDataClearingForgetAllFootnote
    }
}

private struct DataClearingHeaderView: View {
    var body: some View {
        VStack(spacing: Constants.outerStackSpacing) {
            VStack(spacing: Constants.innerStackSpacing) {
                // Fire illustration
                Image(uiImage: DesignSystemImages.Color.Size72.fire)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                
                // Title
                Text(UserText.dataClearing)
                    .daxTitle2()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
            }
            
            // Description
            Text(UserText.settingsDataClearingDescription)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Constants.padding)
        .frame(maxWidth: .infinity)
        .background(.clear)
    }
    
    enum Constants {
        static let outerStackSpacing: CGFloat = 12
        static let innerStackSpacing: CGFloat = 8
        static let iconSize: CGFloat = 64
        static let padding: EdgeInsets = .init(top: 32, leading: 32, bottom: 8, trailing: 32)
    }
}
