//
//  SimplifiedSyncSettingsView.swift
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

import DesignResourcesKitIcons
import DuckUI
import SwiftUI

public struct SimplifiedSyncSettingsView: View {

    @ObservedObject public var model: SyncSettingsViewModel

    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    @State var selectedDevice: SyncSettingsViewModel.Device?
    @State var isEnvironmentSwitcherInstructionsVisible = false

    public init(model: SyncSettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        List {
            if model.isSyncEnabled {
                syncEnabledContent
            } else {
                syncDisabledContent
            }
        }
        .navigationTitle(UserText.syncTitle)
        .applyListStyle()
        .environmentObject(model)
        .alert(isPresented: $model.shouldShowPasscodeRequiredAlert) {
            Alert(
                title: Text(UserText.syncPasscodeRequiredAlertTitle),
                message: Text(UserText.syncPasscodeRequiredAlertMessage),
                dismissButton: .default(Text(UserText.syncPasscodeRequiredAlertGoToSettingsButton), action: {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    model.shouldShowPasscodeRequiredAlert = false
                })
            )
        }
        .sheet(item: $selectedDevice) { device in
            Group {
                if device.isThisDevice {
                    EditDeviceView(model: model.createEditDeviceModel(device))
                } else {
                    RemoveDeviceView(model: model.createRemoveDeviceModel(device))
                }
            }
            .modifier {
                if #available(iOS 16.0, *) {
                    $0.presentationDetents([.medium])
                } else {
                    $0
                }
            }
        }
    }
}

// MARK: - Sync Disabled Content

extension SimplifiedSyncSettingsView {

    @ViewBuilder
    var syncDisabledContent: some View {
        syncUnavailableViewWhileLoggedOut
        headerSection
        syncToggleSection
        alreadySetUpSection
        getDesktopBrowserSection(source: .notActivated)
    }

    @ViewBuilder
    var syncUnavailableViewWhileLoggedOut: some View {
        if !model.isDataSyncingAvailable || !model.isConnectingDevicesAvailable || !model.isAccountCreationAvailable {
            if model.isAppVersionNotSupported {
                SyncWarningMessageView(title: UserText.syncUnavailableTitle, message: UserText.syncUnavailableMessageUpgradeRequired)
            } else {
                SyncWarningMessageView(title: UserText.syncUnavailableTitle, message: UserText.syncUnavailableMessage)
            }
        }
    }

    @ViewBuilder
    var headerSection: some View {
        Section {
            VStack(spacing: 20) {
                Image(model.isSyncEnabled ? "Sync-Pair-96" : "Sync-New-128")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 96)
                    .padding(.top, -16)

                if model.isSyncEnabled {
                    Button(action: model.scanQRCode) {
                        HStack(spacing: 8) {
                            Image(uiImage: DesignSystemImages.Glyphs.Size16.qr)
                            Text(UserText.simplifiedSyncAnotherDeviceButton)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(disabled: !model.isConnectingDevicesAvailable, compact: true, fullWidth: false))
                    .disabled(!model.isConnectingDevicesAvailable)
                    .padding(.vertical, 10)
                } else {
                    Text(model.isAIChatSyncEnabled ? UserText.simplifiedSyncHeaderMessage : UserText.simplifiedSyncHeaderMessageBasic)
                        .daxBodyRegular()
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
            }
            .frame(maxWidth: .infinity)
        } header: {
            devEnvironmentIndicator
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color(designSystemColor: .background))
    }

    @ViewBuilder
    var devEnvironmentIndicator: some View {
        if model.isOnDevEnvironment {
            Button(action: {
                isEnvironmentSwitcherInstructionsVisible.toggle()
            }, label: {
                Text("Dev environment")
                    .daxFootnoteRegular()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .foregroundColor(.white)
                    .background(Color(baseColor: .red40))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            })
            .alert(isPresented: $isEnvironmentSwitcherInstructionsVisible) {
                Alert(
                    title: Text("You're using Sync Development environment"),
                    primaryButton: .default(Text("Keep Development")),
                    secondaryButton: .destructive(Text("Switch to Production"), action: model.switchToProdEnvironment)
                )
            }
        }
    }

    @ViewBuilder
    var syncToggleSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.isSyncEnabled },
                set: { _ in
                    // To be implemented
                }
            )) {
                Text(UserText.simplifiedSyncToggleTitle)
                    .daxBodyRegular()
            }
            .disabled(!model.isSyncEnabled && !model.isAccountCreationAvailable)
        }
    }

    @ViewBuilder
    var alreadySetUpSection: some View {
        Section {
            Button {
                model.scanQRCode()
            } label: {
                Label(title: {
                    Text(UserText.simplifiedSyncWithAnotherDeviceButton)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .accent))
                }, icon: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.qr)
                        .foregroundColor(Color(designSystemColor: .accent))
                })
            }
            .disabled(!model.isAccountCreationAvailable)

            Button {
                model.beginRecoverFlow()
            } label: {
                Label(title: {
                    Text(UserText.simplifiedUseRecoveryCodeButton)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .accent))
                }, icon: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.note)
                        .foregroundColor(Color(designSystemColor: .accent))
                })
            }
            .sheet(isPresented: $model.isRecoverSyncedDataSheetVisible) {
                RecoverSyncedDataView(model: model, onCancel: {
                    model.isRecoverSyncedDataSheetVisible = false
                })
            }
            .disabled(!model.isAccountRecoveryAvailable)
        } header: {
            Text(UserText.simplifiedAlreadySetUpSectionHeader)
        }
    }

    @ViewBuilder
    func getDesktopBrowserSection(source: SyncSettingsViewModel.PlatformLinksPixelSource) -> some View {
        Section {
            NavigationLink(destination: PlatformLinksView(model: model, source: source)) {
                Label(title: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UserText.simplifiedGetDesktopBrowserTitle)
                            .daxBodyRegular()
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                        Text(UserText.simplifiedGetDesktopBrowserSubtitle)
                            .daxFootnoteRegular()
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                    }
                }, icon: {
                    Image(uiImage: DesignSystemImages.Color.Size24.deviceLaptopInstall)
                })
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Sync Enabled Content

extension SimplifiedSyncSettingsView {

    @ViewBuilder
    var syncEnabledContent: some View {
        syncUnavailableViewWhileLoggedIn
        syncPausedBanners
        headerSection
        syncToggleSection
        syncedDevicesSection
        getDesktopBrowserSection(source: .activated)
        bookmarksSection
        recoverySection
        deleteSection
    }

    @ViewBuilder
    var syncUnavailableViewWhileLoggedIn: some View {
        if !model.isDataSyncingAvailable {
            if model.isAppVersionNotSupported {
                SyncWarningMessageView(title: UserText.syncUnavailableTitle, message: UserText.syncUnavailableMessageUpgradeRequired)
            } else {
                SyncWarningMessageView(title: UserText.syncUnavailableTitle, message: UserText.syncUnavailableMessage)
            }
        }
    }

    @ViewBuilder
    var syncPausedBanners: some View {
        if model.isSyncPaused, let title = model.syncPausedTitle, let message = model.syncPausedDescription {
            SyncWarningMessageView(title: title, message: message)
        }
        if model.isSyncBookmarksPaused {
            syncPausedBanner(
                title: model.syncBookmarksPausedTitle,
                description: model.syncBookmarksPausedDescription,
                buttonTitle: model.syncBookmarksPausedButtonTitle,
                action: model.manageBookmarks
            )
        }
        if model.isSyncCredentialsPaused {
            syncPausedBanner(
                title: model.syncCredentialsPausedTitle,
                description: model.syncCredentialsPausedDescription,
                buttonTitle: model.syncCredentialsPausedButtonTitle,
                action: model.manageLogins
            )
        }
        if model.isSyncCreditCardsPaused {
            syncPausedBanner(
                title: model.syncCreditCardsPausedTitle,
                description: model.syncCreditCardsPausedDescription,
                buttonTitle: model.syncCreditCardsPausedButtonTitle,
                action: model.manageCreditCards
            )
        }
        if !model.invalidBookmarksTitles.isEmpty {
            invalidItemsBanner(
                title: UserText.invalidBookmarksPresentTitle,
                description: UserText.invalidBookmarksPresentDescription(
                    model.invalidBookmarksTitles.first ?? "",
                    numberOfOtherInvalidItems: model.invalidBookmarksTitles.count - 1
                ),
                actionTitle: UserText.bookmarksLimitExceededAction,
                action: model.manageBookmarks
            )
        }
        if !model.invalidCredentialsTitles.isEmpty {
            invalidItemsBanner(
                title: UserText.invalidCredentialsPresentTitle,
                description: UserText.invalidCredentialsPresentDescription(
                    model.invalidCredentialsTitles.first ?? "",
                    numberOfOtherInvalidItems: model.invalidCredentialsTitles.count - 1
                ),
                actionTitle: UserText.credentialsLimitExceededAction,
                action: model.manageLogins
            )
        }
        if !model.invalidCreditCardsTitles.isEmpty {
            invalidItemsBanner(
                title: UserText.invalidCreditCardsPresentTitle,
                description: UserText.invalidCreditCardsPresentDescription(
                    model.invalidCreditCardsTitles.first ?? "",
                    numberOfOtherInvalidItems: model.invalidCreditCardsTitles.count - 1
                ),
                actionTitle: UserText.creditCardsLimitExceededAction,
                action: model.manageCreditCards
            )
        }
    }

    @ViewBuilder
    func syncPausedBanner(title: String?, description: String?, buttonTitle: String?, action: @escaping () -> Void) -> some View {
        if let title, let description, let buttonTitle {
            SyncWarningMessageView(title: title, message: description, buttonTitle: buttonTitle, buttonAction: action)
        }
    }

    @ViewBuilder
    func invalidItemsBanner(title: String, description: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        SyncWarningMessageView(title: title, message: description, buttonTitle: actionTitle, buttonAction: action)
    }

    // MARK: Devices

    @ViewBuilder
    var syncedDevicesSection: some View {
        Section {
            if model.devices.isEmpty {
                ProgressView()
            }
            devicesList
        } header: {
            HStack {
                Text(UserText.syncedDevicesSectionHeader)
                Circle()
                    .fill(Color(designSystemColor: .alertGreen))
                    .frame(width: 8)
            }
        }
        .onReceive(timer) { _ in
            if selectedDevice == nil {
                model.delegate?.refreshDevices(clearDevices: false)
            }
        }
    }

    @ViewBuilder
    var devicesList: some View {
        ForEach(model.devices) { device in
            Button {
                selectedDevice = device
            } label: {
                HStack {
                    deviceTypeImage(device)
                        .foregroundColor(.primary)
                    Text(device.name)
                        .foregroundColor(.primary)
                    Spacer()
                    if device.isThisDevice {
                        Text(UserText.syncedDevicesThisDeviceLabel)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .accessibility(identifier: "device")
        }
    }

    @ViewBuilder
    func deviceTypeImage(_ device: SyncSettingsViewModel.Device) -> some View {
        switch device.type {
        case "desktop":
            Image(uiImage: DesignSystemImages.Glyphs.Size24.deviceDesktop)
        case "tablet":
            Image(uiImage: DesignSystemImages.Glyphs.Size24.deviceTablet)
        default:
            Image(uiImage: DesignSystemImages.Glyphs.Size24.deviceMobile)
        }
    }

    // MARK: Bookmarks

    @ViewBuilder
    var bookmarksSection: some View {
        Section {
            Toggle(isOn: $model.isUnifiedFavoritesEnabled) {
                Text(UserText.unifiedFavoritesTitle)
                    .daxBodyRegular()
            }
            .accessibility(identifier: "UnifiedFavoritesToggle")

            Toggle(isOn: $model.isFaviconsFetchingEnabled) {
                Text(UserText.fetchFaviconsOptionTitle)
                    .daxBodyRegular()
            }
            .accessibility(identifier: "FaviconFetchingToggle")
        } header: {
            Text(UserText.simplifiedBookmarksSectionHeader)
        } footer: {
            Text(LocalizedStringKey(String(format: UserText.simplifiedBookmarksSectionFooterFormat, "https://duckduckgo.com/duckduckgo-help-pages/sync-and-backup/syncing-favorites")))
                .tint(Color(designSystemColor: .accent))
        }
        .onAppear {
            model.delegate?.updateOptions()
        }
    }

    // MARK: Recovery

    @ViewBuilder
    var recoverySection: some View {
        Section {
            if model.isAutoRestoreFeatureAvailable {
                NavigationLink(destination: AutoRestoreSettingsView(model: model)) {
                    HStack {
                        Text(UserText.autoRestoreSettingsRowLabel)
                            .daxBodyRegular()
                            .foregroundColor(.primary)
                        Spacer()
                        Text(model.autoRestoreStatusText)
                            .daxBodyRegular()
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                model.saveRecoveryPDF()
            } label: {
                Text(UserText.simplifiedDownloadRecoveryCodeButton)
                    .foregroundColor(Color(designSystemColor: .accent))
            }

            Button {
                model.copyCode()
            } label: {
                Text(UserText.simplifiedCopyRecoveryCodeButton)
                    .foregroundColor(Color(designSystemColor: .accent))
            }
        } header: {
            Text(UserText.recoverySectionHeader)
        } footer: {
            Text(UserText.simplifiedRecoverySectionFooter)
        }
    }

    // MARK: Delete

    @ViewBuilder
    var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                model.deleteAllData()
            } label: {
                Text(UserText.simplifiedDeleteSyncDataButton)
            }
        }
    }
}
