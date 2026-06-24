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
import FoundationExtensions
import Networking
import PixelKit
import AIChat
import SERPSettings

struct SettingsAIFeaturesView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            header

            if viewModel.isAIFeaturesNativeControlsEnabled {
                SettingsAINativeFeaturesView()
            } else {
                SettingsAILegacyFeaturesView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isAIFeaturesNativeControlsEnabled,
               UIDevice.current.userInterfaceIdiom == .pad {
                Color.clear.frame(height: 8)
            }
        }
        .applySettingsListModifiers(title: UserText.settingsAiFeatures,
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

    private var header: some View {
        VStack(alignment: .center) {
            Image(rebrandable: "SettingAIFeaturesHero")
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
                        .foregroundColor(Color(designSystemColor: .accentTextPrimary))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Native controls layout (aiFeaturesNativeControls ON)

private struct SettingsAINativeFeaturesView: AIFeaturesSettingsRowProviding {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        // The 3 main AI settings grouped at the top.
        Section {
            duckAIEnableToggleRow

            SettingsPickerCellView(
                label: UserText.settingsAiFeaturesSearchAssistTitle,
                subtitle: UserText.settingsAiFeaturesSearchAssistSubtitle,
                image: Image(uiImage: DesignSystemImages.Glyphs.Size24.assist),
                options: SearchAssistFrequency.allCases.map { Optional($0) },
                selectedOption: viewModel.searchAssistFrequencyBinding
            )
            .accessibilityIdentifier("Settings.AIFeatures.SearchAssistPicker")

            SettingsPickerCellView(
                label: UserText.settingsAiFeaturesHideAIGeneratedImages,
                subtitle: UserText.settingsAiFeaturesHideAIGeneratedImagesSubtitle,
                image: Image(uiImage: DesignSystemImages.Glyphs.Size24.imageAIHide),
                options: HideAIImagesOption.allCases.map { Optional($0) },
                selectedOption: viewModel.hideAIImagesBinding
            )
            .accessibilityIdentifier("Settings.AIFeatures.HideAIGeneratedImagesPicker")
        }

        // Grouped "Duck.ai" section with the Duck.ai-specific settings.
        if viewModel.isAiChatEnabledBinding.wrappedValue {
            Section {
                duckAISearchInputRows
                autoSendContentRow
                manageShortcutsRow
                duckAISettingsRow
            } header: {
                Text(UserText.settingsDuckAiSectionHeader)
            }
            .listRowBackground(Color(designSystemColor: .surface))
        }

        // Always shown: the button disables all AI while any is on, then greys out
        // once everything is disabled, with the footer reinforcing the no-AI state.
        Section {
            Button {
                viewModel.disableAllAI()
            } label: {
                Text(UserText.settingsAiFeaturesDisableAIFeatures)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .accentPrimary))
                    .opacity(viewModel.isAllAIDisabled ? 0.4 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAllAIDisabled)
            .accessibilityIdentifier("Settings.AIFeatures.DisableAllAIOptions")
        } footer: {
            Text(viewModel.isAllAIDisabled ? UserText.settingsAiFeaturesDisableAllFooterDisabled : UserText.settingsAiFeaturesDisableAllFooter)
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }
}

// MARK: - Legacy layout (aiFeaturesNativeControls OFF)

private struct SettingsAILegacyFeaturesView: AIFeaturesSettingsRowProviding {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            duckAIEnableToggleRow

            if viewModel.isAiChatEnabledBinding.wrappedValue {
                duckAISettingsRow
            }
        }

        if viewModel.isAiChatEnabledBinding.wrappedValue {
            if viewModel.experimentalAIChatManager.isExperimentalAIChatFeatureFlagEnabled {
                Section {
                    duckAISearchInputRows
                } footer: {
                    aiChatFeedbackFooter
                }
                .listRowBackground(Color(designSystemColor: .surface))
            }

            if viewModel.experimentalAIChatManager.isContextualDuckAIModeEnabled {
                Section {
                    autoSendContentRow
                }
            }

            Section {
                manageShortcutsRow
            }
            .listRowBackground(Color(designSystemColor: .surface))
        }

        if !viewModel.openedFromSERPSettingsButton {
            Section {
                NavigationLink(destination: SERPSettingsView(page: .searchAssist,
                                                             contentBlockingAssetsPublisher: viewModel.contentBlockingAssetsPublisher,
                                                             keyValueStore: viewModel.keyValueStore)) {
                    SettingsCellView(label: UserText.settingsAiFeaturesSearchAssist,
                                     subtitle: UserText.settingsAiFeaturesSearchAssistSubtitle,
                                     image: Image(uiImage: DesignSystemImages.Glyphs.Size24.assist))
                }
                .listRowBackground(Color(designSystemColor: .surface))

                NavigationLink(destination: SERPSettingsView(page: .hideAIGeneratedImages,
                                                             contentBlockingAssetsPublisher: viewModel.contentBlockingAssetsPublisher,
                                                             keyValueStore: viewModel.keyValueStore)
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
}

// MARK: - Shared rows

/// Rows shared between the native-controls and legacy AI Features layouts.
private protocol AIFeaturesSettingsRowProviding: View {
    var viewModel: SettingsViewModel { get }
}

private extension AIFeaturesSettingsRowProviding {

    @ViewBuilder
    var duckAIEnableToggleRow: some View {
        SettingsCellView(label: UserText.settingsEnableAiChat,
                         subtitle: UserText.settingsEnableAiChatSubtitle,
                         image: Image(uiImage: DesignSystemImages.Glyphs.Size24.aiChat),
                         accessory: .toggle(isOn: viewModel.isAiChatEnabledBinding),
                         accessoryAccessibilityIdentifier: "Settings.AIFeatures.EnableToggle")
    }

    @ViewBuilder
    var duckAISearchInputRows: some View {
        if viewModel.experimentalAIChatManager.isExperimentalAIChatFeatureFlagEnabled {
            let pickerRow = HStack {
                SettingsAIExperimentalPickerView(isDuckAISelected: viewModel.aiChatSearchInputEnabledBinding)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Custom row: keep its separator full-width like the standard cells above/below (iOS 16+).
            if #available(iOS 16.0, *) {
                pickerRow.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            } else {
                pickerRow
            }

            if viewModel.aiChatSearchInputEnabledBinding.wrappedValue,
               viewModel.isDefaultOmnibarModeEnabled {
                SettingsPickerCellView(
                    label: UserText.settingsDefaultOmnibarModeHeader,
                    subtitle: UserText.settingsDefaultOmnibarModeFooter,
                    options: DefaultOmnibarMode.allCases.map { Optional($0) },
                    selectedOption: viewModel.defaultOmnibarModeBinding
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    var autoSendContentRow: some View {
        if viewModel.experimentalAIChatManager.isContextualDuckAIModeEnabled {
            SettingsCellView(label: UserText.settingsAutomaticPageContextTitle,
                             subtitle: UserText.settingsAutomaticPageContextSubtitle,
                             accessory: .toggle(isOn: viewModel.isAutomaticContextAttachmentEnabled))
        }
    }

    @ViewBuilder
    var manageShortcutsRow: some View {
        NavigationLink(destination: SettingsAIChatShortcutsView().environmentObject(viewModel)) {
            SettingsCellView(label: UserText.settingsManageAIChatShortcuts)
        }
    }

    @ViewBuilder
    var duckAISettingsRow: some View {
        SettingsCellView(label: UserText.settingsDuckAISettings,
                         image: Image(uiImage: DesignSystemImages.Glyphs.Size24.settingsAiChat),
                         action: { viewModel.openDuckAIChat() },
                         accessory: .custom(AnyView(
                            Image(uiImage: DesignSystemImages.Glyphs.Size24.openInSmall)
                                .foregroundColor(Color(designSystemColor: .iconsSecondary))
                         )),
                         isButton: true)
        .accessibilityIdentifier("Settings.AIFeatures.DuckAISettings")
    }

    @ViewBuilder
    var aiChatFeedbackFooter: some View {
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

    var footerAttributedString: AttributedString {
        var base = AttributedString(UserText.settingsAIPickerFooterDescription + " ")
        var link = AttributedString(UserText.subscriptionFeedback)
        link.foregroundColor = Color(designSystemColor: .accentPrimary)
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

extension DefaultOmnibarMode: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .search: return UserText.settingsDefaultOmnibarModeSearch
        case .duckAI: return UserText.settingsDefaultOmnibarModeDuckAI
        case .lastUsed: return UserText.settingsDefaultOmnibarModeLastUsed
        }
    }
}

extension SearchAssistFrequency: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .never: return UserText.settingsAiFeaturesSearchAssistNever
        case .onDemand: return UserText.settingsAiFeaturesSearchAssistOnDemand
        case .sometimes: return UserText.settingsAiFeaturesSearchAssistSometimes
        case .often: return UserText.settingsAiFeaturesSearchAssistOften
        }
    }
}

/// On/Off picker option for the Hide AI-Generated Images setting, mapping to the
/// `hideAIGeneratedImages` Bool accessor (`on` = hidden).
enum HideAIImagesOption: String, CaseIterable, Hashable, CustomStringConvertible {
    case on
    case off

    init(hidden: Bool) {
        self = hidden ? .on : .off
    }

    var hidden: Bool {
        self == .on
    }

    var description: String {
        switch self {
        case .on: return UserText.settingsAiFeaturesHideAIGeneratedImagesOn
        case .off: return UserText.settingsAiFeaturesHideAIGeneratedImagesOff
        }
    }
}
