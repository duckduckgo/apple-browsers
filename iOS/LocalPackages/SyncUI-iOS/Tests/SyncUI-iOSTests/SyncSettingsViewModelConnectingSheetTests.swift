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

        sut.showSuccess(recoveryCode: "recovery-code", destination: .fullRecoveryCode(isRecovery: true))

        #expect(sut.connectingSheetPhase == .success(.fullRecoveryCode(isRecovery: true)))
        #expect(sut.recoveryCode == "recovery-code")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Show success for a device added sets the non-recovery success phase and stores the code", .timeLimit(.minutes(1)))
    func showSuccessForDeviceAdded() {
        let sut = makeSUT()

        sut.showSuccess(recoveryCode: "device-code", destination: .fullRecoveryCode(isRecovery: false))

        #expect(sut.connectingSheetPhase == .success(.fullRecoveryCode(isRecovery: false)))
        #expect(sut.recoveryCode == "device-code")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Show success while waiting for the other device finishes the connecting animation first", .timeLimit(.minutes(1)))
    func showSuccessWhileWaitingForOtherDevice() {
        let sut = makeSUT()
        sut.connectingSheetPhase = .waitingForOtherDevice

        sut.showSuccess(recoveryCode: "device-code", destination: .fullRecoveryCode(isRecovery: false))

        #expect(sut.connectingSheetPhase == .connecting(isRecovery: false, successDestination: .fullRecoveryCode(isRecovery: false)))

        sut.connectingAnimationDidFinish()

        #expect(sut.connectingSheetPhase == .success(.fullRecoveryCode(isRecovery: false)))
        #expect(sut.recoveryCode == "device-code")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Already-syncing success keeps its destination through animation and until Done", .timeLimit(.minutes(1)))
    func alreadySyncingSuccessKeepsDestinationThroughAnimation() {
        let sut = makeSUT()
        let destination = SyncSettingsViewModel.SuccessDestination.alreadySyncing
        sut.connectingSheetPhase = .waitingForOtherDevice

        sut.showSuccess(recoveryCode: "device-code", destination: destination)

        #expect(sut.connectingSheetPhase == .connecting(isRecovery: false, successDestination: destination))

        sut.connectingAnimationDidFinish()

        #expect(sut.connectingSheetPhase == .success(destination))
        #expect(sut.recoveryCode == "device-code")

        sut.doneFromConnectingSheet()

        #expect(sut.connectingSheetPhase == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A later full success does not retain the previous short destination", .timeLimit(.minutes(1)))
    func laterFullSuccessDoesNotRetainShortDestination() {
        let sut = makeSUT()
        sut.showSuccess(recoveryCode: "host-code", destination: .alreadySyncing)
        sut.doneFromConnectingSheet()

        sut.showSuccess(recoveryCode: "joiner-code", destination: .fullRecoveryCode(isRecovery: false))

        #expect(sut.connectingSheetPhase == .success(.fullRecoveryCode(isRecovery: false)))
        #expect(sut.recoveryCode == "joiner-code")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Done from the connecting sheet dismisses it", .timeLimit(.minutes(1)))
    func doneFromConnectingSheetDismisses() {
        let sut = makeSUT()
        sut.showSuccess(recoveryCode: "recovery-code", destination: .fullRecoveryCode(isRecovery: true))

        sut.doneFromConnectingSheet()

        #expect(sut.connectingSheetPhase == nil)
    }
}
