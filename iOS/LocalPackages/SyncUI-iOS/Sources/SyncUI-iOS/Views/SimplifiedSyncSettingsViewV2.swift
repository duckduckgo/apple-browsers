//
//  SimplifiedSyncSettingsViewV2.swift
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
import UIComponents

// V2 of the Sync & Backup settings screen, gated behind the simplifiedSyncSetupV2 feature
// flag. Started as a copy of SimplifiedSyncSettingsView and is being reshaped for the
// Simplified Sync Setup follow-up redesign; the original stays in place for users off the flag.
// https://app.asana.com/1/137249556945/project/1214200115953388/task/1215960387490701
public struct SimplifiedSyncSettingsViewV2: View {

    @ObservedObject public var model: SyncSettingsViewModel

    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    @State var selectedDevice: SyncSettingsViewModel.Device?
    @State var isEnvironmentSwitcherInstructionsVisible = false

    public init(model: SyncSettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        List {
            syncWarningBanners
            headerSection

            if model.isSyncEnabled {
                syncEnabledSections
            } else {
                syncToggleSection
                syncDisabledSections
            }
        }
        .navigationTitle(UserText.syncTitle)
        .animation(.easeInOut(duration: 0.3), value: model.isSyncEnabled)
        .animation(.easeInOut(duration: 0.3), value: model.devices.isEmpty)
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
        .sheet(item: $model.connectingSheetPhase, onDismiss: {
            model.connectingSheetDidDismiss()
        }, content: {_ in
            SimplifiedConnectingSheetViewV2(model: model)
                .interactiveDismissDisabled()
        })
    }
}

// MARK: - Sync Disabled Content

extension SimplifiedSyncSettingsViewV2 {

    @ViewBuilder
    var syncWarningBanners: some View {
        if model.isSyncEnabled {
            syncUnavailableViewWhileLoggedIn
            syncPausedBanners
        } else {
            syncUnavailableViewWhileLoggedOut
        }
    }

    @ViewBuilder
    var syncDisabledSections: some View {
        recoverSyncedDataSection
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
            VStack(spacing: 8) {
                ZStack {
                    Image(AppRebrand.isAppRebranded() ? "Desktop-Mobile-DDG-Devices-Feature-128" : "Sync-New-128-legacy", bundle: .module)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 128, height: 96)
                        .opacity(model.isSyncEnabled ? 0 : 1)

                    Image(AppRebrand.isAppRebranded() ? "Desktop-Mobile-Sync-Feature-128" : "Sync-Pair-96-legacy", bundle: .module)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 128, height: 96)
                        .opacity(model.isSyncEnabled ? 1 : 0)
                }
                .padding(.top, -16)

                VStack(spacing: 13) {
                    VStack(spacing: 4) {
                        Text(headerTitle)
                            .daxTitle2()
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(designSystemColor: .textPrimary))

                        syncStatusIndicator
                    }

                    Text(headerMessage)
                        .daxBodyRegular()
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)
        } header: {
            devEnvironmentIndicator
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color(designSystemColor: .background))
    }

    var headerTitle: String {
        model.isSyncEnabled ? UserText.simplifiedSyncEnabledHeaderTitle : UserText.simplifiedSyncHeaderTitle
    }

    var headerMessage: String {
        if model.isSyncEnabled {
            return model.isAIChatSyncEnabled ? UserText.simplifiedSyncEnabledHeaderMessage : UserText.simplifiedSyncEnabledHeaderMessageBasic
        } else {
            return model.isAIChatSyncEnabled ? UserText.simplifiedSyncHeaderMessage : UserText.simplifiedSyncHeaderMessageBasic
        }
    }

    @ViewBuilder
    var syncStatusIndicator: some View {
        StatusIndicatorView(
            status: model.isSyncEnabled ? .on : .off,
            text: model.isSyncEnabled ? UserText.simplifiedSyncStatusOn : UserText.simplifiedSyncStatusOff
        )
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
            HStack {
                Text(UserText.simplifiedSyncToggleTitleThisDevice)
                    .daxBodyRegular()
                Spacer()
                if model.isBusy && !model.isSyncEnabled {
                    ProgressView()
                        .transition(.opacity)
                }
                Toggle("", isOn: Binding(
                    get: { model.isSyncEnabled },
                    set: { newValue in
                        if newValue {
                            model.delegate?.fireSyncSetupPixel(event: .backUpThisDeviceTapped)
                            model.enableSyncToggleTapped()
                        } else {
                            model.disableSyncToggleTapped()
                        }
                    }
                ))
                .labelsHidden()
                .tint(Color(designSystemColor: .accentPrimary))
                .accessibilityLabel(UserText.simplifiedSyncToggleTitleThisDevice)
            }
            .animation(.easeInOut(duration: 0.3), value: model.isBusy)
            .disabled(model.isBusy || (!model.isSyncEnabled && !model.isAccountCreationAvailable))

            if !model.isSyncEnabled {
                syncWithAnotherDeviceButton
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    @ViewBuilder
    var syncWithAnotherDeviceButton: some View {
        Button {
            model.scanQRCode()
        } label: {
            HStack(spacing: 8) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.qr)
                    .foregroundColor(Color(designSystemColor: .accentPrimary))
                Text(UserText.simplifiedSyncWithAnotherDeviceButton)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .accentPrimary))
            }
        }
        .disabled(!model.isAccountCreationAvailable)
    }

    @ViewBuilder
    var recoverSyncedDataSection: some View {
        Section {
            Button {
                model.delegate?.fireSyncSetupPixel(event: .recoverSyncedDataTapped)
                model.beginRecoverFlow()
            } label: {
                Text(UserText.simplifiedRecoverSyncedDataButton)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sheet(isPresented: $model.isRecoverSyncedDataSheetVisible) {
                RecoverSyncedDataView(model: model, onCancel: {
                    model.isRecoverSyncedDataSheetVisible = false
                })
            }
            .disabled(!model.isAccountRecoveryAvailable)
        } header: {
            // Top-only gap above this section per the design. A clear header adds space above the
            // card without touching the gap below it — unlike `listSectionSpacing`, which pads both
            // sides of a section. Height is tuned against the canvas.
            Color.clear
                .frame(height: 44)
                .listRowInsets(EdgeInsets())
                .accessibilityHidden(true)
        }
        .listRowBackground(Color(designSystemColor: .surface))
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
        .listRowBackground(Color(designSystemColor: .surface))
    }
}

// MARK: - Sync Enabled Content

extension SimplifiedSyncSettingsViewV2 {

    @ViewBuilder
    var syncEnabledSections: some View {
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
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            devicesList

            if model.isConnectingDevicesAvailable {
                Button {
                    model.scanQRCode()
                } label: {
                    HStack {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.add)
                            .foregroundColor(Color(designSystemColor: .accentPrimary))
                        Text(UserText.simplifiedSyncWithAnotherDeviceButton)
                            .daxBodyRegular()
                            .foregroundColor(Color(designSystemColor: .accentPrimary))
                    }
                }
            }
        } header: {
            Text(UserText.simplifiedMyDevicesSectionHeader)
        }
        .onReceive(timer) { _ in
            if selectedDevice == nil {
                model.delegate?.refreshDevices(clearDevices: false)
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
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
                    disclosureChevron
                }
            }
            .transition(.opacity)
            .accessibility(identifier: "device")
        }
    }

    var disclosureChevron: some View {
        Image(systemName: "chevron.forward")
            .font(Font.system(.footnote).weight(.bold))
            .foregroundColor(Color(UIColor.tertiaryLabel))
    }

    @ViewBuilder
    func deviceTypeImage(_ device: SyncSettingsViewModel.Device) -> some View {
        if device.isThirdParty {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.deviceAll)
        } else {
            switch device.type {
            case "desktop":
                Image(uiImage: DesignSystemImages.Glyphs.Size24.deviceDesktop)
            case "tablet":
                Image(uiImage: DesignSystemImages.Glyphs.Size24.deviceTablet)
            default:
                Image(uiImage: DesignSystemImages.Glyphs.Size24.deviceMobile)
            }
        }
    }

    // MARK: Bookmarks

    @ViewBuilder
    var bookmarksSection: some View {
        Section {
            Toggle(isOn: $model.isUnifiedFavoritesEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UserText.unifiedFavoritesTitle)
                        .daxBodyRegular()
                    Text(UserText.simplifiedBookmarksUnifiedFavoritesCaption)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Color(designSystemColor: .accentPrimary))
            .accessibility(identifier: "UnifiedFavoritesToggle")

            Toggle(isOn: $model.isFaviconsFetchingEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UserText.fetchFaviconsOptionTitle)
                        .daxBodyRegular()
                    Text(UserText.simplifiedBookmarksFetchFaviconsCaption)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Color(designSystemColor: .accentPrimary))
            .accessibility(identifier: "FaviconFetchingToggle")
        } header: {
            Text(UserText.simplifiedBookmarksSectionHeader)
        }
        .onAppear {
            model.delegate?.updateOptions()
        }
        .listRowBackground(Color(designSystemColor: .surface))
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
                HStack {
                    Text(UserText.simplifiedDownloadRecoveryCodeButton)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.downloads)
                        .foregroundColor(Color(designSystemColor: .icons))
                }
            }

            Button {
                model.simplifiedCopyRecoveryCode()
            } label: {
                HStack {
                    Text(UserText.simplifiedCopyRecoveryCodeButton)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.copy)
                        .foregroundColor(Color(designSystemColor: .icons))
                }
            }
        } header: {
            Text(UserText.recoverySectionHeader)
        } footer: {
            Text(LocalizedStringKey(String(format: UserText.simplifiedRecoverySectionFooterFormat, "ddgQuickLink://duckduckgo.com/duckduckgo-help-pages/sync-and-backup/recovery-codes-and-troubleshooting#does-my-sync--backup-data-ever-expire")))
                .tint(Color(designSystemColor: .accentPrimary))
        }
        .listRowBackground(Color(designSystemColor: .surface))
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
        .listRowBackground(Color(designSystemColor: .surface))
    }
}

// MARK: - Previews

#if DEBUG

private extension SyncSettingsViewModel {

    /// Builds a `SyncSettingsViewModel` configured for previews. No delegate is set, so
    /// delegate-driven side effects (device refresh, pixels, sheets) are inert.
    static func preview(isSyncEnabled: Bool = false,
                        devices: [Device] = [],
                        isAIChatSyncEnabled: Bool = true,
                        autoRestoreProvider: SyncAutoRestorePreviewProvider = .disabled) -> SyncSettingsViewModel {
        let model = SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: autoRestoreProvider
        )
        model.isAIChatSyncEnabled = isAIChatSyncEnabled
        // Set `isSyncEnabled` before `devices`: its didSet clears devices when false.
        model.isSyncEnabled = isSyncEnabled
        model.devices = devices
        return model
    }
}

private extension SyncSettingsViewModel.Device {
    static let thisDevice = SyncSettingsViewModel.Device(id: "1", name: "iPhone 15 Pro", type: "phone", isThisDevice: true)
    static let desktop = SyncSettingsViewModel.Device(id: "2", name: "MacBook Pro", type: "desktop", isThisDevice: false)
    static let otherMobile = SyncSettingsViewModel.Device(id: "3", name: "Pixel 8", type: "phone", isThisDevice: false)
}

#Preview("Sync Off") {
    RebrandedPreview(isRebranded: true) {
        NavigationView {
            SimplifiedSyncSettingsViewV2(model: .preview(isSyncEnabled: false))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Sync On – This Device Only") {
    RebrandedPreview(isRebranded: true) {
        NavigationView {
            SimplifiedSyncSettingsViewV2(model: .preview(isSyncEnabled: true, devices: [.thisDevice], autoRestoreProvider: .enabled))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Sync On – Multiple Devices") {
    RebrandedPreview(isRebranded: true) {
        NavigationView {
            SimplifiedSyncSettingsViewV2(model: .preview(isSyncEnabled: true, devices: [.thisDevice, .desktop, .otherMobile], autoRestoreProvider: .enabled))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Sync On – Loading Devices") {
    RebrandedPreview(isRebranded: true) {
        NavigationView {
            SimplifiedSyncSettingsViewV2(model: .preview(isSyncEnabled: true, devices: []))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Sync Off (Legacy brand)") {
    RebrandedPreview(isRebranded: false) {
        NavigationView {
            SimplifiedSyncSettingsViewV2(model: .preview(isSyncEnabled: false))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#endif
