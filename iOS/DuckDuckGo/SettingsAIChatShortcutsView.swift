//
//  SettingsAIChatShortcutsView.swift
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
import Core
import PrivacyConfig

/// Visibility logic for the Duck.ai chrome shortcut surfaces.
///
/// The chrome shortcut (the Duck.ai pill in the iPad tabs bar and its matching
/// row in Settings → AI Features → Manage Duck.ai Shortcuts) is iPad-only and
/// gated behind the `aiChatChromeShortcutIPad` feature flag.
///
/// Extracted as a free type so the platform check can be exercised in tests
/// without depending on `UIDevice.current`.
enum DuckAIChromeShortcutVisibility {
    static func isSettingsRowVisible(isIPad: Bool, featureFlagger: FeatureFlagger) -> Bool {
        isIPad && featureFlagger.isFeatureOn(.aiChatChromeShortcutIPad)
    }

    /// No `isIPad` parameter — the only caller (`TabsBarViewController`) is iPad-only by construction.
    static func isChromeButtonVisible(
        featureFlagger: FeatureFlagger,
        isAIChatNavigationBarUserSettingsEnabled: Bool
    ) -> Bool {
        featureFlagger.isFeatureOn(.aiChatChromeShortcutIPad)
            && isAIChatNavigationBarUserSettingsEnabled
    }
}

struct SettingsAIChatShortcutsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            Section(UserText.aiChatSettingsBrowserShortcutsSectionTitle) {
                SettingsCellView(label: UserText.aiChatSettingsEnableBrowsingMenuToggle,
                                 accessory: .toggle(isOn: viewModel.aiChatBrowsingMenuEnabledBinding))

                SettingsCellView(label: UserText.aiChatSettingsEnableAddressBarToggle,
                                 accessory: .toggle(isOn: viewModel.aiChatAddressBarEnabledBinding))

                if shouldShowNavigationBarShortcut {
                    SettingsCellView(label: UserText.aiChatSettingsEnableNavigationBarToggle,
                                     subtitle: UserText.aiChatSettingsEnableNavigationBarSubtitle,
                                     accessory: .toggle(isOn: viewModel.aiChatNavigationBarEnabledBinding))
                }

                if viewModel.state.voiceSearchEnabled {
                    SettingsCellView(label: UserText.aiChatSettingsEnableVoiceSearchToggle,
                                     accessory: .toggle(isOn: viewModel.aiChatVoiceSearchEnabledBinding))
                }

                SettingsCellView(label: UserText.aiChatSettingsEnableTabSwitcherToggle,
                                 accessory: .toggle(isOn: viewModel.aiChatTabSwitcherEnabledBinding))
            }

            shortcutsSection
        }
        .applySettingsListModifiers(title: UserText.settingsAiChatShortcuts, displayMode: .inline, viewModel: viewModel)
    }

    @ViewBuilder
    private var shortcutsSection: some View {
        if viewModel.featureFlagger.isFeatureOn(.duckAIVoiceShortcut) {
            if #available(iOS 17.0, *) {
                Section {
                    NavigationLink {
                        DuckAIWidgetEducationView()
                    } label: {
                        Label {
                            Text(UserText.duckAISettingsAddWidget)
                        } icon: {
                            Image(uiImage: DesignSystemImages.Color.Size24.addWidget)
                                .frame(width: 24, height: 24)
                        }.daxBodyRegular()
                    }

                    if #available(iOS 18.0, *) {
                        NavigationLink {
                            ControlCenterWidgetEducationView(
                                navBarTitle: UserText.controlCenterDuckAIWidgetEducationNavBarTitle,
                                widget: .duckAIVoiceChat,
                                fourthParagraphText: UserText.controlCenterDuckAIWidgetEducationParagraph
                            )
                        } label: {
                            Label {
                                Text(UserText.duckAISettingsAddControlCenterWidget)
                            } icon: {
                                Image(uiImage: DesignSystemImages.Color.Size24.settings)
                                    .frame(width: 24, height: 24)
                            }.daxBodyRegular()
                        }
                    }

                    NavigationLink {
                        SiriEducationView(
                            title: UserText.duckAISiriEducationScreenTitle,
                            description: UserText.duckAISiriEducationScreenDescription,
                            examples: [
                                UserText.duckAISiriEducationScreenExample1,
                                UserText.duckAISiriEducationScreenExample2,
                                UserText.duckAISiriEducationScreenExample3
                            ]
                        )
                    } label: {
                        Label {
                            Text(UserText.duckAISettingsControlWithSiri)
                        } icon: {
                            Image(uiImage: DesignSystemImages.Color.Size24.askSiri)
                                .frame(width: 24, height: 24)
                        }.daxBodyRegular()
                    }
                } header: {
                    Text(UserText.duckAIShortcutsSectionHeader)
                }
                .listRowBackground(Color(designSystemColor: .surface))
            }
        }
    }

    private var shouldShowAddressBarShortcut: Bool {
        !(viewModel.featureFlagger.isFeatureOn(.iPadAIToggle) && UIDevice.current.userInterfaceIdiom == .pad)
    }

    private var shouldShowNavigationBarShortcut: Bool {
        DuckAIChromeShortcutVisibility.isSettingsRowVisible(
            isIPad: UIDevice.current.userInterfaceIdiom == .pad,
            featureFlagger: viewModel.featureFlagger
        )
    }
}

private struct DuckAIWidgetEducationView: View {

    var secondParagraphText: Text {
        if #available(iOS 18, *) {
            return Text(LocalizedStringKey(UserText.addWidgetSettingsSecondParagraph))
        } else {
            return Text("addWidget.settings.secondParagraph.\(Image(.widgetEducationAddIcon))")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(UserText.settingsAddDuckAIWidget)
                    .font(.system(size: 22, weight: .bold, design: .default))

                NumberedParagraphListView(
                    paragraphConfig: [
                        NumberedParagraphConfig(text: UserText.addWidgetSettingsFirstParagraph),
                        NumberedParagraphConfig(
                            text: secondParagraphText,
                            detail: .image(Image.homeScreen,
                                           maxWidth: 270)),
                        NumberedParagraphConfig(text: UserText.addDuckAIWidgetSettingsThirdParagraph),
                        NumberedParagraphConfig(text: UserText.addDuckAIWidgetSettingsFourthParagraph)
                    ]
                )
                .foregroundColor(Color(designSystemColor: .textPrimary))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .navigationBarTitle("")
        .background(Color(designSystemColor: .background))
    }
}
