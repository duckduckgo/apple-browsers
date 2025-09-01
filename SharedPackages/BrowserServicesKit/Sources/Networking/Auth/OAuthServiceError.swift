//
//  OAuthServiceError.swift
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

public enum OAuthServiceError: DDGError {
    case authAPIError(code: OAuthRequest.BodyErrorCode)
    case apiServiceError(Error)
    case invalidRequest
    case invalidResponseCode(HTTPStatusCode)
    case missingResponseValue(String)

    public var description: String {
        switch self {
        case .authAPIError(let code):
            "Auth API responded with error \(code.rawValue) - \(code.description)"
        case .apiServiceError(let error):
            "API service error - \(String(describing: error))"
        case .invalidRequest:
            "Failed to generate the API request"
        case .invalidResponseCode(let code):
            "Invalid API request response code: \(code.rawValue) - \(code.description)"
        case .missingResponseValue(let value):
            "The API response is missing \(value)"
        }
    }

    public var errorDomain: String { "com.duckduckgo.networking.OAuthServiceError" }

    public var errorCode: Int {
        switch self {
        case .authAPIError:
            return 11200
        case .apiServiceError:
            return 11201
        case .invalidRequest:
            return 11202
        case .invalidResponseCode:
            return 11203
        case .missingResponseValue:
            return 11204
        }
    }

    public var underlyingError: Error? {
        switch self {
        case .apiServiceError(let error):
            return error
        default:
            return nil
        }
    }

    public static func == (lhs: OAuthServiceError, rhs: OAuthServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.authAPIError(let lhsCode), .authAPIError(let rhsCode)):
            return lhsCode == rhsCode
        case (.apiServiceError(let lhsError), .apiServiceError(let rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        case (.invalidRequest, .invalidRequest):
            return true
        case (.invalidResponseCode(let lhsCode), .invalidResponseCode(let rhsCode)):
            return lhsCode == rhsCode
        case (.missingResponseValue(let lhsValue), .missingResponseValue(let rhsValue)):
            return lhsValue == rhsValue
        default:
            return false
        }
    }
}
