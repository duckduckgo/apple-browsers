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

public enum OAuthServiceError: Error, LocalizedError, Equatable {
    case authAPIError(code: OAuthRequest.BodyErrorCode)
    case apiServiceError(Error)
    case invalidRequest
    case invalidResponseCode(HTTPStatusCode)
    case missingResponseValue(String)

    public var errorDescription: String? {
        switch self {
        case .authAPIError(let code):
            "Auth API responded with error \(code.rawValue) - \(code.description)"
        case .apiServiceError(let error):
            "API service error - \(error.localizedDescription)"
        case .invalidRequest:
            "Failed to generate the API request"
        case .invalidResponseCode(let code):
            "Invalid API request response code: \(code.rawValue) - \(code.description)"
        case .missingResponseValue(let value):
            "The API response is missing \(value)"
        }
    }

    public var localizedDescription: String {
        errorDescription ?? "Unknown"
    }

    public static func == (lhs: OAuthServiceError, rhs: OAuthServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.authAPIError(let lhsCode), .authAPIError(let rhsCode)):
            return lhsCode == rhsCode
        case (.apiServiceError(let lhsError), .apiServiceError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
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

extension OAuthServiceError: CustomNSError {

    public static var errorDomain: String { "com.duckduckgo.networking.oauthservice" }

    public var errorCode: Int {
        switch self {
        case .authAPIError(code: let code):
            77000
        case .apiServiceError(_):
            77001
        case .invalidRequest:
            77002
        case .invalidResponseCode(_):
            77003
        case .missingResponseValue(_):
            77004
        }
    }

    public var errorUserInfo: [String : Any] {
        var underlyingError: NSError?
        switch self {
        case .authAPIError(code: let code):
            underlyingError = NSError(domain: Self.errorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: code])
        case .apiServiceError(let error):
            underlyingError = error as NSError
        case .invalidRequest:
            break
        case .invalidResponseCode(let code):
            underlyingError = NSError(domain: Self.errorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: code])
        case .missingResponseValue(let missingValue):
            underlyingError = NSError(domain: Self.errorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: missingValue])
        }
        return [
            NSLocalizedDescriptionKey: errorDescription ?? "nil",
            NSUnderlyingErrorKey: underlyingError ?? NSNull()
        ]
    }
}
