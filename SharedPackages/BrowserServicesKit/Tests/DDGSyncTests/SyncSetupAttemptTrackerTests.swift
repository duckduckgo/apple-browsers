//
//  SyncSetupAttemptTrackerTests.swift
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
@_spi(Testing) import WideEvent
@testable import DDGSync

@MainActor
@Suite("SyncSetupAttemptTracker")
final class SyncSetupAttemptTrackerTests {

    private let wideEvent = WideEventMock()
    private var isEnabled = true
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private lazy var tracker = SyncSetupAttemptTracker(wideEvent: wideEvent,
                                                       isEnabled: { [unowned self] in isEnabled },
                                                       now: { [unowned self] in now })

    private func start(entryPoint: String? = "settings_page",
                       setupMode: SyncSetupWideEventData.SetupMode? = .multiDevice) {
        tracker.start(entryPoint: entryPoint, setupMode: setupMode, existingAccount: false, flowVersion: .v21, uiVersion: .v2)
    }

    private func advance(milliseconds: Int) {
        now = now.addingTimeInterval(Double(milliseconds) / 1000)
    }

    private var sent: [(status: WideEventStatus, parameters: [String: String])] {
        wideEvent.completions.map { data, status in
            (status, data.pixelParameters()
                .merging(data.contextData.pixelParameters()) { _, new in new }
                .merging(data.errorData?.pixelParameters() ?? [:]) { _, new in new })
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A second start ends the open attempt as UNKNOWN duplicated and keeps the new one open", .timeLimit(.minutes(1)))
    func secondStartEndsOpenAttemptAsDuplicated() {
        start(entryPoint: "settings_page")
        tracker.recordStep(.codeScreen)
        start(entryPoint: "deep_link")

        #expect(sent.count == 1)
        #expect(sent.first?.status == .unknown(reason: "duplicated"))
        #expect(sent.first?.parameters["context.name"] == "settings_page")
        #expect(sent.first?.parameters["feature.data.ext.last_step"] == "code_screen")
        #expect(wideEvent.started.count == 2)

        tracker.succeed(.successScreenShown)

        #expect(sent.count == 2)
        #expect(sent.last?.parameters["context.name"] == "deep_link")
        #expect(sent.last?.parameters["feature.data.ext.steps"] == "started,success_screen_shown")
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off, nothing is sent", .timeLimit(.minutes(1)))
    func flagOffSendsNothing() {
        isEnabled = false

        start()
        tracker.recordDeviceAuthShown()
        tracker.recordErrorScreen(for: .accountCreationFailed, underlyingError: nil)
        tracker.closeErrorScreen()
        start()
        tracker.succeed(.recoveryCodeShown)

        #expect(wideEvent.started.isEmpty)
        #expect(wideEvent.updates.isEmpty)
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The flag is read when the attempt starts", .timeLimit(.minutes(1)))
    func flagIsReadAtStart() {
        isEnabled = false
        start()
        isEnabled = true
        tracker.succeed(.successScreenShown)

        #expect(wideEvent.completions.isEmpty)

        start()
        isEnabled = false
        tracker.succeed(.successScreenShown)

        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new attempt still ends the open one after the flag turns off", .timeLimit(.minutes(1)))
    func duplicatedAfterFlagTurnsOff() {
        start()
        isEnabled = false
        start()
        tracker.succeed(.successScreenShown)

        #expect(sent.count == 1)
        #expect(sent.first?.status == .unknown(reason: "duplicated"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Try Again then success ends as SUCCESS with error_screen in steps", .timeLimit(.minutes(1)))
    func tryAgainThenSuccess() {
        start()
        tracker.recordStep(.preparingSync)
        tracker.recordErrorScreen(for: .accountCreationFailed, underlyingError: nil)

        #expect(wideEvent.completions.isEmpty)

        tracker.recordStep(.preparingSync)
        tracker.succeed(.successScreenShown)

        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
        #expect(sent.first?.parameters["feature.data.ext.steps"] == "started,preparing_sync,error_screen,preparing_sync,success_screen_shown")
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing the error screen ends as FAILURE with that error as status_reason", .timeLimit(.minutes(1)))
    func closingErrorScreen() {
        start()
        tracker.recordStep(.preparingSync)
        tracker.recordErrorScreen(for: .accountCreationFailed, underlyingError: nil)
        tracker.closeErrorScreen()

        #expect(sent.count == 1)
        #expect(sent.first?.status == .failure)
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == "account_creation_failed")
        #expect(sent.first?.parameters["feature.data.ext.last_step"] == "error_screen")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing the error screen after a successful retry sends nothing more", .timeLimit(.minutes(1)))
    func closingErrorScreenAfterAttemptEnded() {
        start()
        tracker.recordErrorScreen(for: .accountCreationFailed, underlyingError: nil)
        tracker.succeed(.successScreenShown)
        tracker.closeErrorScreen()

        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing the error screen after Try Again moved on leaves the retry open", .timeLimit(.minutes(1)))
    func closingErrorScreenDuringRetry() {
        start()
        tracker.recordErrorScreen(for: .accountCreationFailed, underlyingError: nil)
        tracker.recordStep(.preparingSync)
        tracker.closeErrorScreen()

        #expect(wideEvent.completions.isEmpty)

        tracker.succeed(.successScreenShown)

        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An error with no retry ends the attempt with the classified outcome", .timeLimit(.minutes(1)))
    func errorWithoutRetry() {
        start()
        tracker.recordStep(.codeEntry)
        tracker.end(with: .unableToRecognizeCode, underlyingError: nil)

        #expect(sent.first?.status == .cancelled)
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == "code_rejected")
        #expect(sent.first?.parameters["feature.data.ext.last_step"] == "code_entry")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing the choice prompt ends as CANCELLED user_closed with setup_mode single_device", .timeLimit(.minutes(1)))
    func closingChoicePrompt() {
        start(setupMode: .singleDevice)
        tracker.recordStep(.choiceScreen)
        tracker.end(.userClosed)

        #expect(sent.first?.status == .cancelled)
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == "user_closed")
        #expect(sent.first?.parameters["feature.data.ext.setup_mode"] == "single_device")
        #expect(sent.first?.parameters["feature.data.ext.initial_setup_mode"] == "single_device")
        #expect(sent.first?.parameters["feature.data.ext.last_step"] == "choice_screen")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Declining the sync this device offer ends as CANCELLED with the fallback recorded", .timeLimit(.minutes(1)))
    func decliningSyncThisDeviceOffer() {
        start(setupMode: .singleDevice)
        tracker.recordStep(.choiceScreen)
        tracker.switchMode(to: .multiDevice)
        tracker.recordStep(.codeScreen)
        tracker.recordSyncThisDeviceOffer()
        tracker.end(.userClosedSyncThisDeviceFallback)

        #expect(sent.first?.status == .cancelled)
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == "user_closed_sync_this_device_fallback")
        #expect(sent.first?.parameters["feature.data.ext.sync_this_device_fallback"] == "true")
        #expect(sent.first?.parameters["feature.data.ext.setup_mode"] == "multi_device")
        #expect(sent.first?.parameters["feature.data.ext.initial_setup_mode"] == "single_device")
        #expect(sent.first?.parameters["feature.data.ext.last_step"] == "sync_this_device_offer")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Accepting the restore offer keeps the attempt, with restore_offer in steps and setup_mode recovery", .timeLimit(.minutes(1)))
    func acceptingRestoreOffer() {
        start(setupMode: .singleDevice)
        tracker.recordStep(.restoreOffer)
        tracker.switchMode(to: .recovery)
        tracker.recordStep(.preparingSync)
        tracker.succeed(.successScreenShown)

        #expect(wideEvent.started.count == 1)
        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
        #expect(sent.first?.parameters["feature.data.ext.steps"] == "started,restore_offer,preparing_sync,success_screen_shown")
        #expect(sent.first?.parameters["feature.data.ext.setup_mode"] == "recovery")
        #expect(sent.first?.parameters["feature.data.ext.initial_setup_mode"] == "single_device")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A success screen ends as SUCCESS with its step as last_step", .timeLimit(.minutes(1)),
          arguments: [(SyncSetupAttemptTracker.SuccessStep.successScreenShown, "success_screen_shown"),
                      (.recoveryCodeShown, "recovery_code_shown")])
    func successScreen(successStep: SyncSetupAttemptTracker.SuccessStep, expectedStep: String) {
        start()
        tracker.recordStep(.preparingSync)
        tracker.succeed(successStep)

        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
        #expect(sent.first?.parameters["feature.data.ext.last_step"] == expectedStep)
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Device auth and camera permission are recorded", .timeLimit(.minutes(1)))
    func deviceAuthAndCameraPermission() {
        start()
        tracker.recordDeviceAuthShown()
        tracker.recordStep(.codeEntry)
        tracker.recordCameraPermission(.denied)
        tracker.end(.deviceAuthCancelled)

        #expect(sent.first?.parameters["feature.data.ext.device_auth_shown"] == "true")
        #expect(sent.first?.parameters["feature.data.ext.camera_permission"] == "denied")
        #expect(sent.first?.parameters["feature.data.ext.steps"] == "started,device_auth,code_entry")
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == "device_auth_cancelled")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A start without an entry point sends context.name unknown", .timeLimit(.minutes(1)))
    func missingEntryPoint() {
        start(entryPoint: nil)
        tracker.end(.userClosed)

        #expect(sent.first?.parameters["context.name"] == "unknown")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Latencies come from the injected clock", .timeLimit(.minutes(1)))
    func latencies() {
        start()
        advance(milliseconds: 4000)
        tracker.recordStep(.codeScreen)
        advance(milliseconds: 6000)
        tracker.recordStep(.preparingSync)
        advance(milliseconds: 2000)
        tracker.recordStep(.accountCreated)
        advance(milliseconds: 4000)
        tracker.end(with: .accountCreationFailed, underlyingError: nil)

        #expect(sent.first?.status == .failure)
        #expect(sent.first?.parameters["feature.data.ext.total_latency_ms_bucketed"] == "10000")
        #expect(sent.first?.parameters["feature.data.ext.last_step_latency_ms_bucketed"] == "3000")
        #expect(sent.first?.parameters["feature.data.ext.preparing_sync_latency_ms_bucketed"] == "5000")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Preparing sync latency stops when the success screen appears", .timeLimit(.minutes(1)))
    func preparingSyncLatencyOnSuccess() {
        start()
        advance(milliseconds: 1000)
        tracker.recordStep(.preparingSync)
        advance(milliseconds: 3500)
        tracker.succeed(.successScreenShown)

        #expect(sent.first?.parameters["feature.data.ext.preparing_sync_latency_ms_bucketed"] == "3000")
        #expect(sent.first?.parameters["feature.data.ext.total_latency_ms_bucketed"] == "3000")
    }

    private func startHostAwaitingJoiner() {
        start()
        tracker.recordPeer(role: .host, kind: .ddg)
        tracker.recordStep(.preparingSync)
        advance(milliseconds: 2500)
        tracker.recordHostAwaitingJoiner()
        advance(milliseconds: 45000)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A v2.1 host ends as SUCCESS with what the joiner reported, and the wait is left out of preparing sync",
          .timeLimit(.minutes(1)),
          arguments: SyncSetupWideEventData.PeerOutcome.allCases)
    func hostEndsWithJoinerOutcome(peerOutcome: SyncSetupWideEventData.PeerOutcome) {
        startHostAwaitingJoiner()

        tracker.recordJoinerOutcome(peerOutcome)

        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
        #expect(sent.first?.parameters["feature.data.ext.peer_outcome"] == peerOutcome.rawValue)
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == nil)
        #expect(sent.first?.parameters["feature.data.ext.steps"] == "started,preparing_sync,host_awaiting_joiner")
        #expect(sent.first?.parameters["feature.data.ext.last_step"] == "host_awaiting_joiner")
        #expect(sent.first?.parameters["feature.data.ext.preparing_sync_latency_ms_bucketed"] == "2000")
        #expect(sent.first?.parameters["feature.data.ext.last_step_latency_ms_bucketed"] == "30000")
        #expect(sent.first?.parameters["feature.data.ext.total_latency_ms_bucketed"] == "30000")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A v2.1 host that stops waiting without a report ends as SUCCESS with peer_outcome unknown",
          .timeLimit(.minutes(1)),
          arguments: [
            SyncConnectionError.pairingV2SessionTimedOut(timeoutStage: .waitingForJoinStatus),
            .syncCancelledFromOtherDevice,
            .transportFailure
          ])
    func hostStopsWaitingWithoutReport(error: SyncConnectionError) {
        startHostAwaitingJoiner()

        tracker.end(with: error, underlyingError: underlyingError)

        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
        #expect(sent.first?.parameters["feature.data.ext.peer_outcome"] == "unknown")
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == nil)
        #expect(sent.first?.parameters["feature.data.ext.timeout_stage"] == nil)
        #expect(sent.first?.parameters["feature.data.ext.error.domain"] == nil)
        #expect(sent.first?.parameters["feature.data.ext.last_step"] == "host_awaiting_joiner")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A v2.1 host whose user closes the waiting screen ends as SUCCESS with peer_outcome unknown", .timeLimit(.minutes(1)))
    func hostUserClosesWhileWaiting() {
        startHostAwaitingJoiner()

        tracker.end(.userClosed)

        #expect(sent.first?.status == .success)
        #expect(sent.first?.parameters["feature.data.ext.peer_outcome"] == "unknown")
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new attempt while a v2.1 host waits ends the waiting one as SUCCESS", .timeLimit(.minutes(1)))
    func newAttemptWhileHostWaits() {
        startHostAwaitingJoiner()

        start()

        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
        #expect(sent.first?.parameters["feature.data.ext.peer_outcome"] == "unknown")
        #expect(wideEvent.started.count == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A late report or code send from a replaced host doesn't end the new attempt", .timeLimit(.minutes(1)))
    func lateHostCallbacksLeaveReplacementOpen() {
        startHostAwaitingJoiner()
        start()

        tracker.recordJoinerOutcome(.success)
        tracker.endAsHost(peerOutcome: .unknown)

        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
        #expect(sent.first?.parameters["feature.data.ext.peer_outcome"] == "unknown")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A host before v2.1 ends as SUCCESS right after sending the code, with peer_outcome unknown", .timeLimit(.minutes(1)))
    func hostBeforeV21EndsAfterSendingCode() {
        start()
        tracker.recordPeer(role: .host, kind: .ddg)
        tracker.recordStep(.preparingSync)
        advance(milliseconds: 2500)

        tracker.endAsHost(peerOutcome: .unknown)

        #expect(sent.count == 1)
        #expect(sent.first?.status == .success)
        #expect(sent.first?.parameters["feature.data.ext.peer_outcome"] == "unknown")
        #expect(sent.first?.parameters["feature.data.ext.last_step"] == "preparing_sync")
        #expect(sent.first?.parameters["feature.data.ext.preparing_sync_latency_ms_bucketed"] == "2000")
    }

    @available(iOS 16, macOS 13, *)
    @Test("The other device leaving before the host sent the code ends as CANCELLED peer_left", .timeLimit(.minutes(1)))
    func peerLeavesBeforeHostSentCode() {
        start()
        tracker.recordPeer(role: .host, kind: .ddg)
        tracker.recordStep(.confirmationScreen)

        tracker.end(with: .syncCancelledFromOtherDevice, underlyingError: nil)

        #expect(sent.first?.status == .cancelled)
        #expect(sent.first?.parameters["feature.data.ext.status_reason"] == "peer_left")
        #expect(sent.first?.parameters["feature.data.ext.peer_outcome"] == nil)
    }

    private let underlyingError = NSError(domain: "TestDomain", code: 42, userInfo: [
        NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
    ])

    @available(iOS 16, macOS 13, *)
    @Test("A FAILURE sends the underlying error and its own underlying error", .timeLimit(.minutes(1)))
    func failureSendsUnderlyingError() {
        start()
        tracker.end(with: .accountCreationFailed, underlyingError: underlyingError)

        #expect(sent.first?.status == .failure)
        #expect(sent.first?.parameters["feature.data.ext.error.domain"] == "TestDomain")
        #expect(sent.first?.parameters["feature.data.ext.error.code"] == "42")
        #expect(sent.first?.parameters["feature.data.ext.error.underlying_domain"] == NSURLErrorDomain)
        #expect(sent.first?.parameters["feature.data.ext.error.underlying_code"] == String(NSURLErrorTimedOut))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A CANCELLED outcome doesn't send the underlying error", .timeLimit(.minutes(1)))
    func cancelledDoesNotSendUnderlyingError() {
        start()
        tracker.end(with: .unableToRecognizeCode, underlyingError: underlyingError)

        #expect(sent.first?.status == .cancelled)
        #expect(sent.first?.parameters["feature.data.ext.error.domain"] == nil)
        #expect(sent.first?.parameters["feature.data.ext.error.code"] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing the error screen sends the error the screen showed", .timeLimit(.minutes(1)))
    func closingErrorScreenSendsItsUnderlyingError() {
        start()
        tracker.recordErrorScreen(for: .accountCreationFailed, underlyingError: underlyingError)
        tracker.closeErrorScreen()

        #expect(sent.first?.status == .failure)
        #expect(sent.first?.parameters["feature.data.ext.error.domain"] == "TestDomain")
        #expect(sent.first?.parameters["feature.data.ext.error.code"] == "42")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A FAILURE without an underlying error sends no error fields", .timeLimit(.minutes(1)))
    func failureWithoutUnderlyingError() {
        start()
        tracker.end(with: .accountCreationFailed, underlyingError: nil)

        #expect(sent.first?.status == .failure)
        #expect(sent.first?.parameters["feature.data.ext.error.domain"] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Calls without an open attempt send nothing", .timeLimit(.minutes(1)))
    func callsWithoutOpenAttempt() {
        tracker.recordStep(.codeScreen)
        tracker.recordErrorScreen(for: .accountCreationFailed, underlyingError: nil)
        tracker.closeErrorScreen()
        tracker.end(.userClosed)
        tracker.succeed(.successScreenShown)

        #expect(wideEvent.updates.isEmpty)
        #expect(wideEvent.completions.isEmpty)
    }
}
