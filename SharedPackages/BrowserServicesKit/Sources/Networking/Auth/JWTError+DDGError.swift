//
//  JWTError+DDGError.swift
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

import Foundation
import JWTKit
import Common

extension JWTError: @retroactive Equatable {}
extension JWTError: @retroactive CustomNSError {}
extension JWTError: DDGError {

    public var description: String {
        return self.reason
    }

    public static var errorDomain: String { "com.duckduckgo.networking.JWTError" }

    public var errorCode: Int {
        switch self {
        case .claimVerificationFailure:
            return 1
        case .signingAlgorithmFailure:
            return 2
        case .malformedToken:
            return 3
        case .signatureVerifictionFailed:
            return 4
        case .missingKIDHeader:
            return 5
        case .unknownKID:
            return 6
        case .invalidJWK:
            return 7
        case .invalidBool:
            return 8
        case .generic:
            return 9
        }
    }

    public static func == (lhs: JWTError, rhs: JWTError) -> Bool {
        lhs.errorCode == rhs.errorCode
    }
}
