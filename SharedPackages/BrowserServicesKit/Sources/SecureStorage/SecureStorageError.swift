//
//  SecureStorageError.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import GRDB
import PixelKit

public enum SecureStorageDatabaseError: Error, CustomNSError {
    case corruptedDatabase(DatabaseError)
    case migrationFailed(Error)
    case databaseRecreationFailed(Error)

    var underlyingError: Error? {
        switch self {
        case .corruptedDatabase(let dbError): return dbError
        case .migrationFailed(let error): return error
        case .databaseRecreationFailed(let error): return error
        }
    }

    public var errorUserInfo: [String: Any] {
        [:]
    }

    public var errorCode: Int {
        switch self {
        case .corruptedDatabase: return 100
        case .migrationFailed: return 101
        case .databaseRecreationFailed: return 102
        }
    }
}

public enum SecureStorageError: Error {

    case initFailed(cause: Error)
    case authRequired
    case invalidPassword
    case noL1Key
    case noL2Key
    case authError(cause: Error)
    case failedToOpenDatabase(cause: Error)
    case databaseError(cause: Error)
    case duplicateRecord
    case keystoreError(status: Int32)
    case secError(status: Int32)
    case generalCryptoError
    case encodingFailed
    case keystoreReadError(field: String, serviceName: String, status: Int32)
    case keystoreUpdateError(status: Int32)
}

extension SecureStorageError: CustomNSError, ErrorWithPixelParameters {

    /// Uses the legacy "SecureVaultError" name to avoid causing issues with metrics after this was renamed to `SecureStorageError`.
    public static var errorDomain: String { "SecureVaultError" }

    public var errorCode: Int {
        switch self {
        case .initFailed: return 1
        case .authRequired: return 2
        case .invalidPassword: return 3
        case .noL1Key: return 4
        case .noL2Key: return 5
        case .authError: return 6
        case .failedToOpenDatabase: return 7
        case .databaseError: return 8
        case .duplicateRecord: return 9
        case .keystoreError: return 10
        case .secError: return 11
        case .generalCryptoError: return 12
        case .encodingFailed: return 13
        case .keystoreReadError: return 14
        case .keystoreUpdateError: return 15
        }
    }

    public var errorUserInfo: [String: Any] {
        var errorUserInfo = [String: Any]()
        switch self {
        case .initFailed(cause: let error),
                .authError(cause: let error),
                .failedToOpenDatabase(cause: let error),
                .databaseError(cause: let error):
            if let secureVaultError = error as? SecureStorageError {
                return secureVaultError.errorUserInfo
            }

            errorUserInfo["NSUnderlyingError"] = error as NSError
            if let sqliteError = (error as? DatabaseError) ?? ((error as? SecureStorageDatabaseError)?.underlyingError as? DatabaseError) {
                errorUserInfo["SQLiteResultCode"] = NSNumber(value: sqliteError.resultCode.rawValue)
                errorUserInfo["SQLiteExtendedResultCode"] = NSNumber(value: sqliteError.extendedResultCode.rawValue)
            }
        case .keystoreError(status: let code):
            errorUserInfo["NSUnderlyingError"] = NSError(domain: "keystoreError", code: Int(code), userInfo: nil)
        case .keystoreReadError(_, _, status: let code):
            errorUserInfo["NSUnderlyingError"] = NSError(domain: "keystoreReadError", code: Int(code), userInfo: nil)
        case .keystoreUpdateError(status: let code):
            errorUserInfo["NSUnderlyingError"] = NSError(domain: "keystoreUpdateError", code: Int(code), userInfo: nil)
        case .secError(status: let code):
            errorUserInfo["NSUnderlyingError"] = NSError(domain: "secError", code: Int(code), userInfo: nil)
        case .authRequired, .invalidPassword, .noL1Key, .noL2Key, .duplicateRecord, .generalCryptoError, .encodingFailed:
            errorUserInfo["NSUnderlyingError"] = NSError(domain: "\(self)", code: 0, userInfo: nil)
        }

        return errorUserInfo
    }

    public var errorParameters: [String: String] {
        switch self {
        case .initFailed(cause: let error),
                .authError(cause: let error),
                .failedToOpenDatabase(cause: let error),
                .databaseError(cause: let error):
            if let underlyingError = (error as? SecureStorageDatabaseError)?.underlyingError as? NSError {
                return ["ud2": underlyingError.domain,
                        "ue2": String(underlyingError.code)]
            } else {
                return [:]
            }
        case .keystoreReadError(let field, _, _):
            return ["keystoreField": field]
        default:
            return [:]
        }
    }
}
