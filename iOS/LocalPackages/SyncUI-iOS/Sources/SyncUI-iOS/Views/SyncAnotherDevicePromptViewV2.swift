//
//  SyncAnotherDevicePromptViewV2.swift
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

struct SyncAnotherDevicePromptViewV2: View {

    @ObservedObject var model: SyncSettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Image(rebrandable: "Desktop-Sync-New-Feature-128", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 96)

                Text(UserText.simplifiedSyncAnotherDeviceV2Title)
                    .daxTitle1()
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 24)

                if let deviceName = model.thisDeviceName {
                    Text(UserText.simplifiedSyncAnotherDeviceV2Body(deviceName))
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Color(designSystemColor: .textPrimary))
            .padding(.top, 56)

            Spacer()

            VStack(spacing: 8) {
                Button {
                    model.syncAnotherDeviceFromConnectingSheet()
                } label: {
                    HStack(spacing: 8) {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.add)
                        Text(UserText.simplifiedSyncWithAnotherDeviceButton)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    model.notNowFromConnectingSheet()
                } label: {
                    Text(UserText.simplifiedSyncAnotherDeviceNotNow)
                }
                .buttonStyle(SecondaryFillButtonStyle())
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
    }
}

#if DEBUG

private extension SyncSettingsViewModel {
    static func previewModel() -> SyncSettingsViewModel {
        let model = SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: SyncAutoRestorePreviewProvider.disabled
        )
        model.isSyncEnabled = true
        model.devices = [.init(id: "1", name: "Dave’s iPhone", type: "phone", isThisDevice: true)]
        return model
    }
}

#Preview("Rebranded") {
    RebrandedPreview(isRebranded: true) {
        SyncAnotherDevicePromptViewV2(model: .previewModel())
    }
}

#Preview("Legacy brand") {
    RebrandedPreview(isRebranded: false) {
        SyncAnotherDevicePromptViewV2(model: .previewModel())
    }
}

#endif
