//
//  SyncSetupWideEventOutcomeTests.swift
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
import WideEvent
@testable import DDGSync

@Suite("SyncConnectionError sync-setup wide event outcome")
struct SyncSetupWideEventOutcomeTests {

    typealias Outcome = SyncSetupWideEventData.Outcome

    struct Case: CustomTestStringConvertible, Sendable {
        let error: SyncConnectionError
        let status: WideEventStatus
        let statusReason: String?
        let timeoutStage: String?

        init(_ error: SyncConnectionError, _ status: WideEventStatus, _ statusReason: String?, timeoutStage: String? = nil) {
            self.error = error
            self.status = status
            self.statusReason = statusReason
            self.timeoutStage = timeoutStage
        }

        var testDescription: String { "\(error)" }
    }

    static let cases: [Case] = [
        Case(.unableToRecognizeCode, .cancelled, "code_rejected"),
        Case(.unsupportedThirdPartyRecoveryCode, .cancelled, "code_rejected"),
        Case(.updateRequired(detectedDuring: .codeRead), .cancelled, "code_rejected"),
        Case(.updateRequired(detectedDuring: .pairingSession), .failure, "needs_upgrade"),
        Case(.thirdPartyAccountAlreadyUpgraded, .cancelled, "already_upgraded"),
        Case(.syncCancelledFromOtherDevice, .cancelled, "peer_left"),

        Case(.pairingV2SessionTimedOut(timeoutStage: .waitingForPeerHello), .cancelled, "session_timeout", timeoutStage: "waiting_for_peer_hello"),
        Case(.pairingV2SessionTimedOut(timeoutStage: .waitingForConfirmation), .cancelled, "session_timeout", timeoutStage: "waiting_for_confirmation"),
        Case(.pairingV2SessionTimedOut(timeoutStage: .waitingForPeerStatus), .failure, "session_timeout", timeoutStage: "waiting_for_peer_status"),
        Case(.pairingV2SessionTimedOut(timeoutStage: .waitingForRecoveryCode), .failure, "session_timeout", timeoutStage: "waiting_for_recovery_code"),
        Case(.pairingV2SessionTimedOut(timeoutStage: .loggingIn), .failure, "session_timeout", timeoutStage: "logging_in"),
        Case(.pairingV2SessionTimedOut(timeoutStage: nil), .failure, "session_timeout", timeoutStage: "unknown"),
        Case(.pairingV2SessionTimedOut(timeoutStage: .waitingForJoinStatus), .success, nil),

        Case(.failedToFetchPublicKey, .failure, "v1_failure"),
        Case(.failedToTransmitExchangeRecoveryKey, .failure, "v1_failure"),
        Case(.failedToFetchConnectRecoveryKey, .failure, "v1_failure"),
        Case(.failedToLogIn, .failure, "v1_failure"),
        Case(.failedToTransmitExchangeKey, .failure, "v1_failure"),
        Case(.failedToFetchExchangeRecoveryKey, .failure, "v1_failure"),
        Case(.failedToCreateAccount, .failure, "v1_failure"),
        Case(.failedToTransmitConnectRecoveryKey, .failure, "v1_failure"),
        Case(.pollingForRecoveryKeyTimedOut, .failure, "v1_failure"),

        Case(.accountCreationFailed, .failure, "account_creation_failed"),
        Case(.accountUpgradeFailed, .failure, "account_upgrade_failed"),
        Case(.protocolError, .failure, "protocol_error"),
        Case(.unexpectedSecondHello, .failure, "unexpected_second_hello"),
        Case(.unexpectedEvent, .failure, "unexpected_event"),
        Case(.pairingSessionNotReady, .failure, "pairing_session_not_ready"),
        Case(.unreadablePairingMessage, .failure, "unrecognized_code"),
        Case(.pairingV2OperationFailure(PairingV2FailureContext(stage: .scannerPollOwnChannel, kind: .networkError)), .failure, "relay_channel_failure"),
        Case(.pairingV2OperationFailure(PairingV2FailureContext(stage: .scannerGenerateKeys, kind: nil)), .failure, "unexpected_failure"),
        Case(.relayChannelUnavailable, .failure, "relay_channel_unavailable"),
        Case(.recoveryCodePreparationFailed, .failure, "recovery_code_preparation_failed"),
        Case(.peerRecoveryCodeUnavailable, .failure, "peer_recovery_code_unavailable"),
        Case(.transportFailure, .failure, "transport_failure"),
        Case(.unexpectedFailure, .failure, "unexpected_failure"),
        Case(.missingThirdPartyCredential, .failure, "missing_3party_credential"),
        Case(.undecryptableThirdPartyCredential, .failure, "undecryptable_3party_credential"),
        Case(.accountExtendFailed, .failure, "account_extend_failed"),
        Case(.missingThirdPartyKey, .failure, "missing_3party_key"),
        Case(.localStorageFailed, .failure, "local_storage_failed"),
        Case(.invalidCredentials, .failure, "invalid_credentials"),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("Each connection error ends the attempt with its status, status_reason and timeout_stage",
          .timeLimit(.minutes(1)),
          arguments: cases)
    func outcome(_ testCase: Case) {
        #expect(testCase.error.syncSetupWideEventOutcome == Outcome(status: testCase.status,
                                                                    statusReason: testCase.statusReason,
                                                                    timeoutStage: testCase.timeoutStage))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A FAILURE sends the classic sync_setup_ended_failed reason", .timeLimit(.minutes(1)), arguments: cases.filter { $0.status == .failure })
    func failureReasonMatchesClassicPixel(_ testCase: Case) {
        #expect(testCase.error.syncSetupWideEventOutcome.statusReason == testCase.error.syncSetupFailureReason)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Already paired and a blocked account switch end as CANCELLED", .timeLimit(.minutes(1)))
    func cancelledOutcomesOutsideConnectionErrors() {
        #expect(Outcome.alreadyPaired == Outcome(status: .cancelled, statusReason: "already_paired"))
        #expect(Outcome.accountSwitchBlocked == Outcome(status: .cancelled, statusReason: "account_switch_blocked"))
    }
}
