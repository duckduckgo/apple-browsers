//
//  AccountKeychainAccessError.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Common

public enum AccountKeychainAccessError: DDGError {
    case failedToDecodeKeychainData
    case failedToDecodeKeychainValueAsData
    case failedToDecodeKeychainDataAsString
    case failedToEncodeKeychainData
    case keychainSaveFailure(OSStatus)
    case keychainDeleteFailure(OSStatus)
    case keychainLookupFailure(OSStatus)
    case expectedTokenNotFound

    public var description: String {
        switch self {
        case .failedToDecodeKeychainData:
            return "failedToDecodeKeychainData"
        case .failedToDecodeKeychainValueAsData:
            return "failedToDecodeKeychainValueAsData"
        case .failedToDecodeKeychainDataAsString:
            return "failedToDecodeKeychainDataAsString"
        case .failedToEncodeKeychainData:
            return "failedToEncodeKeychainData"
        case .keychainSaveFailure(let status):
            return "keychainSaveFailure(\(status) - \(status.humanReadableDescription))"
        case .keychainDeleteFailure(let status):
            return "keychainDeleteFailure(\(status) - \(status.humanReadableDescription))"
        case .keychainLookupFailure(let status):
            return "keychainLookupFailure(\(status) - \(status.humanReadableDescription))"
        case .expectedTokenNotFound:
            return "expectedTokenNotFound"
        }
    }

    public static var errorDomain: String { "com.duckduckgo.subscription.AccountKeychainAccessError" }

    public var errorCode: Int {
        switch self {
        case .failedToDecodeKeychainData:
            return 12400
        case .failedToDecodeKeychainValueAsData:
            return 12401
        case .failedToDecodeKeychainDataAsString:
            return 12402
        case .failedToEncodeKeychainData:
            return 12403
        case .keychainSaveFailure:
            return 12404
        case .keychainDeleteFailure:
            return 12405
        case .keychainLookupFailure:
            return 12406
        case .expectedTokenNotFound:
            return 12407
        }
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .failedToDecodeKeychainData,
                .failedToDecodeKeychainValueAsData,
                .failedToDecodeKeychainDataAsString,
                .failedToEncodeKeychainData,
                .expectedTokenNotFound:
            return nil
        case .keychainSaveFailure(let oSStatus),
                .keychainDeleteFailure(let oSStatus),
                .keychainLookupFailure(let oSStatus):
            return NSError(domain: AccountKeychainAccessError.errorDomain, code: Int(oSStatus))
        }
    }
}
