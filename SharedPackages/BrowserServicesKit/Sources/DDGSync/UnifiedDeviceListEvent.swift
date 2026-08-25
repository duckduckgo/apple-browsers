//
//  UnifiedDeviceListEvent.swift
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

/// Privacy-safe outcomes for the unified Sync device list. Associated values are deliberately
/// bounded enums so device, account, credential, and key identifiers can never reach pixels.
public enum UnifiedDeviceListEvent: Equatable {

    public enum Frequency: Equatable {
        case standard
        case daily
    }

    public enum DeviceInfoFallbackReason: String, Equatable {
        case notPublishedYet = "not_published_yet"
        case blobAbsent = "blob_absent"
        case blobDecryptFailed = "blob_decrypt_failed"
    }

    public enum AccountInfoKeyUnavailableReason: String, Equatable {
        case noKeyOnServer = "no_key_on_server"
        case noWrapForOurCredential = "no_wrap_for_our_credential"
        case unwrapFailed = "unwrap_failed"
        case invalidKeyMaterial = "invalid_key_material"
        case keysFetchFailed = "keys_fetch_failed"
        case rateLimited = "rate_limited"
    }

    public enum Credential: String, Equatable {
        case ddg
        case thirdParty = "3party"
        case none
    }

    public enum AccountInfoKeyAdoptFailureReason: String, Equatable {
        case keysFetchFailed = "keys_fetch_failed"
        case rateLimited = "rate_limited"
    }

    public enum AccountInfoKeyCreateFailureReason: String, Equatable {
        case mintFailed = "mint_failed"
        case requestFailed = "request_failed"
        case rateLimited = "rate_limited"
    }

    public enum AccountInfoKeyWrapFailureReason: String, Equatable {
        case unwrapFailed = "unwrap_failed"
        case requestFailed = "request_failed"
        case rateLimited = "rate_limited"
    }

    public enum DeviceInfoWriteFailureReason: String, Equatable {
        case encryptFailed = "encrypt_failed"
        case requestFailed = "request_failed"
        case rateLimited = "rate_limited"
        case persistFailed = "persist_failed"
    }

    case ownRowResolvedDeviceInfo
    case ownRowResolvedLegacy(DeviceInfoFallbackReason)
    case ownRowResolvedPlaceholder(DeviceInfoFallbackReason)
    case accountInfoKeyUnavailable(AccountInfoKeyUnavailableReason)
    case otherRowDeviceInfoFailedDecryption(Credential)
    case otherRowResolvedPlaceholder(Credential)

    case accountInfoKeyAdoptFailed(AccountInfoKeyAdoptFailureReason)
    case accountInfoKeyCreateSuccess
    case accountInfoKeyCreateFailed(AccountInfoKeyCreateFailureReason)
    case accountInfoKeyWrapSuccess
    case accountInfoKeyWrapFailed(AccountInfoKeyWrapFailureReason)
    case accountInfoKeyAdoptSuccess

    case ownRowDeviceInfoFirstWriteSuccess
    case ownRowDeviceInfoFirstWriteFailed(DeviceInfoWriteFailureReason)
    case ownRowDeviceInfoUpdateSuccess
    case ownRowDeviceInfoUpdateFailed(DeviceInfoWriteFailureReason)
    case ownRowDeviceInfoRepairSuccess
    case ownRowDeviceInfoRepairFailed(DeviceInfoWriteFailureReason)

    public var name: String {
        let prefix = "sync_unified_devices_"
        switch self {
        case .ownRowResolvedDeviceInfo:
            return prefix + "own_row_resolved_device_info"
        case .ownRowResolvedLegacy:
            return prefix + "own_row_resolved_legacy"
        case .ownRowResolvedPlaceholder:
            return prefix + "own_row_resolved_placeholder"
        case .accountInfoKeyUnavailable:
            return prefix + "account_info_key_unavailable"
        case .otherRowDeviceInfoFailedDecryption:
            return prefix + "other_row_device_info_failed_decryption"
        case .otherRowResolvedPlaceholder:
            return prefix + "other_row_resolved_placeholder"
        case .accountInfoKeyAdoptFailed:
            return prefix + "account_info_key_adopt_failed"
        case .accountInfoKeyCreateSuccess:
            return prefix + "account_info_key_create_success"
        case .accountInfoKeyCreateFailed:
            return prefix + "account_info_key_create_failed"
        case .accountInfoKeyWrapSuccess:
            return prefix + "account_info_key_wrap_success"
        case .accountInfoKeyWrapFailed:
            return prefix + "account_info_key_wrap_failed"
        case .accountInfoKeyAdoptSuccess:
            return prefix + "account_info_key_adopt_success"
        case .ownRowDeviceInfoFirstWriteSuccess:
            return prefix + "own_row_device_info_first_write_success"
        case .ownRowDeviceInfoFirstWriteFailed:
            return prefix + "own_row_device_info_first_write_failed"
        case .ownRowDeviceInfoUpdateSuccess:
            return prefix + "own_row_device_info_update_success"
        case .ownRowDeviceInfoUpdateFailed:
            return prefix + "own_row_device_info_update_failed"
        case .ownRowDeviceInfoRepairSuccess:
            return prefix + "own_row_device_info_repair_success"
        case .ownRowDeviceInfoRepairFailed:
            return prefix + "own_row_device_info_repair_failed"
        }
    }

    public var parameters: [String: String]? {
        switch self {
        case .ownRowResolvedLegacy(let reason),
             .ownRowResolvedPlaceholder(let reason):
            return ["reason": reason.rawValue]
        case .accountInfoKeyUnavailable(let reason):
            return ["reason": reason.rawValue]
        case .otherRowDeviceInfoFailedDecryption(let credential),
             .otherRowResolvedPlaceholder(let credential):
            return ["credential": credential.rawValue]
        case .accountInfoKeyAdoptFailed(let reason):
            return ["reason": reason.rawValue]
        case .accountInfoKeyCreateFailed(let reason):
            return ["reason": reason.rawValue]
        case .accountInfoKeyWrapFailed(let reason):
            return ["reason": reason.rawValue]
        case .ownRowDeviceInfoFirstWriteFailed(let reason),
             .ownRowDeviceInfoUpdateFailed(let reason),
             .ownRowDeviceInfoRepairFailed(let reason):
            return ["reason": reason.rawValue]
        default:
            return nil
        }
    }

    public var frequency: Frequency {
        switch self {
        case .ownRowResolvedDeviceInfo,
             .ownRowResolvedLegacy,
             .ownRowResolvedPlaceholder,
             .accountInfoKeyUnavailable,
             .otherRowDeviceInfoFailedDecryption,
             .otherRowResolvedPlaceholder,
             .accountInfoKeyAdoptFailed,
             .accountInfoKeyCreateFailed,
             .accountInfoKeyWrapFailed,
             .ownRowDeviceInfoFirstWriteFailed,
             .ownRowDeviceInfoUpdateFailed,
             .ownRowDeviceInfoRepairFailed:
            return .daily
        case .accountInfoKeyCreateSuccess,
             .accountInfoKeyWrapSuccess,
             .accountInfoKeyAdoptSuccess,
             .ownRowDeviceInfoFirstWriteSuccess,
             .ownRowDeviceInfoUpdateSuccess,
             .ownRowDeviceInfoRepairSuccess:
            return .standard
        }
    }
}

enum UnifiedDeviceListTelemetry {

    static func accountInfoKeyUnavailableReason(for error: Error) -> UnifiedDeviceListEvent.AccountInfoKeyUnavailableReason {
        if let keyError = error as? AccountInfoKeyManagerError {
            switch keyError {
            case .missingProtectedKey:
                return .noKeyOnServer
            case .unavailableWrappingKey:
                return .noWrapForOurCredential
            case .invalidProtectedKeySet, .publicKeyMismatch:
                return .invalidKeyMaterial
            case .unableToUnwrapPrivateKey:
                return .unwrapFailed
            }
        }
        if let syncError = error as? SyncError {
            if case .unexpectedStatusCode(let statusCode) = syncError, statusCode == 429 {
                return .rateLimited
            }
            if case .failedToDecryptValue = syncError {
                return .unwrapFailed
            }
            return .keysFetchFailed
        }
        if error is URLError {
            return .keysFetchFailed
        }
        if error is RSAKeyImportError {
            return .invalidKeyMaterial
        }
        return .unwrapFailed
    }

    static func keyAdoptFailureReason(for error: Error) -> UnifiedDeviceListEvent.AccountInfoKeyAdoptFailureReason {
        isRateLimited(error) ? .rateLimited : .keysFetchFailed
    }

    static func keyCreateRequestFailureReason(for error: Error) -> UnifiedDeviceListEvent.AccountInfoKeyCreateFailureReason {
        isRateLimited(error) ? .rateLimited : .requestFailed
    }

    static func keyWrapRequestFailureReason(for error: Error) -> UnifiedDeviceListEvent.AccountInfoKeyWrapFailureReason {
        isRateLimited(error) ? .rateLimited : .requestFailed
    }

    static func deviceInfoRequestFailureReason(for error: Error) -> UnifiedDeviceListEvent.DeviceInfoWriteFailureReason {
        isRateLimited(error) ? .rateLimited : .requestFailed
    }

    private static func isRateLimited(_ error: Error) -> Bool {
        if let syncError = error as? SyncError,
           case .unexpectedStatusCode(let statusCode) = syncError {
            return statusCode == 429
        }
        return false
    }
}
