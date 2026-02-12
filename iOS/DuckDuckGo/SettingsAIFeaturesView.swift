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
import PixelKit

struct SettingsAIFeaturesView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        List {

            VStack(alignment: .center) {
                Image(.settingAIFeaturesHero)
                    .padding(.top, -20)

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

                    Section {
                        HStack {
                            SettingsAIExperimentalPickerView(isDuckAISelected: viewModel.aiChatSearchInputEnabledBinding)
                                .padding(.vertical, 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
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

                }

                if viewModel.experimentalAIChatManager.isContextualDuckAIModeEnabled {
                    Section {
                        SettingsCellView(label: UserText.settingsAutomaticPageContextTitle,
                                         subtitle: UserText.settingsAutomaticPageContextSubtitle,
                                         accessory: .toggle(isOn: viewModel.isAutomaticContextAttachmentEnabled))
                    }
                }

                Section {
                    NavigationLink(destination: SettingsAIChatShortcutsView().environmentObject(viewModel)) {
                        SettingsCellView(label: UserText.settingsManageAIChatShortcuts)
                    }
                }
                .listRowBackground(Color(designSystemColor: .surface))

            }

            if !viewModel.openedFromSERPSettingsButton {
                Section {
                    NavigationLink(destination: SERPSettingsView(page: .searchAssist, featureFlagger: viewModel.featureFlagger)) {
                        SettingsCellView(label: UserText.settingsAiFeaturesSearchAssist,
                                         subtitle: UserText.settingsAiFeaturesSearchAssistSubtitle,
                                         image: Image(uiImage: DesignSystemImages.Glyphs.Size24.assist))
                    }
                    .listRowBackground(Color(designSystemColor: .surface))

                    if viewModel.shouldShowHideAIGeneratedImagesSection {
                        NavigationLink(destination: SERPSettingsView(page: .hideAIGeneratedImages, featureFlagger: viewModel.featureFlagger)
                                .onAppear {
                                    PixelKit.fire(SERPSettingsPixel.hideAIGeneratedImagesButtonClicked, frequency: .dailyAndStandard)
                                }
                        ) {
                            SettingsCellView(label: UserText.settingsAiFeaturesHideAIGeneratedImages,
                                             subtitle: UserText.settingsAiFeaturesHideAIGeneratedImagesSubtitle,
                                             image: Image(uiImage: DesignSystemImages.Glyphs.Size24.imageAIHide))
                        }
                        .listRowBackground(Color(designSystemColor: .surface))
                    }
                }
            }
        }.applySettingsListModifiers(title: UserText.settingsAiFeatures,
                                     displayMode: .inline,
                                     viewModel: viewModel)
        .navigationBarBackButtonHidden(viewModel.openedFromSERPSettingsButton)
        .navigationBarItems(trailing: viewModel.openedFromSERPSettingsButton ?
            AnyView(Button(UserText.navigationTitleDone) {
                viewModel.onRequestDismissSettings?()
            }.foregroundColor(Color(designSystemColor: .textPrimary))) : AnyView(EmptyView()))


        .onAppear {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsDisplayed,
                                         withAdditionalParameters: viewModel.featureDiscovery.addToParams([:], forFeature: .aiChat))
            // Fire funnel pixel for first time viewing settings page with new input option
            if let aiChatSettings = viewModel.aiChatSettings as? AIChatSettings {
                aiChatSettings.processSettingsViewedFunnelStep()
            }
        }
    }
}

private extension SettingsAIFeaturesView {
    var footerAttributedString: AttributedString {
        var base = AttributedString(UserText.settingsAIPickerFooterDescription + " ")
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
