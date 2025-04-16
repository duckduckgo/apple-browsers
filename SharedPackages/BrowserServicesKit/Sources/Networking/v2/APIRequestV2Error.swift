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

extension APIRequestV2 {

    public enum Error: Swift.Error, LocalizedError, Equatable {

        case urlSession(Swift.Error)
        case invalidResponse
        case unsatisfiedRequirement(APIResponseConstraints)
        case invalidStatusCode(Int)
        case invalidDataType
        case emptyResponseBody
        case invalidURL

        public var errorDescription: String? {
            switch self {
            case .urlSession(let error):
                return "URL session error: \(error.localizedDescription)"
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

        // MARK: - Equatable Conformance
        public static func == (lhs: Error, rhs: Error) -> Bool {
            switch (lhs, rhs) {
            case (.urlSession(let lhsError), .urlSession(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
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

}
