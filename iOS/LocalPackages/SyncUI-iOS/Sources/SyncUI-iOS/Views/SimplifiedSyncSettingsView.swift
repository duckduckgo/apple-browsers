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

    @State var isRecoverSyncedDataSheetVisible = false
    @State var isEnvironmentSwitcherInstructionsVisible = false

    public init(model: SyncSettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        List {
            syncDisabledContent
        }
        .navigationTitle(UserText.syncTitle)
        .applyListStyle()
        .environmentObject(model)
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
        getDesktopBrowserSection
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
            HStack {
                VStack(alignment: .center, spacing: 20) {
                    Image("Sync-New-128")

                    Text(model.isAIChatSyncEnabled ? UserText.simplifiedSyncHeaderMessage : UserText.simplifiedSyncHeaderMessageBasic)
                        .daxBodyRegular()
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
            }
        } header: {
            devEnvironmentIndicator
        }
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
                    // Enable sync functionality to be added
                }
            )) {
                Text(UserText.simplifiedSyncToggleTitle)
                    .daxBodyRegular()
            }
            .disabled(!model.isAccountCreationAvailable)
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
                Task { @MainActor in
                    if await model.commonAuthenticate() {
                        isRecoverSyncedDataSheetVisible = true
                    }
                }
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
            .sheet(isPresented: $isRecoverSyncedDataSheetVisible) {
                RecoverSyncedDataView(model: model, onCancel: {
                    isRecoverSyncedDataSheetVisible = false
                })
            }
            .disabled(!model.isAccountRecoveryAvailable)
        } header: {
            Text(UserText.simplifiedAlreadySetUpSectionHeader)
        }
    }

    @ViewBuilder
    var getDesktopBrowserSection: some View {
        Section {
            NavigationLink(destination: PlatformLinksView(model: model, source: .notActivated)) {
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
