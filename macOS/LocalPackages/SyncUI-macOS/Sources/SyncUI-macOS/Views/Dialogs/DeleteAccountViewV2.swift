//
//  DeleteAccountViewV2.swift
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

struct DeleteAccountViewV2: View {

    @EnvironmentObject var model: ManagementDialogModel

    let devices: [SyncDevice]

    @State private var isDeleting = false

    var body: some View {
        SyncDialogV2(spacing: 20.0) {
            VStack(alignment: .center, spacing: 20) {
                Image(.syncWarnFeature128)
                SyncUIViews.TextHeader(text: UserText.deleteAccountConfirmTitleV2)
                SyncUIViewsV2.TextDetailMultiline(text: UserText.deleteAccountConfirmMessageV2)

                SyncedDevicesListV2(devices: devices)
                    .roundedBorder()
            }
        } buttons: {
            Spacer()

            Button(UserText.cancel) {
                model.cancelPressed()
            }
            .buttonStyle(DismissActionButtonStyle(stateColors: .themedDismissButton))
            .disabled(isDeleting)

            Button {
                deleteAccount()
            } label: {
                HStack(spacing: 6) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(UserText.deleteAccountConfirmButtonV2)
                }
            }
            .buttonStyle(DismissActionButtonStyle(textColor: Color(designSystemColor: .destructivePrimary),
                                                  stateColors: .themedDismissButton))
            .disabled(isDeleting)
        }
    }

    private func deleteAccount() {
        guard !isDeleting else { return }
        isDeleting = true
        model.delegate?.deleteAccount()
    }
}

#if DEBUG
#Preview("Two Devices") {
    DesignSystemRebrand.isAppRebranded = { true }
    return DeleteAccountViewV2(devices: [
        SyncDevice(kind: .current, name: "Work Laptop", id: "current-device"),
        SyncDevice(kind: .mobile, name: "Androidz", id: "mobile-device")
    ])
    .environmentObject(ManagementDialogModel())
}

#Preview("Many Devices") {
    DesignSystemRebrand.isAppRebranded = { true }
    return DeleteAccountViewV2(devices: [
        SyncDevice(kind: .current, name: "Work Laptop", id: "current-device"),
        SyncDevice(kind: .mobile, name: "Androidz", id: "mobile-device"),
        SyncDevice(kind: .desktop, name: "Home iMac", id: "desktop-device"),
        SyncDevice(kind: .mobile, name: "iPad", id: "tablet-device"),
        SyncDevice(kind: .desktop, name: "Old Laptop", id: "old-device")
    ])
    .environmentObject(ManagementDialogModel())
}
#endif
