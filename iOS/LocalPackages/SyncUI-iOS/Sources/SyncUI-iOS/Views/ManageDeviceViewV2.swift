//
//  ManageDeviceViewV2.swift
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
import DuckUI
import SwiftUI
import UIComponents

struct ManageDeviceViewV2: View {

    @ObservedObject var model: SyncSettingsViewModel

    @StateObject private var editModel: EditDeviceViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var isShowingRemoveConfirmation = false
    @State private var lastSavedDeviceName: String

    private let device: SyncSettingsViewModel.Device

    init(model: SyncSettingsViewModel,
         device: SyncSettingsViewModel.Device) {
        self.model = model
        self.device = device
        _editModel = StateObject(wrappedValue: model.createEditDeviceModel(device))
        _lastSavedDeviceName = State(initialValue: device.name)
    }

    var body: some View {
        List {
            headerSection

            if device.isThisDevice {
                nameSection
                syncToggleSection
            } else {
                removeSection
            }
        }
        .applyListStyle()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.isSyncEnabled) { isEnabled in
            if !isEnabled {
                dismiss()
            }
        }
        .onDisappear {
            saveDeviceNameIfNeeded()
        }
    }

    private var headerSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(rebrandable: device.syncedIllustrationName, bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 96)

                VStack(spacing: 4) {
                    Text(headerTitle)
                        .daxTitle2()
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(designSystemColor: .textPrimary))

                    StatusIndicatorView(status: syncStatus, text: syncStatusText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color(designSystemColor: .background))
    }

    private var headerTitle: String {
        device.isThisDevice ? editModel.name : device.name
    }

    private var isSynced: Bool {
        device.isThisDevice ? model.isSyncEnabled : true
    }

    private var syncStatus: StatusIndicator {
        isSynced ? .on : .off
    }

    private var syncStatusText: String {
        isSynced ? UserText.simplifiedManageDeviceStatusSynced : UserText.simplifiedSyncStatusOff
    }

    private var nameSection: some View {
        Section {
            TextField("", text: $editModel.name)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .submitLabel(.done)
                .onSubmit {
                    saveDeviceNameIfNeeded()
                }
                .accessibility(identifier: "deviceName")
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    private var syncToggleSection: some View {
        Section {
            Toggle(isOn: syncToggleBinding) {
                Text(UserText.simplifiedSyncToggleTitleThisDevice)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }
            .tint(Color(designSystemColor: .accentPrimary))
            .disabled(model.isBusy)
            .accessibility(identifier: "SyncThisDeviceToggle")
        } footer: {
            Text(UserText.simplifiedManageDeviceTurnOffFooter)
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    private var syncToggleBinding: Binding<Bool> {
        Binding {
            model.isSyncEnabled
        } set: { newValue in
            if !newValue {
                model.disableSyncToggleTapped()
            }
        }
    }

    private func saveDeviceNameIfNeeded() {
        guard device.isThisDevice,
              model.isSyncEnabled,
              editModel.name != lastSavedDeviceName else { return }

        lastSavedDeviceName = editModel.name
        editModel.save()
    }

    private var removeSection: some View {
        Section {
            Button(role: .destructive) {
                isShowingRemoveConfirmation = true
            } label: {
                Text(UserText.removeDeviceButton)
                    .daxBodyRegular()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibility(identifier: "removeDevice")
        } footer: {
            Text(UserText.simplifiedManageDeviceRemoveFooter)
        }
        .listRowBackground(Color(designSystemColor: .surface))
        .alert(UserText.removeDeviceTitle, isPresented: $isShowingRemoveConfirmation) {
            Button(UserText.cancelButton, role: .cancel) {}
            Button(UserText.removeDeviceButton, role: .destructive) {
                model.createRemoveDeviceModel(device).remove()
                dismiss()
            }
        } message: {
            Text(UserText.removeDeviceMessage(device.name))
        }
    }
}

private extension SyncSettingsViewModel.Device {

    var syncedIllustrationName: String {
        type == "desktop" ? "Desktop-Sync-Added-128" : "Mobile-Sync-Added-128"
    }
}

#if DEBUG

private extension SyncSettingsViewModel {
    static func managePreview(isSyncEnabled: Bool = true) -> SyncSettingsViewModel {
        let model = SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: SyncAutoRestorePreviewProvider.disabled
        )
        model.isSyncEnabled = isSyncEnabled
        return model
    }
}

#Preview("Other Device – Desktop") {
    RebrandedPreview(isRebranded: true) {
        NavigationView {
            ManageDeviceViewV2(
                model: .managePreview(),
                device: .init(id: "2", name: "macOS Ventura", type: "desktop", isThisDevice: false)
            )
        }
    }
}

#Preview("Other Device – Mobile") {
    RebrandedPreview(isRebranded: true) {
        NavigationView {
            ManageDeviceViewV2(
                model: .managePreview(),
                device: .init(id: "3", name: "Pixel 8", type: "phone", isThisDevice: false)
            )
        }
    }
}

#Preview("This Device – Sync On") {
    RebrandedPreview(isRebranded: true) {
        NavigationView {
            ManageDeviceViewV2(
                model: .managePreview(isSyncEnabled: true),
                device: .init(id: "1", name: "iPhone 15 Pro", type: "phone", isThisDevice: true)
            )
        }
    }
}

#Preview("This Device – Sync Off") {
    RebrandedPreview(isRebranded: true) {
        NavigationView {
            ManageDeviceViewV2(
                model: .managePreview(isSyncEnabled: false),
                device: .init(id: "1", name: "iPhone 15 Pro", type: "phone", isThisDevice: true)
            )
        }
    }
}

#endif
