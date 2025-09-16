//
//  SyncRecoveryPromptView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
import DuckUI
import SyncUI_iOS

struct SyncRecoveryPromptView: View {
    let syncWithAnotherDeviceAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            ScrollView {
                VStack(spacing: 0) {
                    Image(.sync128)
                        .padding(24)

                    Text(UserText.syncRecoveryPromptTitle)
                        .daxTitle1()
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)

                    Text(UserText.syncRecoveryPromptMessage)
                        .daxBodyRegular()
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .foregroundStyle(Color(designSystemColor: .textPrimary))
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: syncWithAnotherDeviceAction) {
                    Text(UserText.syncRecoveryPromptSyncButton)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: dismissAction) {
                    Text(UserText.syncRecoveryPromptContinueButton)
                }
                .buttonStyle(GhostButtonStyle())
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 30)
        }
        .padding(.bottom)
        .background(Color(designSystemColor: .backgroundSheets))

    }    
}

#Preview {
    SyncRecoveryPromptView(
        syncWithAnotherDeviceAction: {},
        dismissAction: {}
    )
}
