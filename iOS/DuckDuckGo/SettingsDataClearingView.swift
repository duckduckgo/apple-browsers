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
import DuckUI

private struct ClearButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {}
}

struct SettingsDataClearingView: View {

    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @ObservedObject private var viewModel: DataClearingSettingsViewModel
    @State private var clearButtonFrame: CGRect = .zero
    
    init(viewModel: DataClearingSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        List {
            // Header section
            if viewModel.newUIEnabled {
                Section {
                    DataClearingHeaderView()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                // Fire Button Animation
                SettingsPickerCellView(label: UserText.settingsFirebutton,
                                       options: FireButtonAnimationType.allCases,
                                        selectedOption: viewModel.fireButtonAnimationBinding)
            }
            
            if viewModel.showAIChatsToggle && viewModel.newUIEnabled {
                aiChatsToggleSection
            }

            Section {
                // Fireproof Sites
                SettingsCellView(label: viewModel.fireproofedSitesTitle,
                                 subtitle: viewModel.fireproofedSitesSubtitle,
                                 action: { viewModel.openFireproofSites() },
                                 disclosureIndicator: true,
                                 isButton: true)

                // Automatically Clear Data
                SettingsCellView(label: viewModel.autoClearTitle,
                                 action: { viewModel.openAutoClearData() },
                                 accessory: .rightDetail(viewModel.autoClearAccessibilityLabel),
                                  disclosureIndicator: true,
                                  isButton: true)
            }

            if viewModel.showAIChatsToggle && !viewModel.newUIEnabled {
                aiChatsToggleSection
            }
                
            Section {
                SettingsCellView(action: {
                    viewModel.presentFireConfirmation(from: clearButtonFrame)
                }, customView: {
                    forgetAllButtonContent
                }, isButton: true)
                .background(
                    GeometryReader { geometryProxy in
                        Color.clear
                            .preference(key: ClearButtonFrameKey.self, value: geometryProxy.frame(in: .global))
                    }
                )
                .onPreferenceChange(ClearButtonFrameKey.self) { newFrame in
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        self.clearButtonFrame = newFrame
                    }
                }
                .accessibilityIdentifier("Settings.DataClearing.Button.ForgetAll")
            } footer: {
                if !viewModel.newUIEnabled {
                    Text(viewModel.footnoteText)
                }
            }
        }
        .applySettingsListModifiers(title: UserText.dataClearing,
                                    displayMode: .inline,
                                    viewModel: settingsViewModel)
        .background(Color(designSystemColor: .background))
        .modifier(ScrollBounceBehaviorModifier())
        .onAppear {
            viewModel.refreshFireproofedSitesCount()
        }
        .onFirstAppear {
            Pixel.fire(pixel: .settingsDataClearingOpen)
        }
    }

    private var forgetAllButtonContent: AnyView {
        AnyView(
            HStack(alignment: .center) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.fireSolid)
                    .tintIfAvailable(Color(designSystemColor: .icons))
                Text(viewModel.clearDataButtonTitle)
                    .foregroundStyle(Color(designSystemColor: .accent))
                Spacer()
            }
        )
    }
    
    private var aiChatsToggleSection: some View {
        Section {
            SettingsCellView(label: viewModel.aiChatsToggleTitle,
                             accessory: .toggle(isOn: settingsViewModel.autoClearAIChatHistoryBinding))
        } footer: {
            Text(UserText.settingsClearAIChatHistoryFooter)
        }
    }
}

private struct DataClearingHeaderView: View {
    var body: some View {
        VStack(spacing: Constants.outerStackSpacing) {
            VStack(spacing: Constants.innerStackSpacing) {
                // Fire illustration
                Image(uiImage: DesignSystemImages.Color.Size128.fire)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.iconSize.width, height: Constants.iconSize.height)
                
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
        static let iconSize: CGSize = .init(width: 128, height: 96)
        static let padding: EdgeInsets = .init(top: 0, leading: 16, bottom: 8, trailing: 16)
    }
}
