//
//  RemoveDeviceViewV2.swift
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

struct RemoveDeviceViewV2: View {

    @EnvironmentObject var model: ManagementDialogModel

    let device: SyncDevice

    @State private var isRemoving = false

    private var illustration: Image {
        device.kind == .mobile ? Image(.syncRemoveDeviceMobile) : Image(.syncRemoveDeviceDesktop)
    }

    var body: some View {
        SyncDialogV2(spacing: 20.0) {
            VStack(alignment: .center, spacing: 20) {
                illustration
                SyncUIViews.TextHeader(text: UserText.removeDeviceConfirmTitleV2)
                SyncUIViewsV2.TextDetailMultilineMarkdown(text: UserText.removeDeviceConfirmMessageV2(device.name))
            }
        } buttons: {
            Spacer()

            Button(UserText.cancel) {
                model.cancelPressed()
            }
            .buttonStyle(DismissActionButtonStyle(stateColors: .themedDismissButton))
            .disabled(isRemoving)

            Button {
                remove()
            } label: {
                HStack(spacing: 6) {
                    if isRemoving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(UserText.removeDeviceConfirmButtonV2)
                }
            }
            .buttonStyle(DismissActionButtonStyle(textColor: Color(designSystemColor: .destructivePrimary),
                                                  stateColors: .themedDismissButton))
            .disabled(isRemoving)
        }
    }

    private func remove() {
        guard !isRemoving else { return }
        isRemoving = true
        model.delegate?.removeDeviceConfirmed(device)
    }
}

#if DEBUG
#Preview("This Device") {
    DesignSystemRebrand.isAppRebranded = { true }
    return RemoveDeviceViewV2(device: SyncDevice(kind: .current, name: "Work Laptop", id: "current-device"))
        .environmentObject(ManagementDialogModel())
}

#Preview("Other Device") {
    DesignSystemRebrand.isAppRebranded = { true }
    return RemoveDeviceViewV2(device: SyncDevice(kind: .mobile, name: "Androidz", id: "mobile-device"))
        .environmentObject(ManagementDialogModel())
}
#endif
