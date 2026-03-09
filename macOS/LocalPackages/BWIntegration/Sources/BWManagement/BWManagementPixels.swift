//
//  BWManagementPixels.swift
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

import PixelKit

enum BWManagementPixels: PixelKitEvent {

    case bitwardenNotResponding
    case bitwardenRespondedCannotDecrypt
    case bitwardenHandshakeFailed
    case bitwardenDecryptionOfSharedKeyFailed
    case bitwardenStoringOfTheSharedKeyFailed
    case bitwardenCredentialRetrievalFailed
    case bitwardenCredentialCreationFailed
    case bitwardenCredentialUpdateFailed
    case bitwardenRespondedWithError
    case bitwardenNoActiveVault
    case bitwardenParsingFailed
    case bitwardenStatusParsingFailed
    case bitwardenHmacComparisonFailed
    case bitwardenDecryptionFailed
    case bitwardenSendingOfMessageFailed
    case bitwardenSharedKeyInjectionFailed

    var name: String {
        switch self {
        case .bitwardenNotResponding:
            return "bitwarden_not_responding"
        case .bitwardenRespondedCannotDecrypt:
            return "bitwarden_responded_cannot_decrypt_d"
        case .bitwardenHandshakeFailed:
            return "bitwarden_handshake_failed"
        case .bitwardenDecryptionOfSharedKeyFailed:
            return "bitwarden_decryption_of_shared_key_failed"
        case .bitwardenStoringOfTheSharedKeyFailed:
            return "bitwarden_storing_of_the_shared_key_failed"
        case .bitwardenCredentialRetrievalFailed:
            return "bitwarden_credential_retrieval_failed"
        case .bitwardenCredentialCreationFailed:
            return "bitwarden_credential_creation_failed"
        case .bitwardenCredentialUpdateFailed:
            return "bitwarden_credential_update_failed"
        case .bitwardenRespondedWithError:
            return "bitwarden_responded_with_error"
        case .bitwardenNoActiveVault:
            return "bitwarden_no_active_vault"
        case .bitwardenParsingFailed:
            return "bitwarden_parsing_failed"
        case .bitwardenStatusParsingFailed:
            return "bitwarden_status_parsing_failed"
        case .bitwardenHmacComparisonFailed:
            return "bitwarden_hmac_comparison_failed"
        case .bitwardenDecryptionFailed:
            return "bitwarden_decryption_failed"
        case .bitwardenSendingOfMessageFailed:
            return "bitwarden_sending_of_message_failed"
        case .bitwardenSharedKeyInjectionFailed:
            return "bitwarden_shared_key_injection_failed"
        }
    }

    var parameters: [String: String]? {
        return nil
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }

}
