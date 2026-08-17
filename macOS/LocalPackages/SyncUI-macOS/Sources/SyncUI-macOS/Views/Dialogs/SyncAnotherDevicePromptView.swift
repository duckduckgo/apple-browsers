//
//  SyncAnotherDevicePromptView.swift
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

struct SyncAnotherDevicePromptView: View {
    @EnvironmentObject var model: ManagementDialogModel

    private var isBusy: Bool {
        model.isConnecting
    }

    var body: some View {
        SyncDialogV2(spacing: 20.0) {
            VStack(alignment: .center, spacing: 20) {
                Image(.syncPairFeature128)
                VStack(alignment: .center, spacing: 8) {
                    SyncUIViewsV2.TextHeader(text: UserText.syncAnotherDevicePromptTitleV2)
                    SyncUIViewsV2.TextDetailSecondary(text: UserText.syncAnotherDevicePromptSubtitleV2)
                }
            }
        } buttons: {
            Button {
                Task {
                    await model.delegate?.syncThisDeviceOnlyFromPrompt()
                }
            } label: {
                HStack(spacing: 6) {
                    if model.isConnectingThisDeviceOnly {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(UserText.syncThisDeviceOnlyButtonV2)
                }
            }
            .buttonStyle(DismissActionButtonStyle(stateColors: .themedDismissButton))
            .disabled(isBusy)

            Button {
                model.delegate?.syncWithAnotherDeviceFromPrompt()
            } label: {
                HStack(spacing: 6) {
                    if model.isConnectingAnotherDevice {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(UserText.syncWithAnotherDeviceButtonV2)
                }
            }
            .buttonStyle(DefaultActionButtonStyle(enabled: !isBusy, stateColors: .themedActionButton))
            .disabled(isBusy)
        }
        .onAppear {
            model.delegate?.syncAnotherDevicePromptDidAppear()
        }
    }
}

#if DEBUG
#Preview("Default") {
    DesignSystemRebrand.isAppRebranded = { true }
    return SyncAnotherDevicePromptView()
        .environmentObject(ManagementDialogModel())
}

#Preview("Connecting") {
    SyncAnotherDevicePromptView()
        .environmentObject({
            let model = ManagementDialogModel()
            model.isConnectingThisDeviceOnly = true
            return model
        }())
}
#endif
