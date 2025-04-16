//
//  SyncRequestMaker.swift
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
import Gzip

protocol SyncRequestMaking {
    func makeGetRequest(with result: SyncRequest) throws -> HTTPRequesting
    func makePatchRequest(with result: SyncRequest, clientTimestamp: Date, isCompressed: Bool) throws -> HTTPRequesting
}

struct SyncRequestMaker: SyncRequestMaking {
    let storage: SecureStoring
    let api: RemoteAPIRequestCreating
    let endpoints: Endpoints
    let payloadCompressor: SyncPayloadCompressing
    let dateFormatter = ISO8601DateFormatter()

    func makeGetRequest(with result: SyncRequest) throws -> HTTPRequesting {
        let url = try endpoints.syncGet(features: [result.feature.name])

        let parameters: [String: String] = {
            if let timestamp = result.previousSyncTimestamp {
                return ["since": timestamp]
            }
            return [:]
        }()
        return api.createAuthenticatedGetRequest(url: url, authToken: try getToken(), parameters: parameters)
    }

    func makePatchRequest(with result: SyncRequest, clientTimestamp: Date, isCompressed: Bool) throws -> HTTPRequesting {
        var json = [String: Any]()
        let modelPayload: [String: Any?] = [
            "updates": result.sent.map(\.payload),
            "modified_since": result.previousSyncTimestamp ?? "0"
        ]
        json[result.feature.name] = modelPayload
        json["client_timestamp"] = dateFormatter.string(from: clientTimestamp)

        guard JSONSerialization.isValidJSONObject(json) else {
            throw SyncError.unableToEncodeRequestBody("Sync PATCH payload is not a valid JSON")
        }

        let body = try JSONSerialization.data(withJSONObject: json, options: [])

        guard isCompressed else {
            return api.createAuthenticatedJSONRequest(
                url: endpoints.syncPatch,
                method: .patch,
                authToken: try getToken(),
                json: body
            )
        }

        let compressedBody = try payloadCompressor.compress(body)
        return api.createAuthenticatedJSONRequest(
            url: endpoints.syncPatch,
            method: .patch,
            authToken: try getToken(),
            json: compressedBody,
            headers: ["Content-Encoding": "gzip"])
    }

    private func getToken() throws -> String {
        guard let account = try storage.account() else {
            throw SyncError.accountNotFound
        }

        guard let token = account.token else {
            throw SyncError.noToken
        }

        return token
    }
}
