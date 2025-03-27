//
//  AccountManager.swift
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
import DDGSyncCrypto
import Networking

struct AccountManager: AccountManaging {

    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating
    let crypter: CryptingInternal

    func createAccount(deviceName: String, deviceType: String) async throws -> SyncAccount {
        let deviceId = UUID().uuidString
        let userId = UUID().uuidString
        let password = UUID().uuidString

        let accountKeys = try crypter.createAccountCreationKeys(userId: userId, password: password)
        let encryptedDeviceName = try crypter.encryptAndBase64Encode(deviceName, using: accountKeys.primaryKey)
        let encryptedDeviceType = try crypter.encryptAndBase64Encode(deviceType, using: accountKeys.primaryKey)

        let hashedPassword = Data(accountKeys.passwordHash).base64EncodedString()
        let protectedEncyrptionKey = Data(accountKeys.protectedSecretKey).base64EncodedString()

        let params = Signup.Parameters(
            userId: userId,
            hashedPassword: hashedPassword,
            protectedEncryptionKey: protectedEncyrptionKey,
            deviceId: deviceId,
            deviceName: encryptedDeviceName,
            deviceType: encryptedDeviceType
        )

        guard let paramJson = try? JSONEncoder.snakeCaseKeys.encode(params) else {
            fatalError()
        }

        let request = api.createUnauthenticatedJSONRequest(url: endpoints.signup, method: .post, json: paramJson)

        let result = try await request.execute()

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        guard let result = try? JSONDecoder.snakeCaseKeys.decode(Signup.Result.self, from: body) else {
            throw SyncError.unableToDecodeResponse("Failed to decode signup result")
        }

        return SyncAccount(deviceId: deviceId,
                           deviceName: deviceName,
                           deviceType: deviceType,
                           userId: userId,
                           primaryKey: Data(accountKeys.primaryKey),
                           secretKey: Data(accountKeys.secretKey),
                           token: result.token,
                           state: .active)
    }

    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> LoginResult {
        let deviceId = UUID().uuidString
        let recoveryInfo = try crypter.extractLoginInfo(recoveryKey: recoveryKey)
        return try await login(recoveryInfo,
                               deviceId: deviceId,
                               deviceName: deviceName,
                               deviceType: deviceType)
    }

    func logout(deviceId: String, token: String) async throws {
        let params = LogoutDevice.Parameters(deviceId: deviceId)

        guard let paramJson = try? JSONEncoder.snakeCaseKeys.encode(params) else {
            fatalError()
        }

        let request = api.createAuthenticatedJSONRequest(url: endpoints.logoutDevice, method: .post, authToken: token, json: paramJson)

        let result = try await request.execute()

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        guard let result = try? JSONDecoder.snakeCaseKeys.decode(LogoutDevice.Result.self, from: body) else {
            throw SyncError.unableToDecodeResponse("Failed to decode login result")
        }

        guard result.deviceId == deviceId else {
            throw SyncError.unexpectedResponseBody
        }
    }

    func fetchDevicesForAccount(_ account: SyncAccount) async throws -> [RegisteredDevice] {
        guard let token = account.token else {
            throw SyncError.noToken
        }

        let url = endpoints.syncGet.appendingPathComponent("devices")
        let request = api.createAuthenticatedGetRequest(url: url, authToken: token)
        let result = try await request.execute()

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        guard let result = try? JSONDecoder.snakeCaseKeys.decode(FetchDevicesResult.self, from: body) else {
            throw SyncError.unableToDecodeResponse("Failed to decode devices")
        }

        var devices = [RegisteredDevice]()
        if let entries = result.devices?.entries {
            for device in entries {
                do {
                    let name = try crypter.base64DecodeAndDecrypt(device.name, using: account.primaryKey)
                    let type = try crypter.base64DecodeAndDecrypt(device.type, using: account.primaryKey)
                    devices.append(RegisteredDevice(id: device.id, name: name, type: type))
                } catch {
                    // Invalid devices should be automatically logged out
                    try await logout(deviceId: device.id, token: token)
                }
            }
        }
        return devices
    }

    func refreshToken(_ account: SyncAccount, deviceName: String) async throws -> LoginResult {
        let info = try crypter.extractLoginInfo(recoveryKey: SyncCode.RecoveryKey(userId: account.userId,
                                                                                  primaryKey: account.primaryKey))
        return try await login(info,
                               deviceId: account.deviceId,
                               deviceName: deviceName,
                               deviceType: account.deviceType)
    }

    func deleteAccount(_ account: SyncAccount) async throws {
        guard let token = account.token else {
            throw SyncError.noToken
        }

        let request = api.createAuthenticatedJSONRequest(url: endpoints.deleteAccount, method: .post, authToken: token)
        let result = try await request.execute()
        let statusCode = result.response.statusCode

        guard statusCode == 204 else {
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    private func login(_ info: ExtractedLoginInfo,
                       deviceId: String,
                       deviceName: String,
                       deviceType: String) async throws -> LoginResult {

        let encryptedDeviceName = try crypter.encryptAndBase64Encode(deviceName, using: info.primaryKey)
        let encryptedDeviceType = try crypter.encryptAndBase64Encode(deviceType, using: info.primaryKey)

        let params = Login.Parameters(
            userId: info.userId,
            hashedPassword: info.passwordHash.base64EncodedString(),
            deviceId: deviceId,
            deviceName: encryptedDeviceName,
            deviceType: encryptedDeviceType
        )

        let paramJson = try JSONEncoder.snakeCaseKeys.encode(params)

        let request = api.createUnauthenticatedJSONRequest(url: endpoints.login, method: .post, json: paramJson)

        let result = try await request.execute()

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        guard let result = try? JSONDecoder.snakeCaseKeys.decode(Login.Result.self, from: body) else {
            throw SyncError.unableToDecodeResponse("Failed to decode login result")
        }

        guard let protectedSecretKey = Data(base64Encoded: result.protectedEncryptionKey) else {
            throw SyncError.invalidDataInResponse("protected_key missing from response")
        }

        let token = result.token

        let secretKey = try crypter.extractSecretKey(protectedSecretKey: protectedSecretKey,
                                                     stretchedPrimaryKey: info.stretchedPrimaryKey)

        return LoginResult(
            account: SyncAccount(
                deviceId: deviceId,
                deviceName: deviceName,
                deviceType: deviceType,
                userId: info.userId,
                primaryKey: info.primaryKey,
                secretKey: secretKey,
                token: token,
                state: .addingNewDevice
            ),
            devices: try result.devices.map {
                RegisteredDevice(
                    id: $0.id,
                    name: try crypter.base64DecodeAndDecrypt($0.name, using: info.primaryKey),
                    type: try crypter.base64DecodeAndDecrypt($0.type, using: info.primaryKey)
                )
            }
        )

    }

    struct Signup {

        struct Result: Decodable {
            let userId: String
            let token: String
        }

        struct Parameters: Encodable {
            let userId: String
            let hashedPassword: String
            let protectedEncryptionKey: String
            let deviceId: String
            let deviceName: String
            let deviceType: String
        }
    }

    struct Login {

        struct Result: Decodable {
            let devices: [RegisteredDevice]
            let token: String
            let protectedEncryptionKey: String
        }

        struct Parameters: Encodable {
            let userId: String
            let hashedPassword: String
            let deviceId: String
            let deviceName: String
            let deviceType: String
        }

    }

    struct LogoutDevice {

        struct Result: Decodable {
            let deviceId: String
        }

        struct Parameters: Encodable {
            let deviceId: String
        }
    }

    struct FetchDevicesResult: Decodable {
        struct DeviceWrapper: Decodable {
            var lastModified: String?
            var entries: [RegisteredDevice]
        }

        var devices: DeviceWrapper?
    }
}

extension SyncAccount {

    func updatingState(_ state: SyncAuthState) -> SyncAccount {
        SyncAccount(deviceId: self.deviceId,
                    deviceName: self.deviceName,
                    deviceType: self.deviceType,
                    userId: self.userId,
                    primaryKey: self.primaryKey,
                    secretKey: self.secretKey,
                    token: self.token,
                    state: state)
    }
}
