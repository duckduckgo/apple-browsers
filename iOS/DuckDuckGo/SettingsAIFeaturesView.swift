//
//  SettingsAIFeaturesView.swift
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
import Core
import DesignResourcesKitIcons
import BrowserServicesKit
import Common
import Networking

struct SettingsAIFeaturesView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        List {

            VStack(alignment: .center) {
                if viewModel.isUpdatedAIFeaturesSettingsEnabled {
                    Image(.settingAIFeaturesHero)
                        .padding(.top, -30)
                } else {
                    Image(.settingsAIChatHero)
                        .padding(.top, -20)
                }
                Text(UserText.settingsAiFeatures)
                    .daxTitle3()

                VStack(spacing: 0) {
                    Text(.init(UserText.aiFeaturesDescription))
                        .daxBodyRegular()
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                    Button {
                        viewModel.launchAIFeaturesLearnMore()
                    } label: {
                        Text(UserText.aiFeaturesLearnMore)
                            .daxBodyRegular()
                            .foregroundColor(Color(designSystemColor: .textLink))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)

            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)

            Section {
                SettingsCellView(label: UserText.settingsEnableAiChat,
                                 subtitle: UserText.settingsEnableAiChatSubtitle,
                                 image: Image(uiImage: DesignSystemImages.Glyphs.Size24.aiChat),
                                 accessory: .toggle(isOn: viewModel.isAiChatEnabledBinding))
            }

            if viewModel.isAiChatEnabledBinding.wrappedValue {
                if viewModel.experimentalAIChatManager.isExperimentalAIChatFeatureFlagEnabled {

                    if viewModel.isUpdatedAIFeaturesSettingsEnabled {
                        Section {
                            HStack {
                                Spacer()
                                SettingsAIExperimentalPickerView(isDuckAISelected: viewModel.aiChatSearchInputEnabledBinding)
                                    .padding(.vertical, 8)
                                Spacer()
                            }
                        } footer: {
                            Text(footerAttributedString)
                                .environment(\.openURL, OpenURLAction { url in
                                    switch FooterAction.from(url) {
                                    case .shareFeedback?:
                                        viewModel.presentLegacyView(.feedback)
                                        return .handled
                                    case nil:
                                        return .systemAction
                                    }
                                })
                        }
                        .listRowBackground(Color(designSystemColor: .surface))
                    } else {
                        Section {
                            SettingsCellView(label: UserText.settingsAiChatSearchInput,
                                             accessory: .toggle(isOn: viewModel.aiChatSearchInputEnabledBinding))
                        } footer: {
                            Text(UserText.settingsAiChatSearchInputFooter)
                        }
                    }
                }

                if viewModel.isUpdatedAIFeaturesSettingsEnabled {
                    Section {
                        NavigationLink(destination: SettingsAIChatShortcutsView().environmentObject(viewModel)) {
                            SettingsCellView(label: UserText.settingsManageAIChatShortcuts)
                        }
                    }
                    .listRowBackground(Color(designSystemColor: .surface))
                } else {
                    Section(header: Text(UserText.settingsAiChatShortcuts)) {
                        SettingsCellView(label: UserText.aiChatSettingsEnableBrowsingMenuToggle,
                                         accessory: .toggle(isOn: viewModel.aiChatBrowsingMenuEnabledBinding))

                        SettingsCellView(label: UserText.aiChatSettingsEnableAddressBarToggle,
                                         accessory: .toggle(isOn: viewModel.aiChatAddressBarEnabledBinding))

                        if viewModel.state.voiceSearchEnabled {
                            SettingsCellView(label: UserText.aiChatSettingsEnableVoiceSearchToggle,
                                             accessory: .toggle(isOn: viewModel.aiChatVoiceSearchEnabledBinding))
                        }

                        SettingsCellView(label: UserText.aiChatSettingsEnableTabSwitcherToggle,
                                         accessory: .toggle(isOn: viewModel.aiChatTabSwitcherEnabledBinding))
                    }
                }
            }

            Section {
                SettingsCellView(label: UserText.settingsAiFeaturesSearchAssist,
                                 subtitle: UserText.settingsAiFeaturesSearchAssistSubtitle,
                                 image: Image(uiImage: DesignSystemImages.Glyphs.Size24.assist),
                                 action: { viewModel.openAssistSettings() },
                                 webLinkIndicator: true,
                                 isButton: true)
            }
        }.applySettingsListModifiers(title: UserText.settingsAiFeatures,
                                     displayMode: .inline,
                                     viewModel: viewModel)


        .onAppear {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsDisplayed,
                                         withAdditionalParameters: viewModel.featureDiscovery.addToParams([:], forFeature: .aiChat))
        }
    }
}

private extension SettingsAIFeaturesView {
    var footerAttributedString: AttributedString {
        var base = AttributedString(UserText.settingsAiExperimentalPickerFooterDescription + " ")
        var link = AttributedString(UserText.subscriptionFeedback)
        link.foregroundColor = Color(designSystemColor: .accent)
        link.link = FooterAction.shareFeedback.url
        base.append(link)
        return base
    }
}

private enum FooterAction {
    static let scheme = "action"

    case shareFeedback

    var url: URL {
        URL(string: "\(Self.scheme)://\(host)")!
    }

    private var host: String {
        switch self {
        case .shareFeedback: return "share-feedback"
        }
    }

    static func from(_ url: URL) -> FooterAction? {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "share-feedback": return .shareFeedback
        default: return nil
        }
    }
}
