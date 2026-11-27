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
import PixelKit
import PrivacyConfig
import PreferencesUI_macOS
import SwiftUI

@MainActor
final class BrowserToolPermissionsPreferences: ObservableObject {

    struct Row: Identifiable, Equatable {
        let name: String
        let defaultState: BrowserToolPermissionState
        let asksEveryTime: Bool
        var id: String { name }
    }

    static let order = ["readTabContent", "listOpenTabs", "findInPage", "searchHistory", "bookmarkTab", "closeTabs",
                        "highlightInPage", "openTab", "pinTab", "searchBookmarks", "searchDownloads", "switchToTab"]

    @Published private(set) var rows: [Row] = []
    @Published private(set) var storedStates: [String: BrowserToolPermissionState] = [:]
    @Published private(set) var translateMode: TranslatePagesMode = .alwaysAsk
    @Published private(set) var translateExcludedLanguages: [String] = []
    @Published private(set) var isTranslateCustomized = false
    @Published private(set) var showsTranslateRow = false

    private let catalog: BrowserToolCatalog
    private let permissions: BrowserToolPermissionStoring
    private let source: BrowserToolsPixel.PermissionSource
    private let pixelFiring: PixelFiring?
    private let translatePages: TranslatePagesSetting
    private let featureFlagger: FeatureFlagger
    private var permissionChanges: AnyCancellable?
    private var translateChanges: AnyCancellable?
    private var featureFlagChanges: AnyCancellable?

    init(catalog: BrowserToolCatalog = NSApp.delegateTyped.aiChatBrowserToolsService.catalog,
         permissions: BrowserToolPermissionStoring = NSApp.delegateTyped.aiChatBrowserToolsService.permissions,
         permissionManager: PermissionManagerProtocol = NSApp.delegateTyped.permissionManager,
         source: BrowserToolsPixel.PermissionSource = .settings,
         pixelFiring: PixelFiring? = PixelKit.shared,
         translatePages: TranslatePagesSetting = TranslatePagesSetting(),
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.catalog = catalog
        self.permissions = permissions
        self.source = source
        self.pixelFiring = pixelFiring
        self.translatePages = translatePages
        self.featureFlagger = featureFlagger
        featureFlagChanges = featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
        translateChanges = translatePages.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
        // Every write, removal and burn, not only prompt answers.
        permissionChanges = permissionManager.persistedPermissionsPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
        reload()
    }

    func reload() {
        rows = catalog.enabledTools
            .sorted { (Self.order.firstIndex(of: $0.name) ?? .max) < (Self.order.firstIndex(of: $1.name) ?? .max) }
            .map { Row(name: $0.name, defaultState: $0.permissionMode.defaultState, asksEveryTime: $0.asksEveryTime) }
        storedStates = permissions.storedDecisions
        showsTranslateRow = featureFlagger.isFeatureOn(.aiChatOfferTranslationAndSummarize)
        translateMode = translatePages.mode
        translateExcludedLanguages = translatePages.excludedLanguageCodes
        isTranslateCustomized = translatePages.isCustomized
    }

    func setTranslateMode(_ mode: TranslatePagesMode) {
        translatePages.mode = mode
        reload()
    }

    func setTranslate(languageCode: String, excluded: Bool) {
        if excluded {
            translatePages.exclude(languageCode: languageCode)
        } else {
            translatePages.include(languageCode: languageCode)
        }
        reload()
    }

    func resetTranslate() {
        translatePages.reset()
        reload()
    }

    func state(of row: Row) -> BrowserToolPermissionState {
        let state = storedStates[row.name] ?? row.defaultState
        return row.asksEveryTime && state == .allow ? .ask : state
    }

    func setState(_ state: BrowserToolPermissionState, of row: Row) {
        let previous = self.state(of: row)
        permissions.setState(state == row.defaultState ? nil : state, forToolNamed: row.name)
        reload()
        firePermissionChanged(row, from: previous)
    }

    func reset(_ row: Row) {
        let previous = state(of: row)
        permissions.setState(nil, forToolNamed: row.name)
        reload()
        firePermissionChanged(row, from: previous)
    }

    func resetAll() {
        let hadStoredPermissions = rows.contains { storedStates[$0.name] != nil }
        permissions.clearAll()
        // Read live, not the cached row state, which lags a flag update by a main-queue hop.
        // A hidden row keeps its opt-outs, so a flag rollback and re-enable does not lose them.
        if featureFlagger.isFeatureOn(.aiChatOfferTranslationAndSummarize) {
            translatePages.reset()
        }
        reload()
        if hadStoredPermissions {
            pixelFiring?.fire(BrowserToolsPixel.permissionsReset)
        }
    }

    private func firePermissionChanged(_ row: Row, from previous: BrowserToolPermissionState) {
        let current = state(of: row)
        guard current != previous, let tool = BrowserToolsPixel.toolSlugs[row.name] else { return }
        pixelFiring?.fire(BrowserToolsPixel.permissionChanged(tool: tool, from: previous, to: current, source: source))
    }

    var canResetAll: Bool {
        rows.contains { storedStates[$0.name] != nil } || (showsTranslateRow && isTranslateCustomized)
    }
}

struct PreferencesBrowserToolPermissionsView: View {

    @StateObject private var model = BrowserToolPermissionsPreferences()

    var body: some View {
        if !model.rows.isEmpty || model.showsTranslateRow {
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
                        if model.showsTranslateRow {
                            if !model.rows.isEmpty {
                                WebsitePermissionListSeparator()
                            }
                            TranslatePagesRow(model: model)
                        }
                    }
                }
            }
            .id(PreferencesScrollAnchor.browserToolPermissions)
            .onAppear(perform: model.reload)
        }
    }
}

struct BrowserToolPermissionsPanelView: View {

    @StateObject private var model: BrowserToolPermissionsPreferences
    // Tools changed from their default when the panel opened. One set back from the dropdown
    // stays until the panel closes, so it can be changed again; Reset removes it at once.
    @State private var shownTools: Set<String>
    private let openSettings: () -> Void

    @MainActor
    init(model: BrowserToolPermissionsPreferences? = nil, openSettings: @escaping () -> Void) {
        let model = model ?? BrowserToolPermissionsPreferences(source: .panel)
        _model = StateObject(wrappedValue: model)
        _shownTools = State(initialValue: Set(model.storedStates.keys))
        self.openSettings = openSettings
    }

    private var rows: [BrowserToolPermissionsPreferences.Row] {
        model.rows.filter { shownTools.contains($0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UserText.browserToolSettingsTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))

            if rows.isEmpty {
                Text(UserText.browserToolPanelAllDefault)
                    .font(.system(size: 12))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                PreferencesWebsitePermissionListContainer {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                WebsitePermissionListSeparator()
                            }
                            BrowserToolPermissionRow(row: row, model: model, showsDetail: false) {
                                shownTools.remove(row.name)
                            }
                        }
                    }
                }
            }

            scopeNote
        }
        .padding(16)
        .frame(width: 420)
    }

    private var scopeNote: some View {
        var link = AttributedString(UserText.browserToolPanelManageInSettings)
        link.link = URL(string: "about:settings")
        return Text(AttributedString(UserText.browserToolPanelScope + " ") + link)
            .font(.system(size: 12))
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { _ in
                openSettings()
                return .handled
            })
    }
}

struct BrowserToolPermissionRow: View {

    let row: BrowserToolPermissionsPreferences.Row
    @ObservedObject var model: BrowserToolPermissionsPreferences
    var showsDetail = true
    var onReset: (() -> Void)?

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
                    .help(showsDetail ? "" : BrowserToolSettingsText.detail(toolName: row.name) ?? "")
                if showsDetail, let detail = BrowserToolSettingsText.detail(toolName: row.name) {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)

            NSPopUpButtonView(selection: Binding(get: { model.state(of: row) }, set: { model.setState($0, of: row) })) {
                let button = BrowserToolStatePopUpButton()
                for state in Self.states where !(row.asksEveryTime && state == .allow) {
                    button.menu?.addItem(withTitle: Self.title(for: state), action: nil, keyEquivalent: "").representedObject = state
                }
                return button
            }
            .fixedSize()
            .accessibilityLabel(BrowserToolSettingsText.title(toolName: row.name))
            .accessibilityIdentifier("Preferences.AIChat.browserToolPermissions.\(row.name)")

            Button {
                model.reset(row)
                onReset?()
            } label: {
                Image(nsImage: DesignSystemImages.Glyphs.Size12.replay)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .disabled(model.storedStates[row.name] == nil)
            .opacity(model.storedStates[row.name] == nil ? 0.4 : 1)
            .help(UserText.browserToolSettingsReset)
            .accessibilityLabel(UserText.browserToolSettingsReset(toolName: BrowserToolSettingsText.title(toolName: row.name)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    fileprivate static func title(for state: BrowserToolPermissionState) -> String {
        switch state {
        case .ask: UserText.permissionCenterAlwaysAsk
        case .allow: UserText.permissionCenterAlwaysAllow
        case .deny: UserText.permissionCenterNeverAllow
        }
    }
}

struct TranslatePagesRow: View {

    @ObservedObject var model: BrowserToolPermissionsPreferences

    private var systemCode: String? { TranslatePagesLanguages.systemCode() }

    private var summary: String {
        TranslatePagesLanguages.summary(excluded: model.translateExcludedLanguages, systemCode: systemCode)
    }

    private var languageMenu: some View {
        Menu {
            if let systemCode, let name = TranslatePagesLanguages.name(of: systemCode) {
                Toggle(isOn: .constant(true)) {
                    Text(verbatim: "\(name)  \(UserText.translatePagesSettingsSystemLanguage)")
                }
                .disabled(true)
                Divider()
            }
            ForEach(TranslatePagesLanguages.menuCodes(excluded: model.translateExcludedLanguages, systemCode: systemCode), id: \.self) { code in
                Toggle(isOn: Binding(
                    get: { model.translateExcludedLanguages.contains(code) },
                    set: { model.setTranslate(languageCode: code, excluded: $0) })) {
                    Text(verbatim: TranslatePagesLanguages.name(of: code) ?? code)
                }
            }
        } label: {
            Text(summary)
                .font(.system(size: 11))
                .foregroundColor(Color(designSystemColor: .accentTextPrimary))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .accessibilityIdentifier("Preferences.AIChat.translatePages.languages")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.translate)
                .renderingMode(.template)
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundColor(Color(designSystemColor: .iconsPrimary))

            VStack(alignment: .leading, spacing: 2) {
                Text(UserText.translatePagesSettingsTitle)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                HStack(spacing: 3) {
                    Text(UserText.translatePagesSettingsDetailPrefix)
                        .font(.system(size: 11))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                    languageMenu
                }
            }

            Spacer(minLength: 10)

            NSPopUpButtonView(selection: Binding(get: { model.translateMode }, set: { model.setTranslateMode($0) })) {
                let button = BrowserToolStatePopUpButton()
                for mode in TranslatePagesMode.allCases {
                    button.menu?.addItem(withTitle: Self.title(for: mode), action: nil, keyEquivalent: "").representedObject = mode
                }
                return button
            }
            .fixedSize()
            .accessibilityLabel(UserText.translatePagesSettingsTitle)
            .accessibilityIdentifier("Preferences.AIChat.translatePages")

            Button(action: model.resetTranslate) {
                Image(nsImage: DesignSystemImages.Glyphs.Size12.replay)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .disabled(!model.isTranslateCustomized)
            .opacity(model.isTranslateCustomized ? 1 : 0.4)
            .help(UserText.browserToolSettingsReset)
            .accessibilityLabel(UserText.browserToolSettingsReset(toolName: UserText.translatePagesSettingsTitle))
            .accessibilityIdentifier("Preferences.AIChat.translatePages.reset")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private static func title(for mode: TranslatePagesMode) -> String {
        switch mode {
        case .alwaysAsk: UserText.translatePagesSettingsAlwaysAsk
        case .neverAsk: UserText.translatePagesSettingsNeverAsk
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

/// As wide as the longest option, so rows that leave out Allow line up with the rest.
private final class BrowserToolStatePopUpButton: NSPopUpButton {

    private static let width: CGFloat = {
        let button = NSPopUpButton()
        button.addItems(withTitles: [BrowserToolPermissionState.ask, .allow, .deny].map(BrowserToolPermissionRow.title(for:)))
        return button.intrinsicContentSize.width
    }()

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: super.intrinsicContentSize.height)
    }
}
