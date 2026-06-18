//
//  RegisteredDeviceMapperTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import XCTest

@testable import DDGSync

final class RegisteredDeviceMapperTests: XCTestCase {

    func testWhenMappingDefaultCredentialEntryThenDecryptsWithPrimaryKeyAndSetsDefaultCredentialID() {
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(), isScopedAccessCredentialsEnabled: { true })
        let entry = RegisteredDeviceEntry(id: "native-device",
                                          name: "encrypted_Mac",
                                          type: "encrypted_desktop",
                                          credentialId: SyncCredentialID.defaultCredential)

        let device = mapper.registeredDevice(fromLegacyEntry: entry, account: makeAccount())

        XCTAssertEqual(device?.id, "native-device")
        XCTAssertEqual(device?.name, "Mac")
        XCTAssertEqual(device?.type, "desktop")
        XCTAssertEqual(device?.credentialId, SyncCredentialID.defaultCredential)
    }

    func testWhenMappingThirdPartyEntryWithCachedScopedPasswordThenDecryptsJWEFields() async throws {
        let account = makeAccount()
        let scopedPassword = Data(repeating: 7, count: 32)
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let codec = JWECompactCodec()
        let entry = RegisteredDeviceEntry(
            id: "third-party-device",
            name: try codec.encryptDirect(payload: Data("Python Client".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            type: try codec.encryptDirect(payload: Data("browser".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            credentialId: SyncCredentialID.thirdParty)
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            cachedScopedPassword: { scopedPassword },
                                            isScopedAccessCredentialsEnabled: { true },
                                            jweCompactCodec: codec)

        let devices = await mapper.registeredDevices(from: [entry], account: account)

        XCTAssertEqual(devices.map { $0.id }, ["third-party-device"])
        XCTAssertEqual(devices.map { $0.name }, ["Python Client"])
        XCTAssertEqual(devices.map { $0.type }, ["browser"])
        XCTAssertEqual(devices.map { $0.credentialId }, [SyncCredentialID.thirdParty])
    }

    func testWhenMappingThirdPartyEntryWithoutCachedPasswordThenRecoversScopedPasswordAndDecryptsJWEFields() async throws {
        let account = makeAccount()
        let scopedPassword = Data(repeating: 7, count: 32)
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let codec = JWECompactCodec()
        let entry = RegisteredDeviceEntry(
            id: "third-party-device",
            name: try codec.encryptDirect(payload: Data("Python Client".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            type: try codec.encryptDirect(payload: Data("browser".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            credentialId: SyncCredentialID.thirdParty)
        let accessCredentials = [AccessCredential(id: SyncCredentialID.thirdParty, scope: "sync", encrypted3PartyCredential: "encrypted")]
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchAccessCredentialsStub = accessCredentials
        scopedAccess.recoverScopedPasswordStub = scopedPassword
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            scopedAccess: scopedAccess,
                                            cachedScopedPassword: { nil },
                                            isScopedAccessCredentialsEnabled: { true },
                                            jweCompactCodec: codec)

        let devices = await mapper.registeredDevices(from: [entry], account: account)

        XCTAssertEqual(scopedAccess.fetchAccessCredentialsCalls.map { $0.deviceId }, [account.deviceId])
        XCTAssertEqual(scopedAccess.recoverScopedPasswordCalls.count, 1)
        XCTAssertEqual(scopedAccess.recoverScopedPasswordCalls.first?.accessCredentials?.map { $0.id }, [SyncCredentialID.thirdParty])
        XCTAssertEqual(devices.map { $0.id }, ["third-party-device"])
        XCTAssertEqual(devices.map { $0.name }, ["Python Client"])
        XCTAssertEqual(devices.map { $0.type }, ["browser"])
        XCTAssertEqual(devices.map { $0.credentialId }, [SyncCredentialID.thirdParty])
    }

    func testWhenCachedScopedPasswordCannotDecryptEveryThirdPartyEntryThenFallsBackWithoutPartiallyTrustingCache() async throws {
        let account = makeAccount()
        let scopedPassword = Data(repeating: 7, count: 32)
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let codec = JWECompactCodec()
        let decryptableEntry = RegisteredDeviceEntry(
            id: "decryptable-third-party-device",
            name: try codec.encryptDirect(payload: Data("Python Client".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            type: try codec.encryptDirect(payload: Data("browser".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            credentialId: SyncCredentialID.thirdParty)
        let undecryptableEntry = RegisteredDeviceEntry(id: "undecryptable-third-party-device",
                                                       name: "not-jwe",
                                                       type: "not-jwe",
                                                       credentialId: SyncCredentialID.thirdParty)
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            cachedScopedPassword: { scopedPassword },
                                            isScopedAccessCredentialsEnabled: { true },
                                            jweCompactCodec: codec)

        let devices = await mapper.registeredDevices(from: [decryptableEntry, undecryptableEntry], account: account)

        XCTAssertEqual(devices.map { $0.id }, ["decryptable-third-party-device", "undecryptable-third-party-device"])
        XCTAssertEqual(devices.map { $0.name }, ["Browser", "Browser"])
        XCTAssertEqual(devices.map { $0.type }, ["unknown", "unknown"])
        XCTAssertEqual(devices.map { $0.credentialId }, [SyncCredentialID.thirdParty, SyncCredentialID.thirdParty])
    }

    func testWhenMappingUnknownCredentialEntryThenFallsBackWithoutAttemptingDecryption() async {
        var crypter = CryptingMock()
        crypter._base64DecodeAndDecrypt = { _ in
            XCTFail("Unknown credential entries should not be decrypted")
            return ""
        }
        let mapper = RegisteredDeviceMapper(crypter: crypter, isScopedAccessCredentialsEnabled: { true })
        let entry = RegisteredDeviceEntry(id: "future-device",
                                          name: "encrypted_Future",
                                          type: "encrypted_browser",
                                          credentialId: "future")

        let devices = await mapper.registeredDevices(from: [entry], account: makeAccount())

        XCTAssertEqual(devices.map { $0.id }, ["future-device"])
        XCTAssertEqual(devices.map { $0.name }, ["Unknown"])
        XCTAssertEqual(devices.map { $0.type }, ["unknown"])
        XCTAssertEqual(devices.map { $0.credentialId }, ["future"])
    }

    private func makeAccount() -> SyncAccount {
        SyncAccount(deviceId: "device-1",
                    deviceName: "Mac",
                    deviceType: "desktop",
                    userId: "user-1",
                    primaryKey: Data((0..<32).map(UInt8.init)),
                    secretKey: Data(repeating: 2, count: 32),
                    token: "token-1",
                    state: .active)
    }
}
