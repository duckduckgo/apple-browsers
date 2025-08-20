//
//  RemoteKeyExchanger.swift
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

final class RemoteKeyExchanger: RemoteKeyExchanging {

    let code: String
    let exchangeInfo: ExchangeInfo

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
        self.exchangeInfo = try crypter.prepareForExchange()
        self.code = try exchangeInfo.toCode()
    }

    func pollForPublicKey() async throws -> ExchangeMessage? {
        assert(!isPolling, "exchanger is already polling")

        isPolling = true
        while isPolling {
            if let key = try await fetchPublicKey() {
                return key
            }

            if isPolling {
                try await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            }
        }
        return nil
    }

    func stopPolling() {
        isPolling = false
    }

    // MARK: Public Key

    private func fetchPublicKey() async throws -> ExchangeMessage? {
        if let base64EncodedEncryptedRecoveryKeyString = try await fetchEncryptedExchangeMessage() {
            let exchangeKey = try decryptEncryptedExchangeKey(base64EncodedEncryptedRecoveryKeyString)
            return exchangeKey
        }
        return nil
    }

    private func decryptEncryptedExchangeKey(_ base64EncodedEncryptedExchangeString: String) throws -> ExchangeMessage {
        guard let base64DecodedEncryptedExchangeMessage = Data(base64Encoded: base64EncodedEncryptedExchangeString) else {
            throw SyncError.failedToDecryptValue("Failed to convert base64 string to Data")
        }
        let data = try crypter.unseal(encryptedData: base64DecodedEncryptedExchangeMessage,
                                      publicKey: exchangeInfo.publicKey,
                                      secretKey: exchangeInfo.secretKey)

        let exchangeMessage = try JSONDecoder.snakeCaseKeys.decode(ExchangeMessage.self, from: data)

        return exchangeMessage
    }

    private func fetchEncryptedExchangeMessage() async throws -> String? {
        let url = endpoints.exchange.appendingPathComponent(exchangeInfo.keyId)

        let request = api.createRequest(url: url,
                                        method: .get,
                                        headers: [:],
                                        parameters: [:],
                                        body: nil,
                                        contentType: nil)

        do {
            let result = try await request.execute()
            guard let data = result.data else {
                throw SyncError.invalidDataInResponse("No body in successful GET on /exchange")
            }

            let base64EncodedEncryptedExchangeMessageString = try JSONDecoder
                .snakeCaseKeys
                .decode(ExchangeResult.self, from: data)
                .encryptedMessage

            return base64EncodedEncryptedExchangeMessageString
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 404 {
                return nil
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    struct ExchangeResult: Decodable {
        let encryptedMessage: String
    }
}

final class RemoteExchangeRecoverer: RemoteExchangeRecovering {
    private enum Constants {
        static var pollingTimeout: TimeInterval = 10
    }

    let exchangeInfo: ExchangeInfo

    let crypter: CryptingInternal
    let api: RemoteAPIRequestCreating
    let endpoints: Endpoints

    var isPolling = false

    init(crypter: CryptingInternal,
         api: RemoteAPIRequestCreating,
         endpoints: Endpoints,
         exchangeInfo: ExchangeInfo) throws {
        self.crypter = crypter
        self.api = api
        self.endpoints = endpoints
        self.exchangeInfo = exchangeInfo
    }

    // MARK: Recover Key

    func pollForRecoveryKey() async throws -> SyncCode.RecoveryKey? {
        try await pollForRecoveryKey(timeout: Constants.pollingTimeout)
    }

    func pollForRecoveryKey(timeout: TimeInterval) async throws -> SyncCode.RecoveryKey? {
        assert(!isPolling, "exchanger is already polling")

        isPolling = true
        let timeoutDate = Date().addingTimeInterval(timeout)

        while isPolling {
            if Date() > timeoutDate {
                throw SyncError.pollingDidTimeOut
            }

            if let key = try await fetchRecoveryKey() {
                return key
            }

            if isPolling {
                try await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            }
        }
        return nil
    }

    func stopPolling() {
        isPolling = false
    }

    private func fetchRecoveryKey() async throws -> SyncCode.RecoveryKey? {
        if let base64EncodedEncryptedRecoveryKeyString = try await fetchEncryptedRecoveryKey() {
            let recoveryKey = try decryptEncryptedRecoveryKey(base64EncodedEncryptedRecoveryKeyString)
            return recoveryKey
        }
        return nil
    }

    private func decryptEncryptedRecoveryKey(_ base64EncodedEncryptedRecoveryKeyString: String) throws -> SyncCode.RecoveryKey {
        guard let encryptedRecoveryKey = Data(base64Encoded: base64EncodedEncryptedRecoveryKeyString) else {
            throw SyncError.failedToDecryptValue("Invalid recovery key in exchange response")
        }
        let decryptedRecoveryKeyData = try crypter.unseal(encryptedData: encryptedRecoveryKey,
                                                          publicKey: exchangeInfo.publicKey,
                                                          secretKey: exchangeInfo.secretKey)

        guard let recoveryKey = try JSONDecoder.snakeCaseKeys.decode(SyncCode.self, from: decryptedRecoveryKeyData).recovery else {
            throw SyncError.failedToDecryptValue("Invalid recovery key in connect response")
        }

        return recoveryKey
    }

    private func fetchEncryptedRecoveryKey() async throws -> String? {
        let url = endpoints.exchange.appendingPathComponent(exchangeInfo.keyId)

        let request = api.createRequest(url: url,
                                        method: .get,
                                        headers: [:],
                                        parameters: [:],
                                        body: nil,
                                        contentType: nil)

        do {
            let result = try await request.execute()
            guard let data = result.data else {
                throw SyncError.invalidDataInResponse("No body in successful GET on /exchange")
            }

            let base64EncodedEncryptedRecoveryKeyString = try JSONDecoder
                .snakeCaseKeys
                .decode(ExchangeResult.self, from: data)
                .encryptedMessage

            return base64EncodedEncryptedRecoveryKeyString
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 404 {
                return nil
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    struct ExchangeResult: Decodable {
        let encryptedMessage: String
    }

}

extension ExchangeInfo {

    func toCode() throws -> String {
        return try SyncCode(exchangeKey: .init(keyId: keyId, publicKey: publicKey))
            .toJSON()
            .base64EncodedString()
    }

}
