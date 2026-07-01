//
//  SyncPixels.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import PixelKit
import DDGSync

enum SyncFeatureUsagePixels: PixelKitEvent {
    private enum ParameterKeys {
        static let connectedDevices = "connected_devices"
    }

    case syncDisabled
    case syncDisabledAndDeleted(connectedDevices: Int)

    var name: String {
        switch self {
        case .syncDisabled: return "sync_disabled"
        case .syncDisabledAndDeleted: return "sync_disabledanddeleted"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .syncDisabledAndDeleted(let connectedDevices):
            return [ParameterKeys.connectedDevices: String(connectedDevices)]
        case .syncDisabled:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .syncDisabled,
                .syncDisabledAndDeleted:
            return [.pixelSource]
        }
    }
}

enum SyncSwitchAccountPixelKitEvent: PixelKitEvent {
    case syncAskUserToSwitchAccount
    case syncUserAcceptedSwitchingAccount
    case syncUserCancelledSwitchingAccount
    case syncUserSwitchedAccount
    case syncUserSwitchedLogoutError
    case syncUserSwitchedLoginError

    var name: String {
        switch self {
        case .syncAskUserToSwitchAccount: return "sync_ask_user_to_switch_account"
        case .syncUserAcceptedSwitchingAccount: return "sync_user_accepted_switching_account"
        case .syncUserCancelledSwitchingAccount: return "sync_user_cancelled_switching_account"
        case .syncUserSwitchedAccount: return "sync_user_switched_account"
        case .syncUserSwitchedLogoutError: return "sync_user_switched_logout_error"
        case .syncUserSwitchedLoginError: return "sync_user_switched_login_error"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .syncAskUserToSwitchAccount,
                .syncUserAcceptedSwitchingAccount,
                .syncUserCancelledSwitchingAccount,
                .syncUserSwitchedAccount,
                .syncUserSwitchedLogoutError,
                .syncUserSwitchedLoginError:
            return [.pixelSource]
        }
    }
}

enum SyncSetupPixelKitEvent: PixelKitEvent {

    enum ParameterKey {
        static let source = "source"
        static let flowVersion = "flow_version"
        static let myKind = "my_kind"
        static let codeType = "code_type"
        static let codeVersion = "code_version"
        static let path = "path"
        static let reason = "reason"
        static let peerKind = "peer_kind"
        static let myRole = "my_role"
    }

    enum ParameterValue {
        static let ddg = "ddg"
        static let recovery = "recovery"
        static let pairing = "pairing"
        static let linking = "linking"
        static let v1 = "v1"
        static let v2 = "v2"
        static let v1Failure = "v1_failure"
        static let alreadyPaired = "already_paired"
        static let accountCreationFailed = "account_creation_failed"
        static let accountUpgradeFailed = "account_upgrade_failed"
        static let invalidCredentials = "invalid_credentials"
        static let protocolError = "protocol_error"
        static let transportFailure = "transport_failure"
        static let sessionTimeout = "session_timeout"
        static let needsUpgrade = "needs_upgrade"
        static let incompatibleCode = "incompatible_code"
        static let alreadyUpgraded = "already_upgraded"
        static let unrecognizedCode = "unrecognized_code"
        static let scanningCancelled = "scanning_cancelled"
        static let syncConfirmationDenied = "sync_confirmation_denied"
        static let unexpectedSecondHello = "unexpected_second_hello"
        static let unexpectedEvent = "unexpected_event"
        static let pairingSessionNotReady = "pairing_session_not_ready"
        static let relayChannelUnavailable = "relay_channel_unavailable"
        static let recoveryCodePreparationFailed = "recovery_code_preparation_failed"
        static let peerRecoveryCodeUnavailable = "peer_recovery_code_unavailable"
        static let unexpectedFailure = "unexpected_failure"
        static let missingThirdPartyCredential = "missing_3party_credential"
        static let undecryptableThirdPartyCredential = "undecryptable_3party_credential"
        static let accountExtendFailed = "account_extend_failed"
        static let missingThirdPartyKey = "missing_3party_key"
        static let localStorageFailed = "local_storage_failed"
        static let host = "host"
        static let joiner = "joiner"
    }

    case syncSetupBarcodeScreenShown(SyncSetupSource, flowVersion: String?)
    case syncSetupBarcodeCodeCopied(SyncSetupSource, flowVersion: String?)
    case syncSetupManualCodeEntryScreenShown(flowVersion: String?)
    case syncSetupManualCodeEnteredSuccess(SyncSetupSource, flowVersion: String?, codeVersion: String?)
    case syncSetupManualCodeEnteredFailed(SyncSetupSource?, flowVersion: String?, reason: String?)
    case syncSetupEndedAbandoned(SyncSetupSource, flowVersion: String?, reason: String? = nil)
    case syncSetupEndedFailed(SyncSetupSource?, flowVersion: String?, peerKind: String?, myRole: String?, reason: String?)
    case syncSetupEndedSuccessful(SyncSetupSource, flowVersion: String?, peerKind: String?, myRole: String?)

    var name: String {
        switch self {
        case .syncSetupBarcodeScreenShown: return "sync_setup_barcode_screen_shown"
        case .syncSetupBarcodeCodeCopied: return "sync_setup_barcode_code_copied"
        case .syncSetupManualCodeEntryScreenShown: return "sync_setup_manual_code_entry_screen_shown"
        case .syncSetupManualCodeEnteredSuccess: return "sync_setup_manual_code_entered_success"
        case .syncSetupManualCodeEnteredFailed: return "sync_setup_manual_code_entered_failed"
        case .syncSetupEndedAbandoned: return "sync_setup_ended_abandoned"
        case .syncSetupEndedFailed: return "sync_setup_ended_failed"
        case .syncSetupEndedSuccessful: return "sync_setup_ended_successful"
        }
    }

    var parameters: [String: String]? {
        var parameters = [ParameterKey.myKind: ParameterValue.ddg]
        parameters[ParameterKey.source] = source?.rawValue
        parameters[ParameterKey.flowVersion] = flowVersion
        parameters[ParameterKey.codeType] = codeType
        parameters[ParameterKey.codeVersion] = codeVersion
        parameters[ParameterKey.path] = path
        parameters[ParameterKey.reason] = reason
        parameters[ParameterKey.peerKind] = peerKind
        parameters[ParameterKey.myRole] = myRole
        return parameters
    }

    private var source: SyncSetupSource? {
        switch self {
        case
            .syncSetupBarcodeScreenShown(let source, _),
            .syncSetupBarcodeCodeCopied(let source, _),
            .syncSetupManualCodeEnteredSuccess(let source, _, _),
            .syncSetupEndedAbandoned(let source, _, _),
            .syncSetupEndedSuccessful(let source, _, _, _):
            return source
        case
            .syncSetupManualCodeEnteredFailed(let source, _, _),
            .syncSetupEndedFailed(let source, _, _, _, _):
            return source
        case
            .syncSetupManualCodeEntryScreenShown:
            return nil
        }
    }

    private var flowVersion: String? {
        switch self {
        case .syncSetupBarcodeScreenShown(_, let flowVersion),
                .syncSetupBarcodeCodeCopied(_, let flowVersion),
                .syncSetupManualCodeEntryScreenShown(let flowVersion),
                .syncSetupManualCodeEnteredSuccess(_, let flowVersion, _),
                .syncSetupManualCodeEnteredFailed(_, let flowVersion, _),
                .syncSetupEndedAbandoned(_, let flowVersion, _),
                .syncSetupEndedFailed(_, let flowVersion, _, _, _),
                .syncSetupEndedSuccessful(_, let flowVersion, _, _):
            return flowVersion
        }
    }

    private var codeType: String? {
        switch self {
        case .syncSetupManualCodeEnteredSuccess(let source, _, _):
            return source.syncSetupCodeType
        default:
            return nil
        }
    }

    private var codeVersion: String? {
        switch self {
        case .syncSetupManualCodeEnteredSuccess(_, _, let codeVersion):
            return codeVersion
        default:
            return nil
        }
    }

    private var path: String? {
        switch self {
        case .syncSetupEndedSuccessful(let source, _, _, _):
            return source.syncSetupPath
        case .syncSetupEndedFailed(let source, _, _, _, _):
            return source?.syncSetupPath
        default:
            return nil
        }
    }

    private var reason: String? {
        switch self {
        case .syncSetupManualCodeEnteredFailed(_, _, let reason),
                .syncSetupEndedAbandoned(_, _, let reason),
                .syncSetupEndedFailed(_, _, _, _, let reason):
            return reason
        default:
            return nil
        }
    }

    private var peerKind: String? {
        switch self {
        case .syncSetupEndedSuccessful(_, _, let peerKind, _),
                .syncSetupEndedFailed(_, _, let peerKind, _, _):
            return peerKind
        default:
            return nil
        }
    }

    private var myRole: String? {
        switch self {
        case .syncSetupEndedSuccessful(_, _, _, let myRole),
                .syncSetupEndedFailed(_, _, _, let myRole, _):
            return myRole
        default:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .syncSetupBarcodeScreenShown,
                .syncSetupBarcodeCodeCopied,
                .syncSetupManualCodeEntryScreenShown,
                .syncSetupManualCodeEnteredSuccess,
                .syncSetupManualCodeEnteredFailed,
                .syncSetupEndedAbandoned,
                .syncSetupEndedFailed,
                .syncSetupEndedSuccessful:
            return [.pixelSource]
        }
    }
}

private extension SyncSetupSource {

    var syncSetupCodeType: String? {
        switch self {
        case .recovery:
            return SyncSetupPixelKitEvent.ParameterValue.recovery
        case .exchange, .connect:
            return SyncSetupPixelKitEvent.ParameterValue.linking
        case .unknown:
            return nil
        }
    }

    var syncSetupPath: String? {
        switch self {
        case .recovery:
            return SyncSetupPixelKitEvent.ParameterValue.recovery
        case .exchange, .connect:
            return SyncSetupPixelKitEvent.ParameterValue.pairing
        case .unknown:
            return nil
        }
    }

}

extension SyncSetupSource {

    var syncSetupMyRole: String? {
        switch self {
        case .connect:
            return SyncSetupPixelKitEvent.ParameterValue.host
        case .exchange:
            return SyncSetupPixelKitEvent.ParameterValue.joiner
        case .recovery, .unknown:
            return nil
        }
    }
}

extension PairingV2DeviceKind {

    var syncSetupPeerKind: String {
        rawValue
    }
}

extension SyncConnectionError {

    var syncSetupFailureReason: String? {
        switch self {
        // These cases are emitted by the legacy V1 exchange/connect flow and are intentionally bucketed together.
        case .failedToLogIn,
                .failedToFetchPublicKey,
                .failedToTransmitExchangeRecoveryKey,
                .failedToFetchConnectRecoveryKey,
                .failedToTransmitExchangeKey,
                .failedToFetchExchangeRecoveryKey,
                .failedToTransmitConnectRecoveryKey,
                .pollingForRecoveryKeyTimedOut,
                .failedToCreateAccount:
            return SyncSetupPixelKitEvent.ParameterValue.v1Failure
        case .invalidCredentials:
            return SyncSetupPixelKitEvent.ParameterValue.invalidCredentials
        case .pairingV2SessionTimedOut:
            return SyncSetupPixelKitEvent.ParameterValue.sessionTimeout
        case .updateRequired:
            return SyncSetupPixelKitEvent.ParameterValue.needsUpgrade
        case .unsupportedThirdPartyRecoveryCode:
            return SyncSetupPixelKitEvent.ParameterValue.incompatibleCode
        case .thirdPartyAccountAlreadyUpgraded:
            return SyncSetupPixelKitEvent.ParameterValue.alreadyUpgraded
        case .unableToRecognizeCode:
            return SyncSetupPixelKitEvent.ParameterValue.unrecognizedCode
        case .accountCreationFailed:
            return SyncSetupPixelKitEvent.ParameterValue.accountCreationFailed
        case .accountUpgradeFailed:
            return SyncSetupPixelKitEvent.ParameterValue.accountUpgradeFailed
        case .transportFailure:
            return SyncSetupPixelKitEvent.ParameterValue.transportFailure
        case .protocolError:
            return SyncSetupPixelKitEvent.ParameterValue.protocolError
        case .syncCancelledFromOtherDevice:
            return nil
        case .unexpectedSecondHello:
            return SyncSetupPixelKitEvent.ParameterValue.unexpectedSecondHello
        case .unexpectedEvent:
            return SyncSetupPixelKitEvent.ParameterValue.unexpectedEvent
        case .pairingSessionNotReady:
            return SyncSetupPixelKitEvent.ParameterValue.pairingSessionNotReady
        case .relayChannelUnavailable:
            return SyncSetupPixelKitEvent.ParameterValue.relayChannelUnavailable
        case .recoveryCodePreparationFailed:
            return SyncSetupPixelKitEvent.ParameterValue.recoveryCodePreparationFailed
        case .peerRecoveryCodeUnavailable:
            return SyncSetupPixelKitEvent.ParameterValue.peerRecoveryCodeUnavailable
        case .unexpectedFailure:
            return SyncSetupPixelKitEvent.ParameterValue.unexpectedFailure
        case .missingThirdPartyCredential:
            return SyncSetupPixelKitEvent.ParameterValue.missingThirdPartyCredential
        case .undecryptableThirdPartyCredential:
            return SyncSetupPixelKitEvent.ParameterValue.undecryptableThirdPartyCredential
        case .accountExtendFailed:
            return SyncSetupPixelKitEvent.ParameterValue.accountExtendFailed
        case .missingThirdPartyKey:
            return SyncSetupPixelKitEvent.ParameterValue.missingThirdPartyKey
        case .localStorageFailed:
            return SyncSetupPixelKitEvent.ParameterValue.localStorageFailed
        }
    }
}
