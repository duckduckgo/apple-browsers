//
//  APIRequestConfiguration.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

extension APIRequest {

    public struct Configuration<QueryParams: Collection> where QueryParams.Element == (key: String, value: String) {

        let url: URL
        let method: APIRequest.HTTPMethod
        let queryParameters: QueryParams
        let allowedQueryReservedCharacters: CharacterSet?
        let headers: HTTPHeaders
        let body: Data?
        let timeoutInterval: TimeInterval
        let cachePolicy: URLRequest.CachePolicy?

        public init(url: URL,
                    method: APIRequest.HTTPMethod = .get,
                    queryParameters: QueryParams = [],
                    allowedQueryReservedCharacters: CharacterSet? = nil,
                    headers: APIRequest.Headers = APIRequest.Headers(),
                    body: Data? = nil,
                    timeoutInterval: TimeInterval = 60.0,
                    cachePolicy: URLRequest.CachePolicy? = nil) {
            self.url = url
            self.method = method
            self.queryParameters = queryParameters
            self.allowedQueryReservedCharacters = allowedQueryReservedCharacters
            self.headers = headers.httpHeaders
            self.body = body
            self.timeoutInterval = timeoutInterval
            self.cachePolicy = cachePolicy
        }

        var request: URLRequest {
            let url = url.appendingParameters(queryParameters, allowedReservedCharacters: allowedQueryReservedCharacters)
            var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
            request.allHTTPHeaderFields = headers
            request.httpMethod = method.rawValue
            request.httpBody = body
            if let cachePolicy = cachePolicy {
                request.cachePolicy = cachePolicy
            }
            return request
        }

    }

}
