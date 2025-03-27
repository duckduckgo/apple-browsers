//
//  RemoteAPIRequestCreator.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Common
import os.log
public struct RemoteAPIRequestCreator: RemoteAPIRequestCreating {

    public func createRequest(url: URL,
                              method: APIRequest.HTTPMethod,
                              headers: HTTPHeaders,
                              parameters: [String: String],
                              body: Data?,
                              contentType: String?) -> HTTPRequesting {

        var requestHeaders = headers
        if let contentType {
            requestHeaders["Content-Type"] = contentType
        }

        let headers = APIRequest.Headers(additionalHeaders: requestHeaders)
        let configuration = APIRequest.Configuration(url: url,
                                                     method: method,
                                                     queryParameters: parameters,
                                                     headers: headers,
                                                     body: body)

        if let body {
            Logger.sync.debug("\(method.rawValue, privacy: .public) request body: \(String(bytes: body, encoding: .utf8) ?? "", privacy: .public)")
        }

        return APIRequest(configuration: configuration, requirements: [.allowHTTPNotModified])
    }
}

extension APIRequest: HTTPRequesting {

    public func execute() async throws -> HTTPResult {
        do {
            let (data, response) = try await fetch()
            return .init(data: data, response: response)
        } catch APIRequest.Error.invalidStatusCode(let code) {
            throw SyncError.unexpectedStatusCode(code)
        }
    }
}
