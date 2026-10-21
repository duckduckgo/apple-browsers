//
//  PairingV2OperationFailure.swift
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

public enum PairingV2FailureStage: String, Equatable {
    case presenterGenerateCode = "presenter_generate_code"
    case presenterOpenOwnChannel = "presenter_open_own_channel"
    case presenterPollOwnChannel = "presenter_poll_own_channel"
    case presenterSendPeerStatus = "presenter_send_peer_status"
    case presenterSendConfirmationStatus = "presenter_send_confirmation_status"
    case presenterSendRecoveryDenied = "presenter_send_recovery_denied"
    case presenterSendRecoveryCode = "presenter_send_recovery_code"
    case presenterSendRecoveryUnavailable = "presenter_send_recovery_unavailable"

    case scannerGenerateKeys = "scanner_generate_keys"
    case scannerOpenOwnChannel = "scanner_open_own_channel"
    case scannerSendHello = "scanner_send_hello"
    case scannerSendPeerStatus = "scanner_send_peer_status"
    case scannerPollOwnChannel = "scanner_poll_own_channel"
    case scannerSendConfirmationStatus = "scanner_send_confirmation_status"
    case scannerSendRecoveryDenied = "scanner_send_recovery_denied"
    case scannerSendRecoveryCode = "scanner_send_recovery_code"
    case scannerSendRecoveryUnavailable = "scanner_send_recovery_unavailable"
}

public enum PairingV2FailureKind: String, Equatable {
    case unavailable
    case expired
    case httpError = "http_error"
    case networkError = "network_error"
}

public struct PairingV2FailureContext: Equatable {
    public let stage: PairingV2FailureStage
    public let kind: PairingV2FailureKind?
}

public struct PairingV2OperationFailure: LocalizedError {
    public let context: PairingV2FailureContext
    public let underlyingError: Error

    init(context: PairingV2FailureContext, underlyingError: Error) {
        self.context = context
        self.underlyingError = underlyingError
    }

    init?(relayError: Error, stage: PairingV2FailureStage) {
        let kind: PairingV2FailureKind
        let underlyingError: Error

        if let relayError = relayError as? PairingV2RelayRequestError {
            kind = relayError.kind
            underlyingError = relayError.underlyingError
        } else {
            switch relayError {
            case PairingV2Error.relayChannelUnavailable:
                kind = .unavailable
            case PairingV2Error.relayChannelExpired:
                kind = .expired
            case SyncError.unexpectedStatusCode(let statusCode):
                kind = PairingV2FailureKind(statusCode: statusCode)
            default:
                return nil
            }
            underlyingError = relayError
        }

        self.init(context: PairingV2FailureContext(stage: stage, kind: kind), underlyingError: underlyingError)
    }

    init(generationStage: PairingV2FailureStage, underlyingError: Error) {
        self.init(context: PairingV2FailureContext(stage: generationStage, kind: nil), underlyingError: underlyingError)
    }

    public var errorDescription: String? {
        underlyingError.localizedDescription
    }
}

struct PairingV2RelayRequestError: LocalizedError {
    let kind: PairingV2FailureKind
    let underlyingError: Error

    var errorDescription: String? {
        underlyingError.localizedDescription
    }
}

extension PairingV2FailureKind {

    init(statusCode: Int) {
        switch statusCode {
        case 404:
            self = .unavailable
        case 410:
            self = .expired
        default:
            self = .httpError
        }
    }
}
