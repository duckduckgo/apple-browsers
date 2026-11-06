//
//  TurnOffSyncOptionsView.swift
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

import SwiftUI
import SwiftUIExtensions
import DesignResourcesKit
import DesignResourcesKitIcons

struct TurnOffSyncOptionsView: View {

    @EnvironmentObject var model: ManagementDialogModel

    let thisDevice: SyncDevice
    let devices: [SyncDevice]

    @State private var isDeleteServerDataSelected: Bool
    @State private var isConfirmingRemoveDevice = false
    @State private var isConfirmingDeleteServerData = false
    @State private var isInProgress = false

    init(thisDevice: SyncDevice, devices: [SyncDevice], isDeleteServerDataSelected: Bool) {
        self.thisDevice = thisDevice
        self.devices = devices
        _isDeleteServerDataSelected = State(initialValue: isDeleteServerDataSelected)
    }

    var body: some View {
        if isConfirmingRemoveDevice {
            RemoveDeviceView(device: thisDevice) {
                isConfirmingRemoveDevice = false
            }
        } else {
            turnOffSyncDialog
        }
    }

    private var turnOffSyncDialog: some View {
        SyncSetupDialog(spacing: 20.0) {
            if isConfirmingDeleteServerData {
                deleteServerDataConfirmation
            } else {
                options
            }
        } buttons: {
            Spacer()

            Button(UserText.cancel) {
                cancel()
            }
            .buttonStyle(DismissActionButtonStyle(stateColors: .themedDismissButton))
            .disabled(isInProgress)

            if isDeleteServerDataSelected {
                deleteServerDataButton
            } else {
                removeDeviceButton
            }
        }
    }

    private var options: some View {
        VStack(alignment: .center, spacing: 20) {
            Image(isDeleteServerDataSelected ? .syncAlertFeature128 : .syncRemoveDeviceDesktop)
                .accessibilityHidden(true)
            SyncUIViews.DialogTitle(text: isDeleteServerDataSelected
                                   ? UserText.turnOffSyncDeleteServerDataTitle
                                   : UserText.removeDeviceConfirmTitleImproved(thisDevice.name))
            SyncUIViews.CenteredBody(text: isDeleteServerDataSelected
                                              ? UserText.turnOffSyncDeleteServerDataMessage
                                              : UserText.removeDeviceConfirmMessageImproved(thisDevice.name))
            deleteServerDataToggle
            if isDeleteServerDataSelected {
                devicesSection
            }
        }
    }

    private var deleteServerDataConfirmation: some View {
        VStack(alignment: .center, spacing: 20) {
            Image(.criticalUpdateFeature128)
                .accessibilityHidden(true)
            SyncUIViews.DialogTitle(text: UserText.deleteServerDataConfirmTitle)
            SyncUIViews.CenteredBody(text: UserText.turnOffSyncDeleteServerDataMessage)
            devicesSection
        }
    }

    private var deleteServerDataToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.trash)
                    .accessibilityHidden(true)
                Text(UserText.turnOffSyncDeleteServerDataToggle)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Spacer()
                Toggle(isOn: $isDeleteServerDataSelected) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(Text(UserText.turnOffSyncDeleteServerDataToggle))
                .accessibilityIdentifier("SyncSettings.turnOffSync.deleteServerDataToggle")
                .disabled(isInProgress)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .syncRoundedBorder(cornerRadius: 12)

            SyncUIViews.Caption(text: UserText.turnOffSyncDeleteServerDataToggleCaption)
                .padding(.horizontal, 16)
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SyncUIViews.SectionHeading(text: UserText.myDevices)
            SyncedDevicesList(devices: devices)
                .syncRoundedBorder(cornerRadius: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var removeDeviceButton: some View {
        Button(UserText.turnOffSyncRemoveDeviceButton) {
            model.delegate?.turnOffSyncRemoveDeviceSelected()
            isConfirmingRemoveDevice = true
        }
        .buttonStyle(DismissActionButtonStyle(textColor: Color(designSystemColor: .destructivePrimary),
                                              stateColors: .themedDismissButton))
        .disabled(isInProgress)
        .accessibilityIdentifier("SyncSettings.turnOffSync.removeDeviceButton")
    }

    private var deleteServerDataButton: some View {
        Button {
            deleteServerDataPressed()
        } label: {
            HStack(spacing: 6) {
                if isInProgress {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(UserText.turnOffSyncDeleteServerDataButton)
            }
        }
        .buttonStyle(DestructiveActionButtonStyle(enabled: !isInProgress,
                                                  backgroundColor: Color(designSystemColor: .destructivePrimary),
                                                  backgroundPressedColor: Color(designSystemColor: .destructiveSecondary)))
        .disabled(isInProgress)
        .accessibilityIdentifier("SyncSettings.turnOffSync.deleteServerDataButton")
    }

    private func deleteServerDataPressed() {
        guard !isInProgress else { return }
        if isConfirmingDeleteServerData {
            isInProgress = true
            model.delegate?.turnOffSyncDeleteServerDataConfirmed()
        } else {
            model.delegate?.turnOffSyncDeleteServerDataSelected()
            isConfirmingDeleteServerData = true
        }
    }

    private func cancel() {
        if isConfirmingDeleteServerData {
            model.delegate?.turnOffSyncDeleteServerDataCancelled()
            isConfirmingDeleteServerData = false
        } else {
            model.cancelPressed()
        }
    }
}

#if DEBUG
private let previewDevices = [
    SyncDevice(kind: .current, name: "Work Laptop", id: "current-device"),
    SyncDevice(kind: .mobile, name: "Androidz", id: "mobile-device")
]

#Preview("Remove Device") {
    TurnOffSyncOptionsView(thisDevice: previewDevices[0], devices: previewDevices, isDeleteServerDataSelected: false)
        .environmentObject(ManagementDialogModel())
}

#Preview("Delete Server Data") {
    TurnOffSyncOptionsView(thisDevice: previewDevices[0], devices: previewDevices, isDeleteServerDataSelected: true)
        .environmentObject(ManagementDialogModel())
}
#endif
