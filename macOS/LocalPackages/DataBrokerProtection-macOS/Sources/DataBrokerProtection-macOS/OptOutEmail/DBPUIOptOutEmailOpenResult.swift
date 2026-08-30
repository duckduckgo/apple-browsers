//
//  DBPUIOptOutEmailOpenResult.swift
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

enum DBPUIOptOutEmailOpenFailure: Equatable {
    case noMailHandler
    case unsupportedMailHandler(String)
    case appleMailComposeUnavailable
    case composeURLBuildFailed(providerName: String)
    case workspaceOpenFailed(providerName: String)
}

enum DBPUIOptOutEmailOpenResult: Equatable {
    case opened(providerName: String)
    case failed(providerName: String, failure: DBPUIOptOutEmailOpenFailure)

    var didOpen: Bool {
        switch self {
        case .opened:
            return true
        case .failed:
            return false
        }
    }

    var providerName: String {
        switch self {
        case .opened(let providerName),
             .failed(let providerName, _):
            return providerName
        }
    }

    var failure: DBPUIOptOutEmailOpenFailure? {
        switch self {
        case .opened:
            return nil
        case .failed(_, let failure):
            return failure
        }
    }
}
