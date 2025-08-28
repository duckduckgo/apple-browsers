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

    public var description: String {
        switch self {
        case .failedToDecodeKeychainData: "failedToDecodeKeychainData"
        case .failedToDecodeKeychainValueAsData: "failedToDecodeKeychainValueAsData"
        case .failedToDecodeKeychainDataAsString: "failedToDecodeKeychainDataAsString"
        case .failedToEncodeKeychainData: "failedToEncodeKeychainData"
        case .keychainSaveFailure(let status): "keychainSaveFailure(\(status) - \(status.humanReadableDescription))"
        case .keychainDeleteFailure(let status): "keychainDeleteFailure(\(status) - \(status.humanReadableDescription))"
        case .keychainLookupFailure(let status): "keychainLookupFailure(\(status) - \(status.humanReadableDescription))"
        }
    }

    public static var errorDomain: String { "com.duckduckgo.subscription.AccountKeychainAccessError" }

    public var errorCode: Int {
        switch self {
        case .failedToDecodeKeychainData: 12400
        case .failedToDecodeKeychainValueAsData: 12401
        case .failedToDecodeKeychainDataAsString: 12402
        case .failedToEncodeKeychainData: 12403
        case .keychainSaveFailure: 12404
        case .keychainDeleteFailure: 12405
        case .keychainLookupFailure: 12406
        }
    }
}
