//
//  SyncSettingsViewModelConnectingSheetTests.swift
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

import Foundation
import Testing
@testable import SyncUI_iOS

@MainActor
@Suite("Sync - Settings View Model Connecting Sheet")
final class SyncSettingsViewModelConnectingSheetTests {

    private func makeSUT() -> SyncSettingsViewModel {
        SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: SyncAutoRestorePreviewProvider.disabled
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test("Show success for a recovery sets the recovery success phase and stores the code", .timeLimit(.minutes(1)))
    func showSuccessForRecovery() {
        let sut = makeSUT()

        sut.showSuccess(recoveryCode: "recovery-code", isRecovery: true)

        #expect(sut.connectingSheetPhase == .success(isRecovery: true))
        #expect(sut.recoveryCode == "recovery-code")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Show success for a device added sets the non-recovery success phase and stores the code", .timeLimit(.minutes(1)))
    func showSuccessForDeviceAdded() {
        let sut = makeSUT()

        sut.showSuccess(recoveryCode: "device-code", isRecovery: false)

        #expect(sut.connectingSheetPhase == .success(isRecovery: false))
        #expect(sut.recoveryCode == "device-code")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Done from the connecting sheet dismisses it", .timeLimit(.minutes(1)))
    func doneFromConnectingSheetDismisses() {
        let sut = makeSUT()
        sut.showSuccess(recoveryCode: "recovery-code", isRecovery: true)

        sut.doneFromConnectingSheet()

        #expect(sut.connectingSheetPhase == nil)
    }
}
