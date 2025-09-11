//
//  PreferencesAIChat.swift
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

import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions
import PixelKit
import DesignResourcesKitIcons

extension Preferences {

    struct AIChatView: View {
        @ObservedObject var model: AIChatPreferences
        @State private var isShowingDisableAIChatDialog = false

        var body: some View {
            PreferencePane {
                TextMenuTitle(UserText.aiFeatures)
                PreferencePaneSubSection {
                    VStack(alignment: .leading, spacing: 1) {
                        TextMenuItemCaption(UserText.aiChatPreferencesCaption)
                        TextButton(UserText.aiChatPreferencesLearnMoreButton) {
                            model.openLearnMoreLink()
                        }
                    }
                }

                if model.shouldShowAIFeaturesToggle {
                    // New UI
                    Divider()
                        .padding(.vertical, 8)

                    PreferencePaneSection {
                        HStack {
                            VStack(alignment: .leading) {
                                TextAndImageMenuItemHeader(UserText.aiChatTitle,
                                                           image: Image(nsImage: DesignSystemImages.Color.Size16.aiChatGradient),
                                                           bottomPadding: 2)
                                TextMenuItemCaption(UserText.aiChatDescription)
                            }

                            Button(model.isAIFeaturesEnabled ? UserText.aiChatDisableButton : UserText.aiChatEnableButton) {
                                if model.isAIFeaturesEnabled {
                                    isShowingDisableAIChatDialog = true
                                } else {
                                    model.isAIFeaturesEnabled = true
                                    PixelKit.fire(AIChatPixel.aiChatSettingsGlobalToggleTurnedOn,
                                                  frequency: .dailyAndCount,
                                                  includeAppVersionParameter: true)
                                }
                            }
                            .accessibilityIdentifier("Preferences.AIChat.aiFeaturesToggle")
                        }
                    }

                    PreferencePaneSection(UserText.aiChatShortcutsSectionTitle,
                                          spacing: 6) {
                        ToggleMenuItem(UserText.aiChatShowInSearchBoxOnNewTabPageBarToggle,
                                       isOn: $model.showShortcutOnNewTabPage)
                        .accessibilityIdentifier("Preferences.AIChat.showOnNewTabPageToggle")
                        .onChange(of: model.showShortcutOnNewTabPage) { newValue in
                            if newValue {
                                PixelKit.fire(AIChatPixel.aiChatSettingsNewTabPageShortcutTurnedOn,
                                              frequency: .dailyAndCount,
                                              includeAppVersionParameter: true)
                            } else {
                                PixelKit.fire(AIChatPixel.aiChatSettingsNewTabPageShortcutTurnedOff,
                                              frequency: .dailyAndCount,
                                              includeAppVersionParameter: true)
                            }
                        }
                        .visibility(model.shouldShowNewTabPageToggle ? .visible : .gone)

                        ToggleMenuItem(UserText.aiChatShowInBrowserMenusToggle,
                                       isOn: $model.showShortcutInApplicationMenu)
                        .accessibilityIdentifier("Preferences.AIChat.showInApplicationMenuToggle")
                        .onChange(of: model.showShortcutInApplicationMenu) { newValue in
                            if newValue {
                                PixelKit.fire(AIChatPixel.aiChatSettingsApplicationMenuShortcutTurnedOn,
                                              frequency: .dailyAndCount,
                                              includeAppVersionParameter: true)
                            } else {
                                PixelKit.fire(AIChatPixel.aiChatSettingsApplicationMenuShortcutTurnedOff,
                                              frequency: .dailyAndCount,
                                              includeAppVersionParameter: true)
                            }
                        }

                        ToggleMenuItem(UserText.aiChatShowInAddressBarLabel,
                                       isOn: $model.showShortcutInAddressBar)
                        .accessibilityIdentifier("Preferences.AIChat.showInAddressBarToggle")
                        .onChange(of: model.showShortcutInAddressBar) { newValue in
                            if newValue {
                                PixelKit.fire(AIChatPixel.aiChatSettingsAddressBarShortcutTurnedOn,
                                              frequency: .dailyAndCount,
                                              includeAppVersionParameter: true)
                            } else {
                                PixelKit.fire(AIChatPixel.aiChatSettingsAddressBarShortcutTurnedOff,
                                              frequency: .dailyAndCount,
                                              includeAppVersionParameter: true)
                            }
                        }

                        if model.shouldShowOpenAIChatInSidebarToggle {
                            ToggleMenuItem(UserText.aiChatOpenInSidebarToggle,
                                           isOn: $model.openAIChatInSidebar)
                            .accessibilityIdentifier("Preferences.AIChat.openInSidebarToggle")
                            .onChange(of: model.openAIChatInSidebar) { _ in
                                PixelKit.fire(AIChatPixel.aiChatSidebarSettingChanged,
                                              frequency: .uniqueByName,
                                              includeAppVersionParameter: true)
                            }
                            .disabled(!model.showShortcutInAddressBar)
                            .padding(.leading, 19)

                            if model.shouldShowPageContextToggle {
                                ToggleMenuItem("Automatically send page context to the sidebar",
                                               isOn: $model.shouldAutomaticallySendPageContext)
                                .accessibilityIdentifier("Preferences.AIChat.shouldAutomaticallySendPageContextToggle")
                                .disabled(!model.showShortcutInAddressBar || !model.openAIChatInSidebar)
                                .padding(.leading, 19)
                            }
                        }
                    }
                    .visibility(model.shouldShowAIFeatures ? .visible : .gone)

                    Divider()
                        .padding(.bottom, 8)

                    PreferencePaneSection {
                        VStack(alignment: .leading) {
                            TextAndImageMenuItemHeader(UserText.searchAssistSettings,
                                                       image: Image(nsImage: DesignSystemImages.Color.Size16.assist),
                                                       bottomPadding: 2)

                            TextMenuItemCaption(UserText.searchAssistSettingsDescription)
                                .padding(.bottom, 6)
                            Button {
                                model.openSearchAssistSettings()
                            } label: {
                                HStack {
                                    Text(UserText.searchAssistSettingsLink)
                                    Image(.externalAppScheme)
                                }
                                .foregroundColor(Color.linkBlue)
                                .cursor(.pointingHand)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else { // Legacy UI displayed when aiChatGlobalSwitch is disabled (to be removed after rollout)
                    // Duck.ai Shortcuts
                    PreferencePaneSection(UserText.duckAIShortcuts) {

                        if model.shouldShowNewTabPageToggle {
                            ToggleMenuItem(UserText.aiChatShowOnNewTabPageBarToggle,
                                           isOn: $model.showShortcutOnNewTabPage)
                            .accessibilityIdentifier("Preferences.AIChat.showOnNewTabPageToggle")
                            .onChange(of: model.showShortcutOnNewTabPage) { newValue in
                                if newValue {
                                    PixelKit.fire(AIChatPixel.aiChatSettingsNewTabPageShortcutTurnedOn,
                                                  frequency: .dailyAndCount,
                                                  includeAppVersionParameter: true)
                                } else {
                                    PixelKit.fire(AIChatPixel.aiChatSettingsNewTabPageShortcutTurnedOff,
                                                  frequency: .dailyAndCount,
                                                  includeAppVersionParameter: true)
                                }
                            }
                        }

                        ToggleMenuItem(UserText.aiChatShowInAddressBarToggle,
                                       isOn: $model.showShortcutInAddressBar)
                        .accessibilityIdentifier("Preferences.AIChat.showInAddressBarToggle")
                        .onChange(of: model.showShortcutInAddressBar) { newValue in
                            if newValue {
                                PixelKit.fire(AIChatPixel.aiChatSettingsAddressBarShortcutTurnedOn,
                                              frequency: .dailyAndCount,
                                              includeAppVersionParameter: true)
                            } else {
                                PixelKit.fire(AIChatPixel.aiChatSettingsAddressBarShortcutTurnedOff,
                                              frequency: .dailyAndCount,
                                              includeAppVersionParameter: true)
                            }
                        }

                        ToggleMenuItem(UserText.aiChatShowInApplicationMenuToggle,
                                       isOn: $model.showShortcutInApplicationMenu)
                        .accessibilityIdentifier("Preferences.AIChat.showInApplicationMenuToggle")
                        .onChange(of: model.showShortcutInApplicationMenu) { newValue in
                            if newValue {
                                PixelKit.fire(AIChatPixel.aiChatSettingsApplicationMenuShortcutTurnedOn,
                                              frequency: .dailyAndCount,
                                              includeAppVersionParameter: true)
                            } else {
                                PixelKit.fire(AIChatPixel.aiChatSettingsApplicationMenuShortcutTurnedOff,
                                              frequency: .dailyAndCount,
                                              includeAppVersionParameter: true)
                            }
                        }

                        if model.shouldShowOpenAIChatInSidebarToggle {
                            ToggleMenuItem(UserText.aiChatOpenInSidebarToggle,
                                           isOn: $model.openAIChatInSidebar)
                            .accessibilityIdentifier("Preferences.AIChat.openInSidebarToggle")
                            .onChange(of: model.openAIChatInSidebar) { _ in
                                PixelKit.fire(AIChatPixel.aiChatSidebarSettingChanged,
                                              frequency: .uniqueByName,
                                              includeAppVersionParameter: true)
                            }

                            if model.shouldShowPageContextToggle {
                                ToggleMenuItem("Automatically send page context to the sidebar",
                                               isOn: $model.shouldAutomaticallySendPageContext)
                                .accessibilityIdentifier("Preferences.AIChat.shouldAutomaticallySendPageContextToggle")
                            }
                        }
                    }
                    .visibility(model.shouldShowAIFeatures ? .visible : .gone)

                    // Search Assist Settings
                    PreferencePaneSection(UserText.searchAssistSettings) {
                        TextMenuItemCaption(UserText.searchAssistSettingsDescription)
                            .padding(.top, -6)
                            .padding(.bottom, 6)
                        Button {
                            model.openSearchAssistSettings()
                        } label: {
                            HStack {
                                Text(UserText.searchAssistSettingsLink)
                                Image(.externalAppScheme)
                            }
                            .foregroundColor(Color.linkBlue)
                            .cursor(.pointingHand)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sheet(isPresented: $isShowingDisableAIChatDialog) {
                removeConfirmationDialog
            }
        }

        @ViewBuilder
        private var removeConfirmationDialog: some View {
            Dialog {
                Image("DaxAIChat")
                    .frame(width: 96, height: 72)

                Text(UserText.aiChatDisableDialogTitle)
                    .font(.title2)
                    .bold()
                    .foregroundColor(Color(.textPrimary))

                Text(UserText.aiChatDisableDialogMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixMultilineScrollableText()
                .foregroundColor(Color(.textPrimary))
            } buttons: {
                Spacer()
                Button(UserText.cancel) { isShowingDisableAIChatDialog = false }
                Button(action: {
                    isShowingDisableAIChatDialog = false
                    model.isAIFeaturesEnabled = false
                    PixelKit.fire(AIChatPixel.aiChatSettingsGlobalToggleTurnedOff,
                                  frequency: .dailyAndCount,
                                  includeAppVersionParameter: true)
                }, label: {
                    Text(UserText.aiChatDisableDialogConfirmButton)
                })
                .buttonStyle(DefaultActionButtonStyle(enabled: true))
            }
            .frame(width: 360)
        }
    }
}
