//
//  ExchangeKeyTransmitter.swift
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

struct ExchangePublicKeyTransmitter: ExchangePublicKeyTransmitting {
    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating
    let crypter: CryptingInternal

    func sendGeneratedExchangeInfo(_ code: SyncCode.ExchangeKey, deviceName: String) async throws -> ExchangeInfo {
        let exchangeInfo = try crypter.prepareForExchange()
        let exchangeKey = try JSONEncoder.snakeCaseKeys.encode(
            ExchangeMessage(keyId: exchangeInfo.keyId, publicKey: exchangeInfo.publicKey, deviceName: deviceName)
        )

        let encryptedRecoveryKey = try crypter.seal(exchangeKey, secretKey: code.publicKey)
        let encodedRecoveryKey = encryptedRecoveryKey.base64EncodedString()

        let body = try JSONEncoder.snakeCaseKeys.encode(
            ExchangeRequest(keyId: code.keyId, encryptedMessage: encodedRecoveryKey)
        )

        let request = api.createRequest(url: endpoints.exchange,
                                        method: .post,
                                        headers: [:],
                                        parameters: [:],
                                        body: body,
                                        contentType: "application/json")
        _ = try await request.execute()
        return exchangeInfo
    }
}

struct ExchangeRecoveryKeyTransmitter: ExchangeRecoveryKeyTransmitting {
    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating
    let crypter: CryptingInternal
    let storage: SecureStoring
    let exchangeMessage: ExchangeMessage

    func send() async throws {
        guard let recoveryCode = try storage.account()?.recoveryCode else {
            throw SyncError.accountNotFound
        }

        guard let recoveryCodeData = Data(base64Encoded: recoveryCode) else {
            throw SyncError.unableToEncodeRequestBody("Base64 encoding failed")
        }

        let encryptedRecoveryKey = try crypter.seal(recoveryCodeData, secretKey: exchangeMessage.publicKey)
        let encodedRecoveryKey = encryptedRecoveryKey.base64EncodedString()

        let body = try JSONEncoder.snakeCaseKeys.encode(
            ExchangeRequest(keyId: exchangeMessage.keyId, encryptedMessage: encodedRecoveryKey)
        )

        let request = api.createRequest(url: endpoints.exchange,
                                        method: .post,
                                        headers: [:],
                                        parameters: [:],
                                        body: body,
                                        contentType: "application/json")
        _ = try await request.execute()
    }
}

private struct ExchangeRequest: Encodable {
    let keyId: String
    let encryptedMessage: String
}
