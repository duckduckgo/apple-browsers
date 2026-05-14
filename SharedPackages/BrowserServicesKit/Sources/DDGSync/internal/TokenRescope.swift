//
//  TokenRescope.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

public protocol TokenRescoping {
    func rescope(scope: String, token: String) async throws -> String?
}

public final class TokenRescope: TokenRescoping {

    public struct Request: Encodable {
        let scope: String
    }

    public struct Response: Decodable {
        let token: String
    }

    let api: RemoteAPIRequestCreating
    let endpoints: Endpoints

    init(api: RemoteAPIRequestCreating,
         endpoints: Endpoints) {
        self.api = api
        self.endpoints = endpoints
    }

    public func rescope(scope: String, token: String) async throws -> String? {

        guard let requestJson = try? JSONEncoder.snakeCaseKeys.encode(Request(scope: scope)) else {
            fatalError()
        }

        let request = api.createAuthenticatedJSONRequest(url: endpoints.tokenRescope,
                                                         method: .post,
                                                         authToken: token,
                                                         json: requestJson)

        do {
            let result = try await request.execute()
            guard let data = result.data else {
                throw SyncError.invalidDataInResponse("No body in successful POST on /token/rescope")
            }

            let scopedToken = try JSONDecoder.snakeCaseKeys.decode(Response.self, from: data)

            return scopedToken.token
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 404 {
                return nil
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }
}
