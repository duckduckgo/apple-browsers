//
//  APIServiceMock.swift
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
import Subscription

public final class APIServiceMock: SubscriptionAPIService {
    public var mockAuthHeaders: [String: String] = [String: String]()

    public var mockResponseJSONData: Data?
    public var mockAPICallSuccessResult: Any?
    public var mockAPICallError: APIServiceError?

    public var onExecuteAPICall: ((ExecuteAPICallParameters) -> Void)?

    public typealias ExecuteAPICallParameters = (method: String, endpoint: String, headers: [String: String]?, body: Data?)

    public init() { }

    // swiftlint:disable force_cast
    public func executeAPICall<T>(method: String, endpoint: String, headers: [String: String]?, body: Data?) async -> Result<T, APIServiceError> where T: Decodable {

        onExecuteAPICall?(ExecuteAPICallParameters(method, endpoint, headers, body))

        if let data = mockResponseJSONData {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .millisecondsSince1970

            if let decodedResponse = try? decoder.decode(T.self, from: data) {
                return .success(decodedResponse)
            } else {
                return .failure(.decodingError)
            }
        } else if let success = mockAPICallSuccessResult {
            return .success(success as! T)
        } else if let error = mockAPICallError {
            return .failure(error)
        }

        return .failure(.unknownServerError)
    }
    // swiftlint:enable force_cast

    public func makeAuthorizationHeader(for token: String) -> [String: String] {
        return mockAuthHeaders
    }
}
