//
//  AIChatDataClearingScriptFailure.swift
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

import DDGError
import Foundation

extension AIChatDataClearingUserScript {

    /// The script's reason for a failed clear as a fixed code, so pixels carry no free text:
    /// the stage in the hundreds (1xx localStorage, 2xx IndexedDB, 3xx unexpected) plus the error name in the units.
    struct ScriptFailure: DDGError {

        enum Stage: String {
            case localStorage
            case indexedDB
            case unexpected

            var code: Int {
                switch self {
                case .localStorage: return 100
                case .indexedDB: return 200
                case .unexpected: return 300
                }
            }
        }

        enum ErrorName: String {
            case unknown = "UnknownError"
            case quotaExceeded = "QuotaExceededError"
            case invalidState = "InvalidStateError"
            case abort = "AbortError"
            case notFound = "NotFoundError"
            case version = "VersionError"
            case data = "DataError"
            case transactionInactive = "TransactionInactiveError"
            case security = "SecurityError"
            case type = "TypeError"
            case syntax = "SyntaxError"

            var code: Int {
                switch self {
                case .unknown: return 1
                case .quotaExceeded: return 2
                case .invalidState: return 3
                case .abort: return 4
                case .notFound: return 5
                case .version: return 6
                case .data: return 7
                case .transactionInactive: return 8
                case .security: return 9
                case .type: return 10
                case .syntax: return 11
                }
            }
        }

        let stage: Stage?
        let errorName: ErrorName?

        /// Scripts that predate `stage` and `errorName` only send a free-text `error`, which maps to code 0.
        init(payload: Any) {
            let fields = payload as? [String: Any]
            stage = (fields?["stage"] as? String).flatMap(Stage.init(rawValue:))
            errorName = (fields?["errorName"] as? String).flatMap(ErrorName.init(rawValue:))
        }

        static let errorDomain = "com.duckduckgo.aiChatDataClearing.script"

        var errorCode: Int {
            (stage?.code ?? 0) + (errorName?.code ?? 0)
        }

        var description: String {
            "Duck.ai clearing script failed at stage \(stage?.rawValue ?? "unknown"): \(errorName?.rawValue ?? "unknown error")"
        }
    }
}
