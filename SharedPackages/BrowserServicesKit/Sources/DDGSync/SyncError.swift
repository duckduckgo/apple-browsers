//
//  SyncError.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public enum SyncError: Error, Equatable {

    public enum AccountRemovedReason: String, Equatable {
        case authStateInactive = "auth-state-inactive"
        case syncEnabledNotSetOnKeyValueStore = "not-set-on-key-value-store2"
        case notFoundInSecureStorage = "not-found-in-secure-storage"
        case userTurnedOffSync = "user-turned-off"
        case userDeletedAccount = "user-deleted-account"
        case unauthenticatedRequest = "unauthenticated-request"
        case serverEnvironmentUpdated = "server-environment-updated"
    }

    case noToken

    case migratedToFileStore
    case failedToMigrateToFileStore
    case failedToInitFileStore

    case failedToLoadAccount
    case failedToSetupEngine
    case failedToRemoveAccount

    case failedToCreateAccountKeys(_ message: String)
    case accountNotFound
    case accountAlreadyExists
    case invalidRecoveryKey

    case noFeaturesSpecified
    case noResponseBody
    case unexpectedStatusCode(Int)
    case unexpectedResponseBody
    case unableToEncodeRequestBody(_ message: String)
    case unableToDecodeResponse(_ message: String)
    case invalidDataInResponse(_ message: String)
    case accountRemoved(_ reason: AccountRemovedReason)

    case failedToEncryptValue(_ message: String)
    case failedToDecryptValue(_ message: String)
    case failedToPrepareForConnect(_ message: String)
    case failedToPrepareForExchange(_ message: String)
    case failedToOpenSealedBox(_ message: String)
    case failedToSealData(_ message: String)

    case failedToWriteSecureStore(status: OSStatus)
    case failedToReadSecureStore(status: OSStatus)
    case failedToRemoveSecureStore(status: OSStatus)
    case failedToDecodeSecureStoreData(error: NSError)

    case credentialsMetadataMissingBeforeFirstSync
    case receivedCredentialsWithoutUUID

    case emailProtectionUsernamePresentButTokenMissing
    case settingsMetadataNotPresent

    case unauthenticatedWhileLoggedIn
    case patchPayloadCompressionFailed(_ errorCode: Int)

    case pollingDidTimeOut

    public var isServerError: Bool {
        switch self {
        case .noResponseBody,
                .unexpectedStatusCode,
                .unexpectedResponseBody,
                .invalidDataInResponse:
            return true
        default:
            return false
        }
    }

    var syncErrorString: String {
        return "syncError"
    }
    var syncErrorMessage: String {
        return "syncErrorMessage"
    }

    public var errorParameters: [String: String] {
        switch self {
        case .noToken:
            return [syncErrorString: "noToken"]
        case .migratedToFileStore:
            return [syncErrorString: "migratedToFileStore"]
        case .failedToInitFileStore:
            return [syncErrorString: "failedToInitFileStore"]
        case .failedToMigrateToFileStore:
            return [syncErrorString: "failedToMigrateToFileStore"]
        case .failedToLoadAccount:
            return [syncErrorString: "failedToLoadAccount"]
        case .failedToSetupEngine:
            return [syncErrorString: "failedToSetupEngine"]
        case .failedToCreateAccountKeys:
            return [syncErrorString: "failedToCreateAccountKeys"]
        case .accountNotFound:
            return [syncErrorString: "accountNotFound"]
        case .accountAlreadyExists:
            return [syncErrorString: "accountAlreadyExists"]
        case .invalidRecoveryKey:
            return [syncErrorString: "invalidRecoveryKey"]
        case .noFeaturesSpecified:
            return [syncErrorString: "noFeaturesSpecified"]
        case .noResponseBody:
            return [syncErrorString: "noResponseBody"]
        case .unexpectedStatusCode:
            return [syncErrorString: "unexpectedStatusCode"]
        case .unexpectedResponseBody:
            return [syncErrorString: "unexpectedResponseBody"]
        case .unableToEncodeRequestBody:
            return [syncErrorString: "unableToEncodeRequestBody"]
        case .unableToDecodeResponse:
            return [syncErrorString: "unableToDecodeResponse"]
        case .invalidDataInResponse:
            return [syncErrorString: "invalidDataInResponse"]
        case .accountRemoved:
            return [syncErrorString: "accountRemoved"]
        case .failedToEncryptValue:
            return [syncErrorString: "failedToEncryptValue"]
        case .failedToDecryptValue:
            return [syncErrorString: "failedToDecryptValue"]
        case .failedToPrepareForConnect:
            return [syncErrorString: "failedToPrepareForConnect"]
        case .failedToPrepareForExchange:
            return [syncErrorString: "failedToPrepareForExchange"]
        case .failedToOpenSealedBox:
            return [syncErrorString: "failedToOpenSealedBox"]
        case .failedToSealData:
            return [syncErrorString: "failedToSealData"]
        case .failedToWriteSecureStore:
            return [syncErrorString: "failedToWriteSecureStore"]
        case .failedToReadSecureStore:
            return [syncErrorString: "failedToReadSecureStore"]
        case .failedToRemoveSecureStore:
            return [syncErrorString: "failedToRemoveSecureStore"]
        case .credentialsMetadataMissingBeforeFirstSync:
            return [syncErrorString: "credentialsMetadataMissingBeforeFirstSync"]
        case .receivedCredentialsWithoutUUID:
            return [syncErrorString: "receivedCredentialsWithoutUUID"]
        case .emailProtectionUsernamePresentButTokenMissing:
            return [syncErrorString: "emailProtectionUsernamePresentButTokenMissing"]
        case .settingsMetadataNotPresent:
            return [syncErrorString: "settingsMetadataNotPresent"]
        case .unauthenticatedWhileLoggedIn:
            return [syncErrorString: "unauthenticatedWhileLoggedIn"]
        case .patchPayloadCompressionFailed:
            return [syncErrorString: "patchPayloadCompressionFailed"]
        case .failedToRemoveAccount:
            return [syncErrorString: "failedToRemoveAccount"]
        case .failedToDecodeSecureStoreData:
            return [syncErrorString: "failedToDecodeSecureStoreData"]
        case .pollingDidTimeOut:
            return [syncErrorString: "pollingDidTimeOut"]
        }
    }
}

extension SyncError: CustomNSError {

    /**
     * The mapping here can't be changed, or it will skew usage metrics.
     */
    public var errorCode: Int {
        switch self {
        case .noToken: return 13

        case .failedToMigrateToFileStore: return 32
        case .migratedToFileStore: return 33
        case .failedToInitFileStore: return 34
        case .failedToLoadAccount: return 15
        case .failedToSetupEngine: return 16

        case .failedToCreateAccountKeys: return 0
        case .accountNotFound: return 17
        case .accountAlreadyExists: return 18
        case .invalidRecoveryKey: return 19

        case .noFeaturesSpecified: return 20
        case .noResponseBody: return 21
        case .unexpectedStatusCode: return 1
        case .unexpectedResponseBody: return 22
        case .unableToEncodeRequestBody: return 2
        case .unableToDecodeResponse: return 3
        case .invalidDataInResponse: return 4
        case .accountRemoved: return 23

        case .failedToEncryptValue: return 5
        case .failedToDecryptValue: return 6
        case .failedToPrepareForConnect: return 7
        case .failedToPrepareForExchange: return 32
        case .failedToOpenSealedBox: return 8
        case .failedToSealData: return 9

        case .failedToWriteSecureStore: return 10
        case .failedToReadSecureStore: return 11
        case .failedToRemoveSecureStore: return 12

        case .credentialsMetadataMissingBeforeFirstSync: return 24
        case .receivedCredentialsWithoutUUID: return 25
        case .emailProtectionUsernamePresentButTokenMissing: return 26
        case .settingsMetadataNotPresent: return 27
        case .unauthenticatedWhileLoggedIn: return 28
        case .patchPayloadCompressionFailed: return 29
        case .failedToRemoveAccount: return 30
        case .failedToDecodeSecureStoreData: return 31

        case .pollingDidTimeOut: return 35
        }
    }

    public var errorUserInfo: [String: Any] {
        switch self {
        case .failedToReadSecureStore(let status),
                .failedToWriteSecureStore(let status),
                .failedToRemoveSecureStore(let status):
            let underlyingError = NSError(domain: "secError", code: Int(status))
            return [NSUnderlyingErrorKey: underlyingError]
        case .failedToDecodeSecureStoreData(let error):
            return [NSUnderlyingErrorKey: error]
        default:
            return [:]
        }
    }

}
