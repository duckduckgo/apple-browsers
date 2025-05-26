//
//  MockAPIService.swift
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
@testable import Networking

public class MockAPIService: APIService {

    public var authorizationRefresherCallback: AuthorizationRefresherCallback?

    /// Dictionary to store mocked responses for specific requests
    private var mockResponses: [APIRequestV2: APIResponseV2] = [:]
    /// Dictionary to store mocked responses for specific requests by URL
    private var mockResponsesByURL: [URL: APIResponseV2] = [:]
    /// Request handler
    public var requestHandler: ((APIRequestV2) -> Result<APIResponseV2, Error>)?

    public init(requestHandler: ((APIRequestV2) -> Result<APIResponseV2, Error>)? = nil) {
        self.requestHandler = requestHandler
    }

    public func set(response: APIResponseV2, forRequest request: APIRequestV2) {
        mockResponses[request] = response
    }

    public func set(response: APIResponseV2, forRequestURL url: URL) {
        mockResponsesByURL[url] = response
    }

    // Function to fetch response for a given request
    public func fetch(request: Networking.APIRequestV2) async throws -> Networking.APIResponseV2 {
        if let requestHandler {
            switch requestHandler(request) {
                    case .success(let result):
                        return result
                    case .failure(let error):
                        throw error
                    }
        } else if let response = mockResponses[request] {
            return response
        } else {
            return mockResponsesByURL[request.urlRequest.url!]! // Intentionally crash if the mock is not available
        }
    }
}

public extension APIRequestV2 {
    var host: String {
        return urlRequest.url!.host!
    }
}
