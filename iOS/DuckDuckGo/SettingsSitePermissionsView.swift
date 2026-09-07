//
//  SettingsSitePermissionsView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import Persistence
import SitePermissions
import SwiftUI
import UIKit

@MainActor
final class SettingsSitePermissionsViewModel: ObservableObject {

    struct Callbacks {
        var didOpen: () -> Void = {}
        var didChangeGlobalDefault: (SitePermissionType, GlobalSitePermissionDecision) -> Void = { _, _ in }
        var didChangeSiteDecision: (SitePermissionType, SitePermissionDecision, SitePermissionDecision) -> Void = { _, _, _ in }
        var didOpenSystemSettings: () -> Void = {}
        var didRequestRevocation: (SitePermissionKey, Set<SitePermissionType>) -> Void = { _, _ in }
        var didRemoveSite: () -> Void = {}
        var didRemoveAll: () -> Void = {}
        var didUndoRemoval: () -> Void = {}
    }

    typealias UndoToastPresenter = (_ message: String, _ undo: @escaping () -> Void) -> Void

    static let supportedPermissionTypes: [SitePermissionType] = [.camera, .microphone]

    @Published private(set) var storedSites = [SitePermissionKey]()
    @Published private var globalDefaults = [SitePermissionType: GlobalSitePermissionDecision]()
    @Published private var siteRecords = [SitePermissionKey: SitePermissionsStore.SitePermissionRecord]()

    private let store: SitePermissionsStore
    private let isEnabled: () -> Bool
    private let openSystemSettingsHandler: () -> Void
    private let presentUndoToast: UndoToastPresenter
    private let callbacks: Callbacks

    init(store: SitePermissionsStore,
         isEnabled: @escaping () -> Bool,
         openSystemSettings: @escaping () -> Void,
         presentUndoToast: @escaping UndoToastPresenter,
         callbacks: Callbacks) {
        self.store = store
        self.isEnabled = isEnabled
        self.openSystemSettingsHandler = openSystemSettings
        self.presentUndoToast = presentUndoToast
        self.callbacks = callbacks
        refresh()
    }

    convenience init(store: SitePermissionsStore, isEnabled: @escaping () -> Bool, callbacks: Callbacks) {
        self.init(store: store,
                  isEnabled: isEnabled,
                  openSystemSettings: Self.openSystemSettingsDefault,
                  presentUndoToast: Self.presentUndoToastDefault,
                  callbacks: callbacks)
    }

    func didOpen() {
        guard isEnabled() else { return }
        refresh()
        callbacks.didOpen()
    }

    func globalDefault(for permissionType: SitePermissionType) -> GlobalSitePermissionDecision {
        globalDefaults[permissionType] ?? .ask
    }

    func siteDecision(for permissionType: SitePermissionType, at site: SitePermissionKey) -> SitePermissionDecision {
        siteRecords[site]?[permissionType] ?? .ask
    }

    func globalDefaultBinding(for permissionType: SitePermissionType) -> Binding<GlobalSitePermissionDecision> {
        Binding(
            get: { self.globalDefault(for: permissionType) },
            set: { self.setGlobalDefault($0, for: permissionType) })
    }

    func siteDecisionBinding(for permissionType: SitePermissionType,
                             at site: SitePermissionKey) -> Binding<SitePermissionDecision> {
        Binding(
            get: { self.siteDecision(for: permissionType, at: site) },
            set: { self.setSiteDecision($0, for: permissionType, at: site) })
    }

    func openSystemSettings() {
        guard isEnabled() else { return }
        callbacks.didOpenSystemSettings()
        openSystemSettingsHandler()
    }

    func removePermissions(for site: SitePermissionKey) {
        guard isEnabled() else { return }
        let snapshot = store.removePermissions(for: site)
        guard !snapshot.isEmpty else { return }
        refresh()
        callbacks.didRequestRevocation(site, Set(Self.supportedPermissionTypes))
        callbacks.didRemoveSite()
        presentUndoToast(
            String(format: UserText.settingsSitePermissionsRemovedSiteFormat, site.host)) { [weak self, store, callbacks, isEnabled] in
            store.restore(snapshot)
            self?.refresh()
            if isEnabled() {
                callbacks.didUndoRemoval()
            }
        }
    }

    func removeAllSitePermissions() {
        guard isEnabled() else { return }
        let sitesToRevoke = storedSites
        let snapshot = store.clearSitePermissions()
        guard !snapshot.isEmpty else { return }
        refresh()
        sitesToRevoke.forEach {
            callbacks.didRequestRevocation($0, Set(Self.supportedPermissionTypes))
        }
        callbacks.didRemoveAll()
        presentUndoToast(UserText.settingsSitePermissionsRemovedAll) { [weak self, store, callbacks, isEnabled] in
            store.restore(snapshot)
            self?.refresh()
            if isEnabled() {
                callbacks.didUndoRemoval()
            }
        }
    }

    private func setGlobalDefault(_ decision: GlobalSitePermissionDecision, for permissionType: SitePermissionType) {
        guard isEnabled() else { return }
        guard globalDefault(for: permissionType) != decision else { return }
        store.setGlobalDefault(decision, for: permissionType)
        globalDefaults[permissionType] = decision
        callbacks.didChangeGlobalDefault(permissionType, decision)
    }

    private func setSiteDecision(_ decision: SitePermissionDecision,
                                 for permissionType: SitePermissionType,
                                 at site: SitePermissionKey) {
        guard isEnabled() else { return }
        let previousDecision = siteDecision(for: permissionType, at: site)
        guard previousDecision != decision else { return }

        if decision == .ask {
            store.resetDecision(for: permissionType, at: site)
        } else {
            store.setPersistentDecision(decision, for: permissionType, at: site)
        }
        refresh()
        if decision == .deny {
            callbacks.didRequestRevocation(site, [permissionType])
        }
        callbacks.didChangeSiteDecision(permissionType, previousDecision, decision)
    }

    private func refresh() {
        globalDefaults = Dictionary(uniqueKeysWithValues: Self.supportedPermissionTypes.map {
            ($0, store.globalDefault(for: $0))
        })
        storedSites = store.storedSites.sorted {
            $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
        }
        siteRecords = Dictionary(uniqueKeysWithValues: storedSites.map { ($0, store.permissions(for: $0)) })
    }

    private static func openSystemSettingsDefault() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func presentUndoToastDefault(message: String, undo: @escaping () -> Void) {
        ActionMessageView.present(message: message,
                                  actionTitle: UserText.actionGenericUndo,
                                  presentationLocation: .withoutBottomBar,
                                  onAction: undo)
    }
}

@MainActor
struct SettingsSitePermissionsView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @StateObject private var viewModel: SettingsSitePermissionsViewModel

    init(viewModel: SettingsSitePermissionsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                ForEach(SettingsSitePermissionsViewModel.supportedPermissionTypes, id: \.self) { permissionType in
                    SettingsSitePermissionRow(
                        permissionType: permissionType,
                        selection: viewModel.globalDefault(for: permissionType).settingsTitle,
                        accessibilityIdentifier: "Settings.SitePermissions.Global.\(permissionType.rawValue)") {
                        Picker(permissionType.settingsTitle, selection: viewModel.globalDefaultBinding(for: permissionType)) {
                            ForEach(GlobalSitePermissionDecision.allCases, id: \.self) { decision in
                                Text(decision.settingsTitle).tag(decision)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
                }
            } header: {
                Text(UserText.sitePermissions)
                    .font(.body.weight(.semibold))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .textCase(nil)
            } footer: {
                Text(systemSettingsFooter)
                    .environment(\.openURL, OpenURLAction { url in
                        guard SettingsSitePermissionsFooterAction.from(url) == .systemSettings else { return .systemAction }
                        viewModel.openSystemSettings()
                        return .handled
                    })
            }

            if !viewModel.storedSites.isEmpty {
                Section {
                    ForEach(viewModel.storedSites, id: \.self) { site in
                        NavigationLink(destination: SettingsSitePermissionsSiteView(site: site, viewModel: viewModel)
                            .environmentObject(settingsViewModel)) {
                            HStack(spacing: 12) {
                                FaviconView(viewModel: FaviconViewModel(domain: site.host))
                                    .frame(width: 24, height: 24)
                                Text(site.host)
                                    .daxBodyRegular()
                                    .foregroundColor(Color(designSystemColor: .textPrimary))
                            }
                        }
                        .accessibilityIdentifier("Settings.SitePermissions.Site.\(site.host)")
                        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(UserText.actionDelete, role: .destructive) {
                                viewModel.removePermissions(for: site)
                            }
                        }
                    }
                } header: {
                    Text(UserText.settingsSitePermissionsManageSites)
                        .font(.body.weight(.semibold))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .textCase(nil)
                }

                Section {
                    Button(UserText.settingsSitePermissionsRemoveAll) {
                        viewModel.removeAllSitePermissions()
                    }
                    .foregroundColor(Color(designSystemColor: .accentPrimary))
                    .accessibilityIdentifier("Settings.SitePermissions.RemoveAll")
                    .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
                }
            }
        }
        .sitePermissionsSectionSpacing()
        .animation(reduceMotion ? nil : .default, value: viewModel.storedSites)
        .applySettingsListModifiers(title: UserText.sitePermissions, displayMode: .inline, viewModel: settingsViewModel)
        .disabled(!settingsViewModel.state.sitePermissionsEnabled)
        .onFirstAppear {
            viewModel.didOpen()
        }
    }

    private var systemSettingsFooter: AttributedString {
        var footer = AttributedString(UserText.settingsSitePermissionsSystemSettingsFooterPrefix)
        var link = AttributedString(UserText.settingsSitePermissionsSystemSettingsLink)
        link.foregroundColor = Color(designSystemColor: .accentPrimary)
        link.link = SettingsSitePermissionsFooterAction.systemSettings.url
        footer.append(link)
        return footer
    }
}

@MainActor
private struct SettingsSitePermissionsSiteView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    let site: SitePermissionKey
    @ObservedObject var viewModel: SettingsSitePermissionsViewModel

    var body: some View {
        List {
            Section {
                ForEach(SettingsSitePermissionsViewModel.supportedPermissionTypes, id: \.self) { permissionType in
                    SettingsSitePermissionRow(
                        permissionType: permissionType,
                        selection: viewModel.siteDecision(for: permissionType, at: site).settingsTitle,
                        accessibilityIdentifier: "Settings.SitePermissions.Site.\(permissionType.rawValue)") {
                        Picker(permissionType.settingsTitle, selection: viewModel.siteDecisionBinding(for: permissionType, at: site)) {
                            ForEach(SitePermissionDecision.allCases, id: \.self) { decision in
                                Text(decision.settingsTitle).tag(decision)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
                }
            } header: {
                Text(String(format: UserText.settingsSitePermissionsSiteHeaderFormat, site.host))
                    .font(.body.weight(.semibold))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .textCase(nil)
            }

            Section {
                Button(UserText.settingsSitePermissionsRemoveSite) {
                    viewModel.removePermissions(for: site)
                    dismiss()
                }
                .foregroundColor(Color(designSystemColor: .accentPrimary))
                .accessibilityIdentifier("Settings.SitePermissions.RemoveSite")
                .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
            }
        }
        .sitePermissionsSectionSpacing()
        .applySettingsListModifiers(title: site.host, displayMode: .inline, viewModel: settingsViewModel)
        .disabled(!settingsViewModel.state.sitePermissionsEnabled)
    }
}

private struct SettingsSitePermissionRow<MenuContent: View>: View {
    let permissionType: SitePermissionType
    let selection: String
    let accessibilityIdentifier: String
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        HStack(spacing: 12) {
            permissionType.settingsIcon
                .font(.title3)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(permissionType.settingsTitle)
                .daxBodyRegular()
                .accessibilityHidden(true)
            Spacer(minLength: 16)
            Menu(content: menuContent) {
                HStack(spacing: 12) {
                    Text(selection)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(permissionType.settingsTitle)
            .accessibilityValue(selection)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .foregroundColor(Color(designSystemColor: .textPrimary))
    }
}

private extension List {
    @ViewBuilder
    func sitePermissionsSectionSpacing() -> some View {
        if #available(iOS 17, *) {
            listSectionSpacing(24)
        } else {
            self
        }
    }
}

private enum SettingsSitePermissionsFooterAction: Equatable {
    static let scheme = "action"

    case systemSettings

    var url: URL {
        URL(string: "\(Self.scheme)://system-settings")!
    }

    static func from(_ url: URL) -> Self? {
        guard url.scheme == scheme, url.host == "system-settings" else { return nil }
        return .systemSettings
    }
}

private extension SitePermissionType {
    var settingsTitle: String {
        switch self {
        case .camera:
            return UserText.settingsSitePermissionsCamera
        case .microphone:
            return UserText.settingsSitePermissionsMicrophone
        case .location:
            return UserText.settingsSitePermissionsLocation
        }
    }

    var settingsIcon: Image {
        switch self {
        case .camera:
            return Image(systemName: "video")
        case .microphone:
            return Image(uiImage: DesignSystemImages.Glyphs.Size24.microphone)
        case .location:
            return Image(uiImage: DesignSystemImages.Glyphs.Size24.location)
        }
    }
}

private extension GlobalSitePermissionDecision {
    var settingsTitle: String {
        switch self {
        case .ask:
            return UserText.settingsSitePermissionsAskEachTime
        case .deny:
            return UserText.settingsSitePermissionsNeverAllow
        }
    }
}

private extension SitePermissionDecision {
    var settingsTitle: String {
        switch self {
        case .ask:
            return UserText.settingsSitePermissionsAskEachTime
        case .allow:
            return UserText.settingsSitePermissionsAlwaysAllow
        case .deny:
            return UserText.settingsSitePermissionsNeverAllow
        }
    }
}
