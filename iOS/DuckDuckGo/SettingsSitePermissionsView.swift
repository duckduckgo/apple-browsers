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

    static let supportedPermissionTypes: [SitePermissionType] = [.location, .camera, .microphone]

    @Published private(set) var storedSites = [SitePermissionKey]()
    @Published private var globalDefaults = [SitePermissionType: GlobalSitePermissionDecision]()
    @Published private var siteRecords = [SitePermissionKey: SitePermissionsStore.SitePermissionRecord]()

    private let store: SitePermissionsStore
    private let openSystemSettingsHandler: () -> Void
    private let presentUndoToast: UndoToastPresenter
    private let callbacks: Callbacks

    init(store: SitePermissionsStore,
         openSystemSettings: @escaping () -> Void,
         presentUndoToast: @escaping UndoToastPresenter,
         callbacks: Callbacks) {
        self.store = store
        self.openSystemSettingsHandler = openSystemSettings
        self.presentUndoToast = presentUndoToast
        self.callbacks = callbacks
        refresh()
    }

    convenience init(store: SitePermissionsStore, callbacks: Callbacks) {
        self.init(store: store,
                  openSystemSettings: Self.openSystemSettingsDefault,
                  presentUndoToast: Self.presentUndoToastDefault,
                  callbacks: callbacks)
    }

    func didOpen() {
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
        callbacks.didOpenSystemSettings()
        openSystemSettingsHandler()
    }

    func removePermissions(for site: SitePermissionKey) {
        let snapshot = store.removePermissions(for: site)
        guard !snapshot.isEmpty else { return }
        refresh()
        callbacks.didRequestRevocation(site, Set(Self.supportedPermissionTypes))
        callbacks.didRemoveSite()
        presentUndoToast(String(format: UserText.settingsSitePermissionsRemovedSiteFormat, site.host)) { [weak self] in
            guard let self else { return }
            store.restore(snapshot)
            refresh()
            callbacks.didUndoRemoval()
        }
    }

    func removeAllSitePermissions() {
        let sitesToRevoke = storedSites
        let snapshot = store.clearSitePermissions()
        guard !snapshot.isEmpty else { return }
        refresh()
        sitesToRevoke.forEach {
            callbacks.didRequestRevocation($0, Set(Self.supportedPermissionTypes))
        }
        callbacks.didRemoveAll()
        presentUndoToast(UserText.settingsSitePermissionsRemovedAll) { [weak self] in
            guard let self else { return }
            store.restore(snapshot)
            refresh()
            callbacks.didUndoRemoval()
        }
    }

    private func setGlobalDefault(_ decision: GlobalSitePermissionDecision, for permissionType: SitePermissionType) {
        guard globalDefault(for: permissionType) != decision else { return }
        store.setGlobalDefault(decision, for: permissionType)
        globalDefaults[permissionType] = decision
        callbacks.didChangeGlobalDefault(permissionType, decision)
    }

    private func setSiteDecision(_ decision: SitePermissionDecision,
                                 for permissionType: SitePermissionType,
                                 at site: SitePermissionKey) {
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

    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @StateObject private var viewModel: SettingsSitePermissionsViewModel

    init(viewModel: SettingsSitePermissionsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                ForEach(SettingsSitePermissionsViewModel.supportedPermissionTypes, id: \.self) { permissionType in
                    NavigationLink(destination: globalPicker(for: permissionType)) {
                        SettingsCellView(label: permissionType.settingsTitle,
                                         image: Image(uiImage: permissionType.settingsIcon(for: .ask)),
                                         accessory: .rightDetail(viewModel.globalDefault(for: permissionType).settingsTitle))
                    }
                    .accessibilityValue(viewModel.globalDefault(for: permissionType).settingsTitle)
                    .accessibilityIdentifier("Settings.SitePermissions.Global.\(permissionType.rawValue)")
                    .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
                }
            } header: {
                sectionHeader(UserText.sitePermissions)
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
                    }
                } header: {
                    sectionHeader(UserText.settingsSitePermissionsManageSites)
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
        .applySettingsListModifiers(title: UserText.sitePermissions, displayMode: .inline, viewModel: settingsViewModel)
        .onFirstAppear {
            viewModel.didOpen()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .daxHeadline()
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .textCase(nil)
    }

    private func globalPicker(for permissionType: SitePermissionType) -> some View {
        ListBasedPicker(
            title: permissionType.settingsTitle,
            options: GlobalSitePermissionDecision.allCases,
            selectedOption: viewModel.globalDefaultBinding(for: permissionType),
            descriptionForOption: { $0.settingsTitle },
            sectionHeader: permissionType.settingsTitle
        )
        .applySettingsListModifiers(title: "", displayMode: .inline, viewModel: settingsViewModel)
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
                    NavigationLink(destination: sitePicker(for: permissionType)) {
                        SettingsCellView(label: permissionType.settingsTitle,
                                         accessory: .rightDetail(viewModel.siteDecision(for: permissionType, at: site).settingsTitle))
                    }
                    .accessibilityValue(viewModel.siteDecision(for: permissionType, at: site).settingsTitle)
                    .accessibilityIdentifier("Settings.SitePermissions.Site.\(permissionType.rawValue)")
                    .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
                }
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
        .applySettingsListModifiers(title: pageTitle, displayMode: .inline, viewModel: settingsViewModel)
    }

    private var pageTitle: String {
        String(format: UserText.settingsSitePermissionsSiteHeaderFormat, site.host)
    }

    private func sitePicker(for permissionType: SitePermissionType) -> some View {
        ListBasedPicker(
            title: permissionType.settingsTitle,
            options: SitePermissionDecision.allCases,
            selectedOption: viewModel.siteDecisionBinding(for: permissionType, at: site),
            descriptionForOption: { $0.settingsTitle },
            iconProvider: { decision in
                Image(uiImage: permissionType.settingsIcon(for: decision))
            },
            sectionHeader: permissionType.settingsTitle
        )
        .applySettingsListModifiers(title: "", displayMode: .inline, viewModel: settingsViewModel)
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

    func settingsIcon(for decision: SitePermissionDecision) -> DesignSystemImage {
        switch (self, decision) {
        case (.camera, .ask):
            return DesignSystemImages.Glyphs.Size24.video
        case (.camera, .allow):
            return DesignSystemImages.Glyphs.Size24.videoSolid
        case (.camera, .deny):
            return DesignSystemImages.Glyphs.Size24.videoBlocked
        case (.microphone, .ask):
            return DesignSystemImages.Glyphs.Size24.microphone
        case (.microphone, .allow):
            return DesignSystemImages.Glyphs.Size24.microphoneSolid
        case (.microphone, .deny):
            return DesignSystemImages.Glyphs.Size24.microphoneBlocked
        case (.location, .ask):
            return DesignSystemImages.Glyphs.Size24.location
        case (.location, .allow):
            return DesignSystemImages.Glyphs.Size24.locationSolid
        case (.location, .deny):
            return DesignSystemImages.Glyphs.Size24.locationBlocked
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
