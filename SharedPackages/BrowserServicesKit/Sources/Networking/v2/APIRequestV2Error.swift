//
//  APIRequestV2Error.swift
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
import Common

public enum APIRequestV2Error: DDGError {

    case urlSession(Error)
    case invalidResponse
    case unsatisfiedRequirement(APIResponseConstraints)
    case invalidStatusCode(Int)
    case invalidDataType
    case emptyResponseBody
    case invalidURL

    public var description: String {
        switch self {
        case .urlSession(let error):
            return "URL session error: \(String(describing: error))"
        case .invalidResponse:
            return "Invalid response received."
        case .unsatisfiedRequirement(let requirement):
            return "The response doesn't satisfy the requirement: \(requirement.rawValue)"
        case .invalidStatusCode(let statusCode):
            return "Invalid status code received in response (\(statusCode))."
        case .invalidDataType:
            return "Invalid response data type"
        case .emptyResponseBody:
            return "The response body is nil"
        case .invalidURL:
            return "Invalid URL"
        }
    }

    public var errorDomain: String { "com.duckduckgo.networking.APIRequestV2" }

    public var errorCode: Int {
        switch self {
        case .urlSession:
            return 11400
        case .invalidResponse:
            return 11401
        case .unsatisfiedRequirement:
            return 11402
        case .invalidStatusCode:
            return 11403
        case .invalidDataType:
            return 11404
        case .emptyResponseBody:
            return 11405
        case .invalidURL:
            return 11406
        }
    }

    public var underlyingError: Error? {
        switch self {
        case .urlSession(let error):
            return error
        default:
            return nil
        }
    }

    // MARK: - Equatable Conformance
    public static func == (lhs: APIRequestV2Error, rhs: APIRequestV2Error) -> Bool {
        switch (lhs, rhs) {
        case (.urlSession(let lhsError), .urlSession(let rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        case (.invalidResponse, .invalidResponse):
            return true
        case (.unsatisfiedRequirement(let lhsRequirement), .unsatisfiedRequirement(let rhsRequirement)):
            return lhsRequirement == rhsRequirement
        case (.invalidStatusCode(let lhsStatusCode), .invalidStatusCode(let rhsStatusCode)):
            return lhsStatusCode == rhsStatusCode
        case (.invalidDataType, .invalidDataType):
            return true
        case (.emptyResponseBody, .emptyResponseBody):
            return true
        case (.invalidURL, .invalidURL):
            return true
        default:
            return false
        }
    }

    public var isTimedOut: Bool {
        if case .urlSession(URLError.timedOut) = self {
            true
        } else {
            false
        }
    }
}
