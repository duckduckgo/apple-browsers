//
//  RecoverSyncedDataView.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

struct RecoverSyncedDataView: View {
    @EnvironmentObject var model: ManagementDialogModel

    var body: some View {
        if model.isImprovedPairingFlowEnabled {
            improvedBody
        } else {
            legacyBody
        }
    }

    private var improvedBody: some View {
        SyncDialogV2(spacing: 20.0) {
            VStack(alignment: .center, spacing: 20) {
                Image(.clipboardSyncRecoverFeature128)
                VStack(alignment: .center, spacing: 8) {
                    SyncUIViews.CenteredTitle(text: UserText.recoverSyncedDataDialogTitleImproved)
                    SyncUIViews.CenteredSecondaryBody(text: UserText.recoverSyncedDataDialogSubtitleImproved)
                }
            }
        } buttons: {
            Spacer()
            Button(UserText.cancel) {
                model.cancelPressed()
            }
            .buttonStyle(DismissActionButtonStyle(stateColors: .themedDismissButton))

            Button(UserText.recoverSyncedDataDialogButtonImproved) {
                Task {
                    await model.delegate?.enterRecoveryCodePressed()
                }
            }
            .buttonStyle(DefaultActionButtonStyle(enabled: !model.isAuthenticating, stateColors: .themedActionButton))
            .disabled(model.isAuthenticating)
        }
    }

    private var legacyBody: some View {
        SyncDialog(spacing: 20.0) {
            VStack(alignment: .center, spacing: 20) {
                Image(.syncPair96)
                SyncUIViews.DialogTitle(text: UserText.reciverSyncedDataDialogTitle)
                SyncUIViews.DialogMessage(text: UserText.reciverSyncedDataDialogSubitle)
            }
            .frame(width: 320)
        } buttons: {
            Button(UserText.cancel) {
                model.cancelPressed()
            }
            .buttonStyle(DismissActionButtonStyle(stateColors: .themedDismissButton))
            Button(UserText.reciverSyncedDataDialogButton) {
                Task {
                    await model.delegate?.enterRecoveryCodePressed()
                }
            }
            .buttonStyle(DefaultActionButtonStyle(enabled: !model.isAuthenticating, stateColors: .themedActionButton))
            .disabled(model.isAuthenticating)
        }
    }

}

#if DEBUG
#Preview("Recover Synced Data") {
    RecoverSyncedDataView()
        .environmentObject(ManagementDialogModel())
}

#Preview("Recover Synced Data - Improved Pairing Flow") {
    RecoverSyncedDataView()
        .environmentObject({
            let model = ManagementDialogModel()
            model.isImprovedPairingFlowEnabled = true
            return model
        }())
}
#endif
