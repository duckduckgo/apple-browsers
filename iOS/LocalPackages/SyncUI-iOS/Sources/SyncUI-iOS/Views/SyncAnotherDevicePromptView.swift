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
    @State private var bottomSafeArea: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color(designSystemColor: .textPrimary))
            .padding(.horizontal, 24)
            .padding(.top, 56)

            Spacer()

            VStack(spacing: 8) {
                Button {
                    model.syncAnotherDeviceFromPromptTapped()
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
                    Text(UserText.simplifiedSyncAnotherDeviceNotNow)
                }
                .buttonStyle(GhostButtonStyle())
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 30)
            .padding(.bottom, max(20 - bottomSafeArea, 0))
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { bottomSafeArea = geometry.safeAreaInsets.bottom }
            }
        )
        .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
    }
}
