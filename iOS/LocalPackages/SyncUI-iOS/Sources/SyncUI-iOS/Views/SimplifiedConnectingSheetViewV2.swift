//
//  SimplifiedConnectingSheetViewV2.swift
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

import SwiftUI
import DesignResourcesKit

public struct SimplifiedConnectingSheetViewV2: View {

    @ObservedObject public var model: SyncSettingsViewModel

    public init(model: SyncSettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            switch model.connectingSheetPhase {
            case .connecting:
                SimplifiedConnectingContentViewV2()
                    .transition(.opacity)
            case .syncAnotherDevice:
                SyncAnotherDevicePromptViewV2(model: model)
                    .transition(.opacity)
            case .deviceConnected:
                SyncDeviceAddedViewV2(model: model)
                    .transition(.opacity)
            case .none:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.connectingSheetPhase)
        .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
    }
}

#if DEBUG
#Preview("Connecting") {
    RebrandedPreview(isRebranded: true) {
        SimplifiedConnectingSheetViewV2(model: .connectingSheetPreview(phase: .connecting))
    }
}

#Preview("Connecting – Dark") {
    RebrandedPreview(isRebranded: true) {
        SimplifiedConnectingSheetViewV2(model: .connectingSheetPreview(phase: .connecting))
    }
    .preferredColorScheme(.dark)
}

#Preview("Sync Another Device") {
    RebrandedPreview(isRebranded: true) {
        SimplifiedConnectingSheetViewV2(model: .connectingSheetPreview(phase: .syncAnotherDevice(isConnecting: false)))
    }
}

#Preview("Device Connected") {
    RebrandedPreview(isRebranded: true) {
        SimplifiedConnectingSheetViewV2(model: .connectingSheetPreview(phase: .deviceConnected))
    }
}

private extension SyncSettingsViewModel {
    static func connectingSheetPreview(phase: ConnectingSheetPhase) -> SyncSettingsViewModel {
        let model = SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: SyncAutoRestorePreviewProvider.disabled
        )
        model.isSyncEnabled = true
        model.devices = [.init(id: "1", name: "Dave’s iPhone", type: "phone", isThisDevice: true)]
        model.recoveryCode = "y2cJyqsW3FPSJ9y2cJyqsW3FPSJ9y2cJyqsW3FPSJ9"
        model.connectingSheetPhase = phase
        return model
    }
}
#endif
