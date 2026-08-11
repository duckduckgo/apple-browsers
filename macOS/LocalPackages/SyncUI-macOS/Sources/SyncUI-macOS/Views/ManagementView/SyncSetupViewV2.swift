//
//  SyncSetupViewV2.swift
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

import AppKit
import SwiftUI
import SwiftUIExtensions
import DesignResourcesKit
import DesignResourcesKitIcons
import PreviewSnapshots

/// V2 of the Sync setup screen, gated behind the `simplifiedSyncSetupV2` feature flag.
/// This starts as a copy of `SyncSetupView` so the two versions can evolve independently.
struct SyncSetupViewV2<ViewModel>: View where ViewModel: ManagementViewModel {
    @EnvironmentObject var model: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(spacing: 8) {
                syncUnavailableView
                syncWithAnotherDeviceView
                (Text(.init(UserText.beginSyncFooterV2))
                 + Text(verbatim: " ")
                 + Text(Image(nsImage: DesignSystemImages.Glyphs.Size16.openIn)).baselineOffset(-3.0))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .padding(.top, 24)
                .padding(.horizontal, 24)
                .font(.system(size: 13))
            }
            syncThisDeviceView
            recoverSyncedDataView
        }
    }

    @ViewBuilder
    fileprivate var syncWithAnotherDeviceView: some View {
        VStack(alignment: .center, spacing: .zero) {
            Image(.syncDevices128)
                .padding(.top, 20)
                .padding(.bottom, 12)

            VStack(alignment: .center, spacing: 10) {
                SyncUIViewsV2.TextHeader(text: UserText.beginSyncTitleV2)
                SyncUIViewsV2.TextDetailSecondary(text: UserText.beginSyncDescriptionV2)
            }
            .padding(.bottom, 20)
            
            Button {
                Task {
                    await model.syncWithAnotherDevicePressed()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(nsImage: DesignSystemImages.Glyphs.Size24.qrScan)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(UserText.beginSyncButtonV2)
                }
            }
            .buttonStyle(SyncWithAnotherDeviceButtonStyleV2(enabled: model.isConnectingDevicesAvailable))
            .disabled(!model.isConnectingDevicesAvailable)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .syncRoundedBorder(cornerRadius: 24)
    }

    @ViewBuilder
    fileprivate var syncThisDeviceView: some View {
        HStack(spacing: 12) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.deviceLaptop)
            Text(UserText.syncThisDeviceTitleV2)
            Spacer()
            Toggle(isOn: Binding(
                get: { false },
                set: { isOn in
                    guard isOn else { return }
                    Task {
                        await model.syncWithServerPressed()
                    }
                }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!model.isAccountCreationAvailable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .syncRoundedBorder(cornerRadius: 12)
    }

    @ViewBuilder
    fileprivate var recoverSyncedDataView: some View {
        VStack(alignment: .leading, spacing: 12) {
            SyncUIViewsV2.TextHeader2(text: UserText.recoverSyncedDataTitleV2)
            Button(UserText.recoverCodeButtonV2) {
                Task {
                    await model.recoverDataPressed()
                }
            }
            .disabled(!model.isAccountRecoveryAvailable)
        }
    }

    @ViewBuilder
    fileprivate var syncUnavailableView: some View {
        if !model.isDataSyncingAvailable || !model.isConnectingDevicesAvailable || !model.isAccountCreationAvailable {
            if model.isAppVersionNotSupported {
                SyncWarningMessage(title: UserText.syncUnavailableTitle, message: UserText.syncUnavailableMessageUpgradeRequired)
                    .padding(.top, 16)
            } else {
                SyncWarningMessage(title: UserText.syncUnavailableTitle, message: UserText.syncUnavailableMessage)
                    .padding(.top, 16)
            }
        }
    }
}

#if DEBUG
struct SyncSetupViewV2_Previews: PreviewProvider {
    typealias State = PreviewManagementViewModel

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<State>(
        configurations: [
            .init(name: "Off state", state: PreviewManagementViewModel(
                isSyncEnabled: false,
                isSimplifiedSyncSetupV2Enabled: true
            )),
            .init(name: "Sync unavailable", state: PreviewManagementViewModel(
                isSyncEnabled: false,
                isSimplifiedSyncSetupV2Enabled: true,
                isDataSyncingAvailable: false,
                isConnectingDevicesAvailable: false,
                isAccountCreationAvailable: false
            ))
        ],
        configure: { model in
            DesignSystemRebrand.isAppRebranded = { true }
            return SyncSetupViewV2<PreviewManagementViewModel>()
                .environmentObject(model)
                .frame(width: 544, height: 800, alignment: .top)
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
        }
    )
}
#endif
