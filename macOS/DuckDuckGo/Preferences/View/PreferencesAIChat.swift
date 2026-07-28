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
import SERPSettings

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

                Divider()
                    .padding(.vertical, 8)

                PreferencePaneSection {
                    HStack {
                        VStack(alignment: .leading) {
                            TextAndImageMenuItemHeader(UserText.aiChatTitle,
                                                       image: Image(nsImage: DesignSystemImages.Color.Size16.duckAI),
                                                       bottomPadding: 2)
                            TextMenuItemCaption(UserText.aiChatDescription)

                            if model.shouldShowDuckAiSettingsLink {
                                Button {
                                    model.openDuckAiSettings()
                                } label: {
                                    HStack {
                                        Text(UserText.duckAiSettingsLink)
                                        Image(.externalAppScheme)
                                    }
                                    .rebrandableLinkForeground()
                                    .cursor(.pointingHand)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 6)
                                .accessibilityIdentifier("Preferences.AIChat.duckAiSettingsLink")
                                .visibility(model.shouldShowAIFeatures ? .visible : .gone)
                            }
                        }

                        // Redesign: Duck.ai is an On/Off dropdown grouped with the pickers below.
                        Spacer()
                        Picker("", selection: model.duckAIEnabledBinding) {
                            Text(UserText.aiChatEnabledOn).tag(true)
                            Text(UserText.aiChatEnabledOff).tag(false)
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityIdentifier("Preferences.AIChat.aiFeaturesToggle")
                    }
                }

                // Native Search Assist / Hide AI Images controls, grouped with Duck.ai at the top.
                PreferencePaneSection {
                    HStack {
                        VStack(alignment: .leading) {
                            TextAndImageMenuItemHeader(UserText.searchAssistSettings,
                                                       image: Image(nsImage: DesignSystemImages.Color.Size16.assist),
                                                       bottomPadding: 2)
                            TextMenuItemCaption(UserText.searchAssistSettingsDescription)
                        }
                        Spacer()
                        Picker("", selection: model.searchAssistFrequencyBinding) {
                            ForEach(SearchAssistFrequency.allCases, id: \.self) { frequency in
                                Text(frequency.displayName).tag(frequency)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityIdentifier("Preferences.AIChat.searchAssistPicker")
                    }
                }

                PreferencePaneSection {
                    HStack {
                        VStack(alignment: .leading) {
                            TextAndImageMenuItemHeader(UserText.hideAIGeneratedImagesSettings,
                                                       image: Image(nsImage: DesignSystemImages.Color.Size16.hideAIGeneratedImages),
                                                       bottomPadding: 2)
                            TextMenuItemCaption(UserText.hideAIGeneratedImagesSettingsDescription)
                            TextButton(UserText.learnMore) {
                                model.openHideAIGeneratedImagesLearnMore()
                            }
                        }
                        Spacer()
                        Picker("", selection: model.hideAIImagesBinding) {
                            ForEach(HideAIImagesOption.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityIdentifier("Preferences.AIChat.hideAIGeneratedImagesPicker")
                    }
                }

                PreferencePaneSection(UserText.aiChatShortcutsSectionTitle,
                                      spacing: 6) {

                    ToggleMenuItem(UserText.aiChatShowOnNewTabPageSearchBoxToggle,
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

                    ToggleMenuItem(UserText.aiChatShowSearchAndDuckAIToggleLabel,
                                   isOn: $model.showSearchAndDuckAIToggle)
                    .accessibilityIdentifier("Preferences.AIChat.showSearchAndDuckAIToggleToggle")

                    if model.shouldShowTabBarButtonVisibilityOptions {
                        ToggleMenuItem(UserText.aiChatShowDuckAIButtonInTabBarLabel,
                                       isOn: $model.showDuckAIButtonInTabBar)
                        .accessibilityIdentifier("Preferences.AIChat.showDuckAIButtonInTabBarToggle")

                        ToggleMenuItem(UserText.aiChatShowSidebarButtonInTabBarLabel,
                                       isOn: $model.showSidebarButtonInTabBar)
                        .accessibilityIdentifier("Preferences.AIChat.showSidebarButtonInTabBarToggle")
                    } else {
                        ToggleMenuItem(UserText.aiChatShowShortcutInAddressBarLabel,
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

                        ToggleMenuItem(UserText.aiChatOpenSidebarWhenViewingWebsitesToggle,
                                       isOn: $model.openAIChatInSidebar)
                        .accessibilityIdentifier("Preferences.AIChat.openInSidebarToggle")
                        .onChange(of: model.openAIChatInSidebar) { _ in
                            PixelKit.fire(AIChatPixel.aiChatSidebarSettingChanged,
                                          frequency: .uniqueByName,
                                          includeAppVersionParameter: true)
                        }
                        .disabled(!model.showShortcutInAddressBar)
                        .padding(.leading, 19)
                    }

                    if model.shouldShowPageContextToggle {
                        ToggleMenuItem(UserText.aiChatAutomaticallySendPageContentToggle,
                                       isOn: $model.shouldAutomaticallySendPageContext)
                        .accessibilityIdentifier("Preferences.AIChat.shouldAutomaticallySendPageContextToggle")
                        .disabled(model.isPageContextToggleDisabled)
                        .padding(.leading, 19)
                    }

                    if model.shouldShowPromptBarPreferences {
                        PromptBarPreferencesView(preferences: model.promptBarPreferences)
                    }
                }
                                      .visibility(model.shouldShowAIFeatures ? .visible : .gone)

                // Always shown: the button disables all AI while any is on, then greys out
                // once everything is disabled, with the caption reinforcing the no-AI state.
                Divider()
                    .padding(.bottom, 8)

                PreferencePaneSection {
                    VStack(alignment: .leading) {
                        Button(UserText.aiFeaturesDisableAllButton) {
                            model.disableAllAI()
                        }
                        .disabled(model.isAllAIDisabled)
                        .accessibilityIdentifier("Preferences.AIChat.disableAllAIButton")
                        TextMenuItemCaption(model.isAllAIDisabled ? UserText.aiFeaturesDisableAllFooterDisabled : UserText.aiFeaturesDisableAllFooter)
                    }
                }
            }
        }
    }
}

extension SearchAssistFrequency {
    var displayName: String {
        switch self {
        case .never: return UserText.searchAssistNever
        case .onDemand: return UserText.searchAssistOnDemand
        case .sometimes: return UserText.searchAssistSometimes
        case .often: return UserText.searchAssistOften
        }
    }
}

// On/Off picker option for Hide AI-Generated Images (`on` = hidden).
enum HideAIImagesOption: String, CaseIterable, Hashable {
    case on
    case off

    init(hidden: Bool) {
        self = hidden ? .on : .off
    }

    var hidden: Bool {
        self == .on
    }

    var displayName: String {
        switch self {
        case .on: return UserText.hideAIGeneratedImagesOn
        case .off: return UserText.hideAIGeneratedImagesOff
        }
    }
}
