//
//  TokenRecoveryResult+Testing.swift
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
@testable import Subscription

extension TokenRecoveryResult {

    /// The cases of `TokenRecoveryResult` without the error of `.failed`.
    enum Outcome: Equatable {
        case recovered
        case notApplicable
        case sessionChanged
        case failed
    }

    /// The result's case.
    var outcome: Outcome {
        switch self {
        case .recovered: .recovered
        case .notApplicable: .notApplicable
        case .sessionChanged: .sessionChanged
        case .failed: .failed
        }
    }

    /// The error of a `.failed` result, or nil for any other result.
    var failure: Error? {
        if case .failed(let error) = self {
            return error
        }
        return nil
    }
}
