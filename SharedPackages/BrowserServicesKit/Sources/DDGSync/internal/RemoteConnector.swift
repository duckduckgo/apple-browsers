//
//  RemoteConnector.swift
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

final class RemoteConnector: RemoteConnecting {

    let code: String
    let connectInfo: ConnectInfo

    let crypter: CryptingInternal
    let api: RemoteAPIRequestCreating
    let endpoints: Endpoints

    var isPolling = false

    init(crypter: CryptingInternal,
         api: RemoteAPIRequestCreating,
         endpoints: Endpoints) throws {
        self.crypter = crypter
        self.api = api
        self.endpoints = endpoints
        self.connectInfo = try crypter.prepareForConnect()
        self.code = try connectInfo.toCode()
    }

    func pollForRecoveryKey() async throws -> SyncCode.RecoveryKey? {
        assert(!isPolling, "connector is already polling")

        isPolling = true
        while isPolling {
            if let key = try await fetchRecoveryKey() {
                return key
            }

            if isPolling {
                try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }
        }
        return nil
    }

    func stopPolling() {
        isPolling = false
    }

    private func fetchRecoveryKey() async throws -> SyncCode.RecoveryKey? {
        if let encryptedRecoveryKey = try await fetchEncryptedRecoveryKey() {
            let recoveryKey = try decryptEncryptedRecoveryKey(encryptedRecoveryKey)
            return recoveryKey
        }
        return nil
    }

    private func decryptEncryptedRecoveryKey(_ encryptedRecoveryKey: Data) throws -> SyncCode.RecoveryKey {
        let data = try crypter.unseal(encryptedData: encryptedRecoveryKey,
                                      publicKey: connectInfo.publicKey,
                                      secretKey: connectInfo.secretKey)

        guard let recoveryKey = try JSONDecoder.snakeCaseKeys.decode(SyncCode.self, from: data).recovery else {
            throw SyncError.failedToDecryptValue("Invalid recovery key in connect response")
        }

        return recoveryKey
    }

    private func fetchEncryptedRecoveryKey() async throws -> Data? {
        let url = endpoints.connect.appendingPathComponent(connectInfo.deviceID)

        let request = api.createRequest(url: url,
                                        method: .get,
                                        headers: [:],
                                        parameters: [:],
                                        body: nil,
                                        contentType: nil)

        do {
            let result = try await request.execute()
            guard let data = result.data else {
                throw SyncError.invalidDataInResponse("No body in successful GET on /connect")
            }

            let encryptedRecoveryKeyString = try JSONDecoder
                .snakeCaseKeys
                .decode(ConnectResult.self, from: data)
                .encryptedRecoveryKey

            guard let encrypted = encryptedRecoveryKeyString.data(using: .utf8) else {
                throw SyncError.invalidDataInResponse("unable to convert result string to data")
            }

            return Data(base64Encoded: encrypted)
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 404 {
                return nil
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    struct ConnectResult: Decodable {
        let encryptedRecoveryKey: String
    }

}

extension ConnectInfo {

    func toCode() throws -> String {
        return try SyncCode(connect: .init(deviceId: deviceID, secretKey: publicKey))
            .toJSON()
            .base64EncodedString()
    }

}
