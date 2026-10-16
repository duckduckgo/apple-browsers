//
//  SyncSettingsViewModel_PreviewMocks.swift
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

#if DEBUG

import Foundation

extension SyncSettingsViewModel {

    /// Builds a `SyncSettingsViewModel` configured for previews. No delegate is set, so
    /// delegate-driven side effects (device refresh, pixels, sheets) are inert.
    static func preview(isSyncEnabled: Bool = false,
                        devices: [Device] = [],
                        isAIChatSyncEnabled: Bool = true,
                        autoRestoreProvider: SyncAutoRestorePreviewProvider = .disabled) -> SyncSettingsViewModel {
        let model = SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: autoRestoreProvider
        )
        model.isAIChatSyncEnabled = isAIChatSyncEnabled
        // Set `isSyncEnabled` before `devices`: its didSet clears devices when false.
        model.isSyncEnabled = isSyncEnabled
        model.devices = devices
        return model
    }

    static func connectingSheetPreview(phase: ConnectingSheetPhase,
                                       autoRestoreProvider: SyncAutoRestorePreviewProvider = .disabled) -> SyncSettingsViewModel {
        let model = SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: autoRestoreProvider
        )
        model.isSyncEnabled = true
        model.devices = [.init(id: "1", name: "Dave’s iPhone", type: "phone", isThisDevice: true)]
        model.recoveryCode = "y2cJyqsW3FPSJ9y2cJyqsW3FPSJ9y2cJyqsW3FPSJ9"
        model.connectingSheetPhase = phase
        return model
    }
}

extension SyncSettingsViewModel.Device {
    static let thisDevice = SyncSettingsViewModel.Device(id: "1", name: "iPhone 15 Pro", type: "phone", isThisDevice: true)
    static let desktop = SyncSettingsViewModel.Device(id: "2", name: "MacBook Pro", type: "desktop", isThisDevice: false)
    static let otherMobile = SyncSettingsViewModel.Device(id: "3", name: "Pixel 8", type: "phone", isThisDevice: false)
}

#endif
