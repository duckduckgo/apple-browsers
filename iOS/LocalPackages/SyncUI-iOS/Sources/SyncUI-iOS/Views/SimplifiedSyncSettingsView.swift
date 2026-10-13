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
import UIComponents

#if DEBUG
import PreviewSnapshots
#endif

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
        .onChange(of: model.isSyncEnabled) { isEnabled in
            if !isEnabled {
                selectedDevice = nil
            }
        }
        .syncPasscodeRequiredAlert(isPresented: $model.shouldShowPasscodeRequiredAlert)
        .sheet(item: $model.connectingSheetPhase, onDismiss: {
            model.connectingSheetDidDismiss()
        }, content: {_ in
            SimplifiedConnectingSheetView(model: model)
                .interactiveDismissDisabled()
        })
        .sheet(isPresented: $model.isTurnOffSyncSheetVisible, onDismiss: {
            model.turnOffSyncSheetDidDismiss()
        }, content: {
            TurnOffSyncSheetView(model: model)
        })
    }
}

// MARK: - Sync Disabled Content

extension SimplifiedSyncSettingsView {

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
                Text(UserText.simplifiedSyncToggleTitle)
                    .daxBodyRegular()
                Spacer()
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
                .accessibilityLabel(UserText.simplifiedSyncToggleTitle)
                .accessibility(identifier: "SyncToggle")
            }
            .animation(.easeInOut(duration: 0.3), value: model.isBusy)
            .disabled(model.isBusy || (!model.isSyncEnabled && !model.isAccountCreationAvailable))
        }
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))

        if !model.isSyncEnabled {
            Section {
                syncWithAnotherDeviceButton
            }
            .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
        }
    }

    @ViewBuilder
    var syncWithAnotherDeviceButton: some View {
        Button {
            model.scanQRCode()
        } label: {
            HStack(spacing: 8) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.qrScan)
                    .foregroundColor(Color(designSystemColor: .accentPrimary))
                Text(UserText.simplifiedSyncWithAnotherDeviceButton)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .accentPrimary))
            }
        }
        .disabled(!(model.isSyncEnabled || model.isAccountCreationAvailable))
    }

    @ViewBuilder
    var recoverSyncedDataSection: some View {
        Section {
            Button {
                model.delegate?.fireSyncSetupPixel(event: .recoverSyncedDataTapped)
                model.beginRecoverFlow()
            } label: {
                HStack {
                    Text(UserText.simplifiedHaveRecoveryCodeButton)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    Spacer()
                    disclosureChevron
                }
            }
            .sheet(isPresented: $model.isRecoverSyncedDataSheetVisible) {
                RecoverSyncedDataView(model: model, onCancel: {
                    model.isRecoverSyncedDataSheetVisible = false
                })
            }
            .disabled(!model.isAccountRecoveryAvailable)
        } header: {
            Text(UserText.simplifiedRecoverSyncedDataSectionHeader)
        }
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
    }

    @ViewBuilder
    func getDesktopBrowserSection(source: SyncSettingsViewModel.PlatformLinksPixelSource) -> some View {
        Section {
            NavigationLink(destination: PlatformLinksView(model: model, source: source)) {
                Label(title: {
                    Text(UserText.simplifiedGetOurDesktopBrowserTitle)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                }, icon: {
                    Image(uiImage: DesignSystemImages.Color.Size24.deviceLaptopInstall)
                })
            }
            .buttonStyle(.plain)
        } header: {
            Text(UserText.simplifiedDownloadSectionHeader)
        }
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
    }
}

// MARK: - Sync Enabled Content

extension SimplifiedSyncSettingsView {

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
                syncWithAnotherDeviceButton
            }
        } header: {
            Text(UserText.simplifiedMyDevicesSectionHeader)
        }
        .onReceive(timer) { _ in
            if selectedDevice == nil {
                model.delegate?.refreshDevices(clearDevices: false)
            }
        }
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
    }

    @ViewBuilder
    var devicesList: some View {
        ForEach(model.devices) { device in
            Button {
                Task { @MainActor in
                    if await model.commonAuthenticate() {
                        model.deviceDetailsShown(for: device)
                        selectedDevice = device
                    }
                }
            } label: {
                HStack {
                    SyncDeviceTypeImage(device: device)
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
            .background(
                NavigationLink(isActive: manageDeviceBinding(for: device)) {
                    ManageDeviceView(model: model, device: device)
                } label: {
                    EmptyView()
                }
                .accessibilityHidden(true)
            )
        }
    }

    func manageDeviceBinding(for device: SyncSettingsViewModel.Device) -> Binding<Bool> {
        Binding {
            selectedDevice?.id == device.id
        } set: { isActive in
            if !isActive {
                selectedDevice = nil
            }
        }
    }

    var disclosureChevron: some View {
        Image(systemName: "chevron.forward")
            .font(Font.system(.footnote).weight(.bold))
            .foregroundColor(Color(UIColor.tertiaryLabel))
    }

    // MARK: Bookmarks

    @ViewBuilder
    var bookmarksSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UserText.simplifiedBookmarksUnifiedFavoritesTitle)
                        .daxBodyRegular()
                    Text(UserText.simplifiedBookmarksUnifiedFavoritesCaption)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Toggle("", isOn: $model.isUnifiedFavoritesEnabled)
                    .labelsHidden()
                    .tint(Color(designSystemColor: .accentPrimary))
                    .accessibilityLabel(UserText.simplifiedBookmarksUnifiedFavoritesTitle)
                    .accessibility(identifier: "UnifiedFavoritesToggle")
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UserText.simplifiedBookmarksFetchFaviconsTitle)
                        .daxBodyRegular()
                    Text(UserText.simplifiedBookmarksFetchFaviconsCaption)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Toggle("", isOn: $model.isFaviconsFetchingEnabled)
                    .labelsHidden()
                    .tint(Color(designSystemColor: .accentPrimary))
                    .accessibilityLabel(UserText.simplifiedBookmarksFetchFaviconsTitle)
                    .accessibility(identifier: "FaviconFetchingToggle")
            }
        } header: {
            Text(UserText.simplifiedBookmarksSectionHeader)
        }
        .onAppear {
            model.delegate?.updateOptions()
        }
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
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
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
    }

    // MARK: Delete

    @ViewBuilder
    var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                model.turnOffSyncTapped()
            } label: {
                Text(model.isImprovedPairingFlowEnabled ? UserText.simplifiedTurnOffSyncButton : UserText.simplifiedDeleteSyncDataButton)
            }
        }
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
    }
}

// MARK: - Previews

#if DEBUG
struct SimplifiedSyncSettingsView_Previews: PreviewProvider {

    enum State {
        case syncOff
        case thisDeviceOnly
        case multipleDevices
        case loadingDevices
    }

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<State>(
        configurations: [
            .init(name: "Sync Off", state: .syncOff),
            .init(name: "Sync On – This Device Only", state: .thisDeviceOnly, scope: .previews),
            .init(name: "Sync On – Multiple Devices", state: .multipleDevices),
            .init(name: "Sync On – Loading Devices", state: .loadingDevices, scope: .previews)
        ],
        configure: { state in
            navigationContainer {
                SimplifiedSyncSettingsView(model: model(for: state))
                    .navigationTitle(UserText.syncTitle)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .applyRebranding()
        }
    )

    @ViewBuilder
    private static func navigationContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 16, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content)
                .navigationViewStyle(.stack)
        }
    }

    private static func model(for state: State) -> SyncSettingsViewModel {
        switch state {
        case .syncOff:
            return .preview(isSyncEnabled: false)
        case .thisDeviceOnly:
            return .preview(isSyncEnabled: true, devices: [.thisDevice], autoRestoreProvider: .enabled)
        case .multipleDevices:
            return .preview(isSyncEnabled: true, devices: [.thisDevice, .desktop, .otherMobile], autoRestoreProvider: .enabled)
        case .loadingDevices:
            return .preview(isSyncEnabled: true, devices: [])
        }
    }
}
#endif
