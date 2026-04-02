//
//  SyncAnotherDevicePromptView.swift
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

struct SyncAnotherDevicePromptView: View {

    @ObservedObject var model: SyncSettingsViewModel

    var body: some View {
        UnderflowContainer {
            VStack(spacing: 0) {
                Image("Desktop-Sync-New-Feature-128")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 96)
                    .padding(.bottom, 20)

                Text(UserText.simplifiedSyncAnotherDeviceTitle)
                    .daxTitle1()
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)

                Text(UserText.simplifiedSyncAnotherDeviceBody)
                    .daxBodyRegular()
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color(designSystemColor: .textPrimary))
            .padding(.horizontal, 24)
            .padding(.top, 56)
        } foregroundContent: {
            VStack(spacing: 8) {
                Button {
                    model.dismissSyncWithAnotherDevicePrompt()
                    model.scanQRCode()
                } label: {
                    HStack(spacing: 8) {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.qr)
                        Text(UserText.simplifiedSyncAnotherDeviceButton)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    model.dismissSyncWithAnotherDevicePrompt()
                } label: {
                    Text(model.simplifiedSyncAnotherDevicePromptDismissButtonTitle)
                }
                .buttonStyle(GhostButtonStyle())
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 30)
        }
        .background(Color(designSystemColor: .backgroundSheets))
    }
}
