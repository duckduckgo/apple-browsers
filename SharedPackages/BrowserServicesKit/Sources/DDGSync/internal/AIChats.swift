//
//  AIChats.swift
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

public protocol AIChatsHandling {
    func delete(until: Date, token: String) async throws
}

public final class AIChats: AIChatsHandling {

    private let api: RemoteAPIRequestCreating
    private let endpoints: Endpoints
    private let dateFormatter: ISO8601DateFormatter

    init(api: RemoteAPIRequestCreating, endpoints: Endpoints) {
        self.api = api
        self.endpoints = endpoints
        self.dateFormatter = ISO8601DateFormatter()
    }

    public func delete(until: Date, token: String) async throws {
        let untilString = dateFormatter.string(from: until)

        let request = api.createAuthenticatedJSONRequest(
            url: endpoints.aiChats,
            method: .delete,
            authToken: token,
            json: nil,
            headers: [:],
            parameters: ["until": untilString]
        )

        let result = try await request.execute()
        let statusCode = result.response.statusCode

        guard statusCode == 204 else {
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }
}
