//
//  PreferencesBrowserToolPermissionsView.swift
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
import Combine
import DesignResourcesKit
import DesignResourcesKitIcons
import PreferencesUI_macOS
import SwiftUI

@MainActor
final class BrowserToolPermissionsPreferences: ObservableObject {

    struct Row: Identifiable, Equatable {
        let name: String
        let defaultState: BrowserToolPermissionState
        var id: String { name }
    }

    static let order = ["readTabContent", "listOpenTabs", "findInPage", "searchHistory", "bookmarkTab", "closeTabs",
                        "highlightInPage", "openTab", "pinTab", "searchBookmarks", "searchDownloads", "switchToTab"]

    @Published private(set) var rows: [Row] = []
    @Published private(set) var storedStates: [String: BrowserToolPermissionState] = [:]

    private let catalog: BrowserToolCatalog
    private let permissions: BrowserToolPermissionStoring
    private var permissionChanges: AnyCancellable?

    init(catalog: BrowserToolCatalog = NSApp.delegateTyped.aiChatBrowserToolsService.catalog,
         permissions: BrowserToolPermissionStoring = NSApp.delegateTyped.aiChatBrowserToolsService.permissions,
         permissionManager: PermissionManagerProtocol = NSApp.delegateTyped.permissionManager) {
        self.catalog = catalog
        self.permissions = permissions
        permissionChanges = permissionManager.permissionPublisher
            .filter { $0.domain == BrowserToolSitePermissions.domain }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
        reload()
    }

    func reload() {
        rows = catalog.enabledTools
            .sorted { (Self.order.firstIndex(of: $0.name) ?? .max) < (Self.order.firstIndex(of: $1.name) ?? .max) }
            .map { Row(name: $0.name, defaultState: $0.permissionMode.defaultState) }
        storedStates = permissions.storedDecisions
    }

    func state(of row: Row) -> BrowserToolPermissionState {
        storedStates[row.name] ?? row.defaultState
    }

    func setState(_ state: BrowserToolPermissionState, of row: Row) {
        permissions.setState(state == row.defaultState ? nil : state, forToolNamed: row.name)
        reload()
    }

    func reset(_ row: Row) {
        permissions.setState(nil, forToolNamed: row.name)
        reload()
    }

    func resetAll() {
        permissions.clearAll()
        reload()
    }

    var canResetAll: Bool {
        rows.contains { storedStates[$0.name] != nil }
    }
}

struct PreferencesBrowserToolPermissionsView: View {

    @StateObject private var model = BrowserToolPermissionsPreferences()

    var body: some View {
        if !model.rows.isEmpty {
            PreferencePaneSection(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextMenuItemHeader(UserText.browserToolSettingsTitle)
                        Spacer()
                        Button(UserText.browserToolSettingsResetAll, action: model.resetAll)
                            .disabled(!model.canResetAll)
                            .accessibilityIdentifier("Preferences.AIChat.browserToolPermissions.resetAll")
                    }
                    TextMenuItemCaption(UserText.browserToolSettingsCaption)
                }

                PreferencesWebsitePermissionListContainer {
                    VStack(spacing: 0) {
                        ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                WebsitePermissionListSeparator()
                            }
                            BrowserToolPermissionRow(row: row, model: model)
                        }
                    }
                }
            }
            .onAppear(perform: model.reload)
        }
    }
}

private struct BrowserToolPermissionRow: View {

    let row: BrowserToolPermissionsPreferences.Row
    @ObservedObject var model: BrowserToolPermissionsPreferences

    private static let states: [BrowserToolPermissionState] = [.ask, .allow, .deny]

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: BrowserToolPermissionPromptText.icon(toolName: row.name))
                .renderingMode(.template)
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundColor(Color(designSystemColor: .iconsPrimary))

            VStack(alignment: .leading, spacing: 2) {
                Text(BrowserToolSettingsText.title(toolName: row.name))
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                if let detail = BrowserToolSettingsText.detail(toolName: row.name) {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)

            Picker(selection: Binding(get: { model.state(of: row) }, set: { model.setState($0, of: row) }), label: EmptyView()) {
                ForEach(Self.states, id: \.self) { state in
                    Text(Self.title(for: state)).tag(state)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(BrowserToolSettingsText.title(toolName: row.name))
            .accessibilityIdentifier("Preferences.AIChat.browserToolPermissions.\(row.name)")

            Button { model.reset(row) } label: {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.undo)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .disabled(model.storedStates[row.name] == nil)
            .opacity(model.storedStates[row.name] == nil ? 0.4 : 1)
            .accessibilityLabel(UserText.browserToolSettingsReset)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private static func title(for state: BrowserToolPermissionState) -> String {
        switch state {
        case .ask: UserText.permissionCenterAlwaysAsk
        case .allow: UserText.permissionCenterAlwaysAllow
        case .deny: UserText.permissionCenterNeverAllow
        }
    }
}

enum BrowserToolSettingsText {

    static func title(toolName: String) -> String {
        switch toolName {
        case "readTabContent": UserText.browserToolSettingsTitleReadTabContent
        case "listOpenTabs": UserText.browserToolSettingsTitleListOpenTabs
        case "findInPage": UserText.browserToolSettingsTitleFindInPage
        case "searchHistory": UserText.browserToolSettingsTitleSearchHistory
        case "bookmarkTab": UserText.browserToolSettingsTitleBookmarkTab
        case "closeTabs": UserText.browserToolSettingsTitleCloseTabs
        case "highlightInPage": UserText.browserToolSettingsTitleHighlightInPage
        case "openTab": UserText.browserToolSettingsTitleOpenTab
        case "pinTab": UserText.browserToolSettingsTitlePinTab
        case "searchBookmarks": UserText.browserToolSettingsTitleSearchBookmarks
        case "searchDownloads": UserText.browserToolSettingsTitleSearchDownloads
        case "switchToTab": UserText.browserToolSettingsTitleSwitchToTab
        default: toolName
        }
    }

    static func detail(toolName: String) -> String? {
        switch toolName {
        case "readTabContent": UserText.browserToolSettingsDetailReadTabContent
        case "listOpenTabs": UserText.browserToolSettingsDetailListOpenTabs
        case "findInPage": UserText.browserToolSettingsDetailFindInPage
        case "searchHistory": UserText.browserToolSettingsDetailSearchHistory
        case "bookmarkTab": UserText.browserToolSettingsDetailBookmarkTab
        case "closeTabs": UserText.browserToolSettingsDetailCloseTabs
        case "highlightInPage": UserText.browserToolSettingsDetailHighlightInPage
        case "openTab": UserText.browserToolSettingsDetailOpenTab
        case "pinTab": UserText.browserToolSettingsDetailPinTab
        case "searchBookmarks": UserText.browserToolSettingsDetailSearchBookmarks
        case "searchDownloads": UserText.browserToolSettingsDetailSearchDownloads
        case "switchToTab": UserText.browserToolSettingsDetailSwitchToTab
        default: nil
        }
    }
}
