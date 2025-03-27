//
//  AuthChallengeDisposition.swift
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

public enum AuthChallengeDisposition: Sendable {

    /// Use the specified credential
    case credential(URLCredential)
    /// The entire request will be canceled
    case cancel
    /// This challenge is rejected and the next authentication protection space should be tried
    case rejectProtectionSpace

    var dispositionAndCredential: (URLSession.AuthChallengeDisposition, URLCredential?) {
        switch self {
        case .credential(let credential):
            return (.useCredential, credential)
        case .cancel:
            return (.cancelAuthenticationChallenge, nil)
        case .rejectProtectionSpace:
            return (.rejectProtectionSpace, nil)
        }
    }

    var description: String {
        switch self {
        case .credential:
            return "credential"
        case .cancel:
            return "cancel"
        case .rejectProtectionSpace:
            return "rejectProtectionSpace"
        }
    }

}

public extension AuthChallengeDisposition? {
    /// Pass challenge to next responder
    static let next = AuthChallengeDisposition?.none
}
