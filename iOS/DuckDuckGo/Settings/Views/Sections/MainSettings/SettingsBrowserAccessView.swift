//
//  SettingsBrowserAccessView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

@MainActor
struct SettingsBrowserAccessView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @State private var storedStates: [String: BrowserToolPermissionState] = [:]
    @State private var showsResetConfirmation = false

    let service: AIChatBrowserToolsService

    var body: some View {
        let canSee = enabledRows(BrowserAccessTool.canSee)
        let canDo = enabledRows(BrowserAccessTool.canDo)
        let canResetAll = (canSee + canDo).contains { row in
            storedStates[row.id] != nil && row.state != row.defaultState
        }

        List {
            if !canSee.isEmpty {
                toolSection(canSee, title: UserText.settingsBrowserAccessCanSee, showsFooter: canDo.isEmpty)
            }

            if !canDo.isEmpty {
                toolSection(canDo, title: UserText.settingsBrowserAccessCanDo, showsFooter: true)
            }

            if !canSee.isEmpty || !canDo.isEmpty {
                Section {
                    Button {
                        showsResetConfirmation = true
                    } label: {
                        Text(UserText.settingsBrowserAccessResetAll)
                            .daxBodyRegular()
                            .foregroundColor(Color(designSystemColor: canResetAll ? .accentTextPrimary : .textSecondary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canResetAll)
                    .accessibilityIdentifier("Settings.BrowserAccess.ResetAll")
                }
                .listRowBackground(Color(designSystemColor: .surfaceTertiary))
            }
        }
        .applySettingsListModifiers(title: UserText.settingsBrowserAccessTitle, viewModel: viewModel)
        .onAppear(perform: reload)
        .onReceive(service.permissions.changesPublisher) { reload() }
        .alert(UserText.settingsBrowserAccessResetAlertTitle, isPresented: $showsResetConfirmation) {
            Button(UserText.actionCancel, role: .cancel) {}
            Button(UserText.settingsBrowserAccessResetAll, role: .destructive) {
                guard viewModel.isAiChatEnabledBinding.wrappedValue, !service.catalog.enabledTools.isEmpty else { return }
                service.permissions.clearAll()
            }
        } message: {
            Text(UserText.settingsBrowserAccessResetAlertMessage)
        }
    }

    private func enabledRows(_ tools: [BrowserAccessTool]) -> [BrowserAccessRow] {
        guard viewModel.isAiChatEnabledBinding.wrappedValue else { return [] }
        return tools.compactMap { item in
            guard let tool = service.catalog.tool(for: item.capability) else { return nil }
            return BrowserAccessRow(item: item,
                                    state: service.permissions.effectiveState(for: tool),
                                    defaultState: tool.asksEveryTime ? .ask : tool.permissionMode.defaultState,
                                    options: tool.asksEveryTime ? [.ask, .deny] : [.ask, .allow, .deny])
        }
    }

    private func toolSection(_ rows: [BrowserAccessRow], title: String, showsFooter: Bool) -> some View {
        Section {
            ForEach(rows) { row in
                BrowserAccessToolCell(row: row) { state in
                    setState(state, for: row.item.capability)
                }
            }
        } header: {
            Text(title)
        } footer: {
            if showsFooter {
                Text(UserText.settingsBrowserAccessFooter)
            }
        }
        .listRowBackground(Color(designSystemColor: .surfaceTertiary))
    }

    private func setState(_ state: BrowserToolPermissionState, for capability: ClientToolCapability) {
        guard viewModel.isAiChatEnabledBinding.wrappedValue,
              let tool = service.catalog.tool(for: capability),
              !(tool.asksEveryTime && state == .allow) else { return }
        service.permissions.setState(state == tool.permissionMode.defaultState ? nil : state, forToolNamed: tool.name)
    }

    private func reload() {
        storedStates = service.permissions.storedDecisions
    }
}

private struct BrowserAccessToolCell: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let row: BrowserAccessRow
    let setState: (BrowserToolPermissionState) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    titleAndDetail
                    permissionMenu
                }
            } else {
                HStack(spacing: 8) {
                    titleAndDetail
                    Spacer(minLength: 0)
                    permissionMenu
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var titleAndDetail: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(uiImage: row.item.icon)
                .renderingMode(.template)
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundColor(Color(designSystemColor: .iconsSecondary))
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.item.title)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Text(row.item.detail)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var permissionMenu: some View {
        Menu {
            ForEach(row.options, id: \.self) { state in
                Button {
                    setState(state)
                } label: {
                    if state == row.state {
                        Label(row.title(for: state), systemImage: "checkmark")
                    } else {
                        Text(row.title(for: state))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(row.title(for: row.state))
                    .daxSubheadRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.footnote).weight(.semibold))
                    .foregroundColor(Color(designSystemColor: .iconsSecondary))
            }
        }
        .accessibilityLabel(row.item.title)
        .accessibilityValue(row.title(for: row.state))
        .accessibilityIdentifier("Settings.BrowserAccess.\(row.id)")
    }
}

private struct BrowserAccessRow: Identifiable {
    let item: BrowserAccessTool
    let state: BrowserToolPermissionState
    let defaultState: BrowserToolPermissionState
    let options: [BrowserToolPermissionState]

    var id: String { item.capability.name }

    func title(for state: BrowserToolPermissionState) -> String {
        switch state {
        case .ask: UserText.settingsBrowserAccessAlwaysAsk
        case .allow: UserText.settingsBrowserAccessAlwaysAllow
        case .deny: UserText.settingsBrowserAccessNeverAllow
        }
    }
}

private struct BrowserAccessTool {
    private typealias Icons = DesignSystemImages.Glyphs.Size16

    let capability: ClientToolCapability
    let title: String
    let detail: String
    let icon: UIImage

    static let canSee: [Self] = [
        .init(capability: .readTabContent,
              title: UserText.settingsBrowserAccessReadTabContent,
              detail: UserText.settingsBrowserAccessReadTabContentDetail,
              icon: Icons.file),
        .init(capability: .listOpenTabs,
              title: UserText.settingsBrowserAccessListOpenTabs,
              detail: UserText.settingsBrowserAccessListOpenTabsDetail,
              icon: Icons.windowsAndTabs),
        .init(capability: .findInPage,
              title: UserText.findInPage,
              detail: UserText.settingsBrowserAccessFindInPageDetail,
              icon: Icons.searchSite),
        .init(capability: .searchHistory,
              title: UserText.settingsBrowserAccessSearchHistory,
              detail: UserText.settingsBrowserAccessSearchHistoryDetail,
              icon: Icons.history),
        .init(capability: .searchBookmarks,
              title: UserText.settingsBrowserAccessSearchBookmarks,
              detail: UserText.settingsBrowserAccessSearchBookmarksDetail,
              icon: Icons.bookmarks)
    ]

    static let canDo: [Self] = [
        .init(capability: .switchToTab,
              title: UserText.settingsBrowserAccessSwitchToTab,
              detail: UserText.settingsBrowserAccessSwitchToTabDetail,
              icon: Icons.arrowCircleRight),
        .init(capability: .openTab,
              title: UserText.settingsBrowserAccessOpenTab,
              detail: UserText.settingsBrowserAccessOpenTabDetail,
              icon: DesignSystemImages.Glyphs.Size24.tabNew)
    ]
}
