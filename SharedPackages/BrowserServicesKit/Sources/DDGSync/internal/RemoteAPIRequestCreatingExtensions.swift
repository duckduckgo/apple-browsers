//
//  RemoteAPIRequestCreatingExtensions.swift
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
import Networking

extension RemoteAPIRequestCreating {

    func createAuthenticatedGetRequest(url: URL,
                                       authToken: String,
                                       headers: [String: String] = [:],
                                       parameters: [String: String] = [:]) -> HTTPRequesting {
        var headers = headers
        headers["Authorization"] = "Bearer \(authToken)"
        return createRequest(
            url: url,
            method: .get,
            headers: headers,
            parameters: parameters,
            body: nil,
            contentType: nil
        )
    }

    func createAuthenticatedJSONRequest(url: URL,
                                        method: APIRequest.HTTPMethod,
                                        authToken: String,
                                        json: Data? = nil,
                                        headers: [String: String] = [:],
                                        parameters: [String: String] = [:]) -> HTTPRequesting {
        var headers = headers
        headers["Authorization"] = "Bearer \(authToken)"
        return createRequest(
            url: url,
            method: method,
            headers: headers,
            parameters: parameters,
            body: json,
            contentType: "application/json"
        )
    }

    func createUnauthenticatedJSONRequest(url: URL,
                                          method: APIRequest.HTTPMethod,
                                          json: Data,
                                          headers: [String: String] = [:],
                                          parameters: [String: String] = [:]) -> HTTPRequesting {
         return createRequest(
            url: url,
            method: method,
            headers: headers,
            parameters: parameters,
            body: json,
            contentType: "application/json"
        )
    }

}
