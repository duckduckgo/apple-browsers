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
                                TextAndImageMenuItemHeader("Duck.ai",
                                                           image: Image(nsImage: DesignSystemImages.Color.Size16.aiChatGradient),
                                                           bottomPadding: 0)
                                TextMenuItemCaption("Chat privately with popular 3rd-party AI models")
                            }

                            Button(model.isAIFeaturesEnabled ? "Disable Duck.ai" : "Enable Duck.ai") {
                                model.isAIFeaturesEnabled.toggle()
                            }
                            .accessibilityIdentifier("Preferences.AIChat.aiFeaturesToggle")
                        }
                    }

                    PreferencePaneSection("Visibility") {
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
                        .visibility(model.shouldShowNewTabPageToggle ? .visible : .gone)

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
                    }
                    .visibility(model.shouldShowAIFeatures ? .visible : .gone)

                    PreferencePaneSection("Open New Chats") {
                        Picker(selection: $model.openAIChatInSidebar, content: {
                            Text("In sidebar").tag(true)
                                .padding(.bottom, 4).accessibilityIdentifier("Preferences.AIChat.openNewChatsPicker.inSidebar")
                            Text("Full page").tag(false)
                                .accessibilityIdentifier("Preferences.AIChat.openNewChatsPicker.fullPage")
                        }, label: {})
                        .pickerStyle(.radioGroup)
                        .offset(x: PreferencesUI_macOS.Const.pickerHorizontalOffset)
                        .accessibilityIdentifier("Preferences.AIChat.openNewChatsPicker")
                        .onChange(of: model.openAIChatInSidebar) { _ in
                            PixelKit.fire(AIChatPixel.aiChatSidebarSettingChanged,
                                          frequency: .uniqueByName,
                                          includeAppVersionParameter: true)
                        }
                    }
                    .visibility(model.shouldShowAIFeatures && model.shouldShowOpenAIChatInSidebarToggle ? .visible : .gone)

                    Divider()
                        .padding(.bottom, 8)

                    PreferencePaneSection {
                        TextAndImageMenuItemHeader("Search Assist Settings",
                                                   image: Image(nsImage: DesignSystemImages.Color.Size16.assist),
                                                   bottomPadding: 0)

                        TextMenuItemCaption("Choose how often you want AI-assisted answers to appear in your searches")

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
                        .padding(.vertical, 8)
                    }

                    //
                } else { // Old UI
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
        }
    }
}
