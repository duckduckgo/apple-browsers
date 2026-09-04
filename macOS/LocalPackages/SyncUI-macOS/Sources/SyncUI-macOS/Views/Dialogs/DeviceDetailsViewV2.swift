//
//  DeviceDetailsViewV2.swift
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

struct DeviceDetailsViewV2: View {

    @EnvironmentObject var model: ManagementDialogModel

    let device: SyncDevice

    @State private var deviceName = ""
    @State private var isSaving = false

    private var trimmedDeviceName: String {
        deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedDeviceName.isEmpty && trimmedDeviceName != device.name
    }

    private var illustration: Image {
        switch device.kind {
        case .current, .desktop:
            return Image(.desktopSyncAddedFeature128)
        case .mobile, .thirdParty:
            return Image(.mobileSyncAddedFeature128)
        }
    }

    private var title: String {
        guard device.isCurrent, !trimmedDeviceName.isEmpty else { return device.name }
        return trimmedDeviceName
    }

    var body: some View {
        SyncDialogV2(spacing: 20.0) {
            VStack(alignment: .center, spacing: 20) {
                illustration
                    .accessibilityHidden(true)
                VStack(alignment: .center, spacing: 8) {
                    SyncUIViews.TextHeader(text: title)
                    SyncUIViewsV2.TextCaption(text: UserText.deviceDetailsSyncedStatusV2)
                }
                if device.isCurrent {
                    nameField
                }
            }
        } buttons: {
            destructiveButton
            Spacer()
            dismissButton
        }
        .onAppear {
            deviceName = device.name
        }
    }

    private var nameField: some View {
        HStack(spacing: 16) {
            Text(UserText.deviceDetailsNameLabelV2)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            TextField(text: $deviceName) {
                EmptyView()
            }
            .labelsHidden()
            .onSubmit(save)
            .disabled(isSaving)
            .accessibilityIdentifier("SyncSettings.deviceDetails.nameField")
        }
        .padding(.horizontal, 10)
        .frame(height: 45)
        .syncRoundedBorder(cornerRadius: 12)
    }

    private var destructiveButton: some View {
        Button(device.isCurrent ? UserText.deviceDetailsTurnOffSyncButtonV2 : UserText.deviceDetailsRemoveDeviceButtonV2) {
            model.delegate?.presentRemoveDeviceConfirmation(device)
        }
        .buttonStyle(DismissActionButtonStyle(textColor: Color(designSystemColor: .destructivePrimary),
                                              stateColors: .themedDismissButton))
        .disabled(isSaving)
    }

    private var dismissButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(device.isCurrent ? UserText.deviceDetailsDoneButtonV2 : UserText.deviceDetailsCloseButtonV2)
            }
        }
        .buttonStyle(DismissActionButtonStyle(stateColors: .themedDismissButton))
        .disabled(isSaving)
    }

    private func save() {
        guard !isSaving else { return }
        guard device.isCurrent, canSave else {
            model.endFlow()
            return
        }
        isSaving = true
        model.delegate?.updateDeviceName(trimmedDeviceName)
    }
}

#if DEBUG
#Preview("This Device") {
    DesignSystemRebrand.isAppRebranded = { true }
    return DeviceDetailsViewV2(device: SyncDevice(kind: .current, name: "Work Laptop", id: "current-device"))
        .environmentObject(ManagementDialogModel())
}

#Preview("Other Device") {
    DesignSystemRebrand.isAppRebranded = { true }
    return DeviceDetailsViewV2(device: SyncDevice(kind: .mobile, name: "Pixel 8", id: "mobile-device"))
        .environmentObject(ManagementDialogModel())
}
#endif
