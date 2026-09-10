//
//  ManagementDialog.swift
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

public enum PreparingToSyncMode: Equatable {
    case singleDeviceOrRecovery
    case twoDevicePairing
}

public enum ManagementDialogKind: Equatable {
    case deleteAccount(_ devices: [SyncDevice])
    case deleteAccountV2(_ devices: [SyncDevice])
    case turnOffSync
    case deviceDetails(_ device: SyncDevice)
    case deviceDetailsV2(_ device: SyncDevice)
    case removeDevice(_ device: SyncDevice)
    case removeDeviceV2(_ device: SyncDevice)
    case syncWithAnotherDevice(codeForDisplayOrPasting: String, stringForQRCode: String)
    case prepareToSync(PreparingToSyncMode)
    case waitForOtherDevice
    case saveRecoveryCode(_ code: String)
    case nowSyncing
    case syncWithServer
    case syncAnotherDevicePrompt
    case syncAuthenticationCancelled
    case enterRecoveryCode(stringForQRCode: String)
    case recoverSyncedData
    case empty
}

public struct ManagementDialog: View {
    @ObservedObject public var model: ManagementDialogModel
    @ObservedObject public var recoveryCodeModel: RecoveryCodeViewModel

    var errorTitle: String {
        return model.syncErrorMessage?.type.title ?? "Sync Error"
    }

    var errorDescription: String {
        composeErrorDescription(
            primary: model.syncErrorMessage?.type.description,
            detail: model.syncErrorMessage?.errorDescription
        )
    }

    var buttonTitle: String {
        return model.syncErrorMessage?.type.buttonTitle ?? UserText.ok
    }

    public init(model: ManagementDialogModel, recoveryCodeModel: RecoveryCodeViewModel = .init()) {
        self.model = model
        self.recoveryCodeModel = recoveryCodeModel
    }

    public var body: some View {
        content
            .alert(isPresented: $model.shouldShowErrorMessage) {
                if model.shouldShowSwitchAccountsMessage {
                    Alert(
                        title: Text(UserText.syncAlertSwitchAccountTitle),
                        message: Text(UserText.syncAlertSwitchAccountMessage),
                        primaryButton: .default(Text(UserText.syncAlertSwitchAccountButton)) {
                            model.userConfirmedSwitchAccounts(recoveryCode: recoveryCodeModel.recoveryCode)
                        },
                        secondaryButton: .cancel {
                            model.cancelPressed()
                        }
                    )
                } else {
                    syncErrorAlert
                }
            }
    }

    @ViewBuilder var content: some View {
        Group {
            switch model.currentDialog {
            case .turnOffSync:
                TurnOffSyncView()
            case .deviceDetails(let device):
                DeviceDetailsView(device: device)
            case .deviceDetailsV2(let device):
                DeviceDetailsViewV2(device: device)
            case .removeDevice(let device):
                RemoveDeviceView(device: device)
            case .removeDeviceV2(let device):
                RemoveDeviceViewV2(device: device)
            case .deleteAccount(let devices):
                DeleteAccountView(devices: devices)
            case .deleteAccountV2(let devices):
                DeleteAccountViewV2(devices: devices)
            case .syncWithAnotherDevice(let codeForDisplayOrPasting, let stringForQRCode):
                if model.isSimplifiedSyncSetupV2Enabled {
                    SyncWithAnotherDeviceViewV2(codeForDisplayOrPasting: codeForDisplayOrPasting, stringForQRCode: stringForQRCode)
                } else {
                    SyncWithAnotherDeviceView(codeForDisplayOrPasting: codeForDisplayOrPasting, stringForQRCode: stringForQRCode)
                }
            case .prepareToSync(let mode):
                if model.isSimplifiedSyncSetupV2Enabled {
                    PreparingToSyncViewV2(state: .connecting)
                } else {
                    PreparingToSyncView(mode: mode)
                }
            case .waitForOtherDevice:
                if model.isSimplifiedSyncSetupV2Enabled {
                    PreparingToSyncViewV2(state: .waitingForOtherDevice)
                } else {
                    PreparingToSyncView(mode: .twoDevicePairing)
                }
            case .saveRecoveryCode(let code):
                if model.isSimplifiedSyncSetupV2Enabled {
                    SyncSuccessViewV2(code: code)
                } else {
                    SaveRecoveryPDFView(code: code)
                }
            case .nowSyncing:
                DeviceSyncedView()
            case .syncWithServer:
                SyncWithServerView()
            case .syncAnotherDevicePrompt:
                SyncAnotherDevicePromptView()
            case .syncAuthenticationCancelled:
                SyncAuthenticationCancelledView()
            case .enterRecoveryCode(let stringForQRCode):
                EnterRecoveryCodeView(stringForQRCode: stringForQRCode)
            case .recoverSyncedData:
                RecoverSyncedDataView()
            default:
                EmptyView()
            }
        }
        .environmentObject(model)
        .environmentObject(recoveryCodeModel)
    }

    private func composeErrorDescription(primary: String?, detail: String?) -> String {
        let primary = primary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let primary, !primary.isEmpty else {
            return detail ?? ""
        }
        // Some callers use the default type description as the detail when there is no underlying error.
        // This is to avoid showing the same message twice in those cases.
        guard let detail, !detail.isEmpty, detail != primary else {
            return primary
        }

        return primary + "\n" + detail
    }

    private var syncErrorAlert: Alert {
        let dismissButton = Alert.Button.default(Text(buttonTitle)) {
            model.endFlow()
        }
        let errorDescription = errorDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !errorDescription.isEmpty else {
            return Alert(title: Text(errorTitle), dismissButton: dismissButton)
        }

        return Alert(
            title: Text(errorTitle),
            message: Text(errorDescription),
            dismissButton: dismissButton
        )
    }
}
