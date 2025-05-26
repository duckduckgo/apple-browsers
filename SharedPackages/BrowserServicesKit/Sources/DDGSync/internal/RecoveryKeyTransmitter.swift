//
//  RecoveryKeyTransmitter.swift
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

struct RecoveryKeyTransmitter: RecoveryKeyTransmitting {

    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating
    let storage: SecureStoring
    let crypter: CryptingInternal

    func send(_ code: SyncCode.ConnectCode) async throws {
        guard let account = try storage.account() else {
            throw SyncError.accountNotFound
        }

        guard let token = try storage.account()?.token else {
            throw SyncError.noToken
        }

        let recoveryKey = try JSONEncoder.snakeCaseKeys.encode(
            SyncCode(recovery: SyncCode.RecoveryKey(userId: account.userId, primaryKey: account.primaryKey))
        )

        let encryptedRecoveryKey = try crypter.seal(recoveryKey, secretKey: code.secretKey)

        let body = try JSONEncoder.snakeCaseKeys.encode(
            ConnectRequest(deviceId: code.deviceId, encryptedRecoveryKey: encryptedRecoveryKey)
        )

        let request = api.createRequest(url: endpoints.connect,
                                        method: .post,
                                        headers: ["Authorization": "Bearer \(token)"],
                                        parameters: [:],
                                        body: body,
                                        contentType: "application/json")
        _ = try await request.execute()
    }

    struct ConnectRequest: Encodable {
        let deviceId: String
        let encryptedRecoveryKey: Data
    }

}
