//
//  AutoClearSettingsView.swift
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
import Core
import DuckUI

struct AutoClearSettingsView: View {
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @ObservedObject var viewModel: AutoClearSettingsViewModel
    
    var body: some View {
        List {
            autoClearToggleSection
            if viewModel.autoClearEnabled {
                clearOptionsSection
                timingSection
            }
        }
        .applySettingsListModifiers(title: UserText.settingsAutomaticallyDeleteData,
                                    displayMode: .inline,
                                    viewModel: settingsViewModel)
        .modifier(ScrollBounceBehaviorModifier())
        .onFirstAppear {
            Pixel.fire(pixel: .settingsDataClearingClearDataOpen)
        }
        .onDisappear {
            viewModel.onViewDismiss()
        }
    }
    
    // MARK: - Section 1: Auto Clear Toggle
    
    private var autoClearToggleSection: some View {
        Section {
            SettingsCellView(label: UserText.settingsAutomaticallyDeleteData,
                             accessory: .toggle(isOn: viewModel.autoClearEnabledBinding))
        } footer: {
            Text(UserText.settingsAutoClearToggleFooter)
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
    }
    
    // MARK: - Section 2: Clear Options
    
    private var clearOptionsSection: some View {
        Section {
            // Tabs
            SettingsCellView(label: UserText.settingsAutoClearTabsTitle,
                             subtitle: UserText.settingsAutoClearTabsSubtitle,
                             accessory: .toggle(isOn: viewModel.clearTabsBinding))
            
            // Cookies and Site Data
            SettingsCellView(label: UserText.settingsAutoClearCookiesTitle,
                             subtitle: UserText.settingsAutoClearCookiesSubtitle,
                             accessory: .toggle(isOn: viewModel.clearCookiesBinding))
            
            // Duck.ai Chats (only if AI Chat is enabled)
            if viewModel.showDuckAIChatsToggle {
                SettingsCellView(label: UserText.settingsAutoClearDuckAIChatsTitle,
                                 subtitle: UserText.settingsAutoClearDuckAIChatsSubtitle,
                                 accessory: .toggle(isOn: viewModel.clearDuckAIChatsBinding))
            }
        } header: {
            Text(UserText.settingsAutomaticDataClearingDeleteSectionTitle)
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
    }
    
    // MARK: - Section 3: Timing Selection
    
    private var timingSection: some View {
        Section {
            ForEach(viewModel.timingOptions, id: \.self) { timing in
                TimingOptionRow(
                    label: viewModel.timingLabel(for: timing),
                    isSelected: viewModel.selectedTiming == timing,
                    action: {
                        viewModel.selectedTimingBinding.wrappedValue = timing
                    }
                )
            }
        } header: {
            Text(UserText.settingsAutoClearTimingSectionHeader)
                .foregroundColor(Color(designSystemColor: .textSecondary))
        } footer: {
            Text(UserText.settingsAutoClearTimingFooter)
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
    }
}

// MARK: - Timing Option Row

private struct TimingOptionRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(Color(designSystemColor: .accent))
                        .accessibilityHidden(true)
                }
            }
            .padding(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color(designSystemColor: .surface))
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
