//
//  SyncThisDeviceFallbackView.swift
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

struct SyncThisDeviceFallbackView: View {
    @EnvironmentObject var model: ManagementDialogModel

    private var isBusy: Bool {
        model.isBusy
    }

    var body: some View {
        SyncDialogV2(spacing: 20.0) {
            VStack(alignment: .center, spacing: 20) {
                Image(.desktopSyncNewFeature128)
                VStack(alignment: .center, spacing: 8) {
                    SyncUIViews.CenteredTitle(text: UserText.syncThisDeviceFallbackTitleImproved)
                    SyncUIViews.CenteredSecondaryBody(text: UserText.syncThisDeviceFallbackSubtitleImproved)
                }
            }
        } buttons: {
            Spacer()
            Button(UserText.cancel) {
                model.cancelPressed()
            }
            .buttonStyle(DismissActionButtonStyle(stateColors: .themedDismissButton))
            .disabled(isBusy)

            Button {
                Task {
                    await model.delegate?.syncThisDeviceFromFallback()
                }
            } label: {
                HStack(spacing: 6) {
                    if model.isConnectingThisDeviceOnly {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(UserText.syncThisDeviceFallbackButtonImproved)
                }
            }
            .buttonStyle(DefaultActionButtonStyle(enabled: !isBusy, stateColors: .themedActionButton))
            .disabled(isBusy)
        }
    }
}

#if DEBUG
#Preview("Default") {
    SyncThisDeviceFallbackView()
        .environmentObject(ManagementDialogModel())
}

#Preview("Connecting") {
    SyncThisDeviceFallbackView()
        .environmentObject({
            let model = ManagementDialogModel()
            model.isConnectingThisDeviceOnly = true
            return model
        }())
}
#endif
