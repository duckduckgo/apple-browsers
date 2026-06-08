//
//  GranularFireConfirmationView.swift
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
import DesignResourcesKitIcons
import Core
import DuckUI
import MetricBuilder

struct GranularFireConfirmationView: View {
    
    @ObservedObject var viewModel: GranularFireConfirmationViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: SheetMetrics.contentSpacing) {
                headerSection
                optionsList
                footerButtons
            }
            .padding(.horizontal, SheetMetrics.contentHorizontalPadding)
            .padding(.vertical, Constants.mainViewPadding.top)
        }
        .background(Color(designSystemColor: .backgroundTertiary))
        .modifier(ScrollBounceBehaviorModifier())
    }
    
    /// Header with title and large icon
    private var headerSection: some View {
        VStack(spacing: SheetMetrics.contentSpacing) {
            Image(uiImage: DesignSystemImages.Color.Size72.fire)
                .resizable()
                .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)
            
            Text(UserText.fireConfirmationTitle)
                .daxTitle3()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var optionsList: some View {
        VStack(spacing: Constants.optionsListSpacing) {
            ToggleRow(
                icon: DesignSystemImages.Glyphs.Size24.tabsMobile,
                title: UserText.fireConfirmationTabsTitle,
                subtitle: viewModel.clearTabsSubtitle(),
                isOn: $viewModel.clearTabs,
                isDisabled: viewModel.isClearTabsDisabled
            )
            .accessibilityIdentifier("Fire.Confirmation.Toggle.Tabs.\(viewModel.clearTabs ? "on" : "off")")
            
            shiftedDivider
            
            ToggleRow(
                icon: DesignSystemImages.Glyphs.Size24.cookie,
                title: UserText.fireConfirmationDataTitle,
                subtitle: viewModel.clearDataSubtitle(),
                isOn: $viewModel.clearData,
                isDisabled: viewModel.isClearDataDisabled
            )
            .accessibilityIdentifier("Fire.Confirmation.Toggle.Data.\(viewModel.clearData ? "on" : "off")")
            
            if viewModel.showAIChatsOption {
                shiftedDivider
                
                ToggleRow(
                    icon: DesignSystemImages.Glyphs.Size24.aiChat,
                    title: UserText.fireConfirmationAIChatsTitle,
                    subtitle: UserText.fireConfirmationAIChatsSubtitle,
                    isOn: $viewModel.clearAIChats
                )
                .accessibilityIdentifier("Fire.Confirmation.Toggle.AIChats.\(viewModel.clearAIChats ? "on" : "off")")
            }
        }
        .background(Color(designSystemColor: .surface))
        .cornerRadius(Constants.optionsListCornerRadius)
    }
    
    private var shiftedDivider: some View {
        Rectangle()
            .fill(Color(designSystemColor: .lines))
            .frame(height: Constants.dividerHeight)
            .padding(.leading, Constants.dividerLeadingSpace)
    }
    
    private var footerButtons: some View {
        VStack(spacing: ButtonStackMetrics.interButtonSpacing) {
            // Delete button
            Button(action: {
                viewModel.confirm()
            }) {
                Text(UserText.actionDelete)
            }
            .buttonStyle(PrimaryDestructiveButtonStyle(disabled: viewModel.isDeleteButtonDisabled))
            .disabled(viewModel.isDeleteButtonDisabled)
            .accessibilityIdentifier("Fire.Confirmation.Button.Delete")
            
            // Cancel button
            Button(action: {
                viewModel.cancel()
            }) {
                Text(UserText.actionCancel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GhostAltButtonStyle())
            .accessibilityIdentifier("Fire.Confirmation.Button.Cancel")
        }
    }
}

private extension GranularFireConfirmationView {
    enum Constants {
        // Main View
        static let mainViewPadding: EdgeInsets = .init(top: 24, leading: 24, bottom: 24, trailing: 24)
        
        // Header section
        static let headerIconSize: CGFloat = 96
        
        // Options List
        static let optionsListSpacing: CGFloat = 0
        static let optionsListCornerRadius: CGFloat = 10
        static let dividerHeight: CGFloat = 0.5
        static let dividerLeadingSpace: CGFloat = 52
    }
}

private struct ToggleRow: View {
    let icon: DesignSystemImage
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false
    
    var body: some View {
        HStack(spacing: Constants.horizontalSpacing) {
            // Icon
            Image(uiImage: icon)
                .padding(.leading, Constants.iconPadding.leading)
                .padding(.trailing, Constants.iconPadding.trailing)
            
            // Text content
            VStack(alignment: .leading, spacing: Constants.titlesVerticalSpacing) {
                Text(title)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(subtitle)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Constants.titlesVerticalPadding)
            .padding(.trailing, Constants.titlesTrailingPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Toggle
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .disabled(isDisabled)
                .padding(.trailing, Constants.toggleTrailingPadding)
                .tint(Color(designSystemColor: .accent))
        }
    }
    
    enum Constants {
        static let horizontalSpacing: CGFloat = 0
        static let iconPadding: EdgeInsets = .init(top: 0, leading: 16, bottom: 0, trailing: 12)
        static let titlesVerticalSpacing: CGFloat = 2
        static let titlesVerticalPadding: CGFloat = 10.5
        static let titlesTrailingPadding: CGFloat = 16
        static let toggleTrailingPadding: CGFloat = 16
    }
}

#if DEBUG
import AIChat
import History
import Persistence

private final class PreviewTabsModel: TabsModelReading {
    var count: Int { 3 }
    var tabs: [Tab] { [] }
}

private final class PreviewHistoryManager: HistoryManaging {
    var isEnabledByUser: Bool { false }
    var history: BrowsingHistory? { nil }
    @MainActor func removeAllHistory() async -> Result<Void, Error> { .success(()) }
    @MainActor func deleteHistoryForURL(_ url: URL) async {}
    @MainActor func addVisit(of url: URL, tabID: String?, fireTab: Bool) {}
    @MainActor func updateTitleIfNeeded(title: String, url: URL) {}
    @MainActor func commitChanges(url: URL) {}
    @MainActor func tabHistory(tabID: String) async throws -> [URL] { [] }
    @MainActor func removeTabHistory(for tabIDs: [String]) async -> Result<Void, Error> { .success(()) }
    @MainActor func removeBrowsingHistory(tabID: String) async -> ActionResult? { nil }
}

private final class PreviewFireproofing: Fireproofing {
    var loginDetectionEnabled: Bool = false
    var allowedDomains: [String] { [] }
    func isAllowed(cookieDomain: String) -> Bool { false }
    func isAllowed(fireproofDomain domain: String) -> Bool { false }
    func addToAllowed(domain: String) {}
    func remove(domain: String) {}
    func clearAll() {}
    func displayDomain(for domain: String) -> String { domain }
    func migrateFireproofDomainsToETLDPlus1IfNeeded() -> Bool { false }
}

private final class PreviewAIChatSettings: AIChatSettingsProvider {
    var aiChatURL: URL { URL(string: "https://duckduckgo.com")! }
    var isAIChatEnabled: Bool { true }
    var sessionTimerInMinutes: Int { 0 }
    var isAIChatAddressBarUserSettingsEnabled: Bool { false }
    var isAIChatSearchInputUserSettingsEnabled: Bool { false }
    var isAIChatSearchInputUserSettingsDisabledByUser: Bool { false }
    var isAIChatBrowsingMenuUserSettingsEnabled: Bool { false }
    var isAIChatVoiceSearchUserSettingsEnabled: Bool { false }
    var isAIChatTabSwitcherUserSettingsEnabled: Bool { false }
    var isAIChatTabBarUserSettingsEnabled: Bool { false }
    var isAutomaticContextAttachmentEnabled: Bool { false }
    var isChatSuggestionsEnabled: Bool { false }
    func enableAIChat(enable: Bool) {}
    func enableAIChatBrowsingMenuUserSettings(enable: Bool) {}
    func enableAIChatAddressBarUserSettings(enable: Bool) {}
    func enableAIChatVoiceSearchUserSettings(enable: Bool) {}
    func enableAIChatTabSwitcherUserSettings(enable: Bool) {}
    func enableAIChatTabBarUserSettings(enable: Bool) {}
    func enableAIChatSearchInputUserSettings(enable: Bool) {}
    func enableAutomaticContextAttachment(enable: Bool) {}
    func enableChatSuggestions(enable: Bool) {}
    var defaultOmnibarMode: DefaultOmnibarMode { .search }
    func setDefaultOmnibarMode(_ mode: DefaultOmnibarMode) {}
}

private final class PreviewThrowingKeyValueStore: ThrowingKeyValueStoring {
    func object(forKey defaultName: String) throws -> Any? { nil }
    func set(_ value: Any?, forKey defaultName: String) throws {}
    func removeObject(forKey defaultName: String) throws {}
}

#Preview {
    GranularFireConfirmationView(
        viewModel: GranularFireConfirmationViewModel(
            tabsModel: PreviewTabsModel(),
            historyManager: PreviewHistoryManager(),
            fireproofing: PreviewFireproofing(),
            aiChatSettings: PreviewAIChatSettings(),
            keyValueFilesStore: PreviewThrowingKeyValueStore(),
            onConfirm: { _ in },
            onCancel: {}
        )
    )
}
#endif
