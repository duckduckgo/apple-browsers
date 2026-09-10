//
//  DeviceInfoMigrationCoordinatorTests.swift
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

@_spi(Testing) import Persistence
import XCTest

@testable import DDGSync

final class DeviceInfoMigrationCoordinatorTests: XCTestCase {

    private var accountManager: AccountManagingMock!
    private var scopedAccess: ScopedAccessCredentialManagingMock!
    private var deviceInfoCodec: DeviceInfoMigrationCodingMock!
    private var secureStore: SecureStorageStub!
    private var keyValueStore: MockKeyValueFileStore!
    private var coordinator: DeviceInfoMigrationCoordinator!
    private var canWriteUnifiedDeviceList: Bool!
    private var accountInfoProtectedKey: ProtectedKey!

    override func setUpWithError() throws {
        try super.setUpWithError()

        accountManager = AccountManagingMock()
        scopedAccess = ScopedAccessCredentialManagingMock()
        deviceInfoCodec = DeviceInfoMigrationCodingMock()
        secureStore = SecureStorageStub()
        secureStore.theAccount = .mock
        keyValueStore = try MockKeyValueFileStore()
        canWriteUnifiedDeviceList = true
        accountInfoProtectedKey = ProtectedKey(
            kid: "account-info-key",
            encryptedPrivateKey: "encrypted-private-key",
            publicKey: .mock,
            encryptedWith: SyncCredentialID.defaultCredential,
            purpose: ProtectedKeyPurpose.accountInfo)
        scopedAccess.ensureAccountInfoProtectedKeysStub = [accountInfoProtectedKey]
        coordinator = makeCoordinator()
    }

    override func tearDown() {
        accountManager = nil
        scopedAccess = nil
        deviceInfoCodec = nil
        secureStore = nil
        keyValueStore = nil
        coordinator = nil
        canWriteUnifiedDeviceList = nil
        accountInfoProtectedKey = nil

        super.tearDown()
    }

    func testWhenWriteFlagIsDisabledThenMigrationIsSkipped() async {
        canWriteUnifiedDeviceList = false

        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)

        XCTAssertTrue(scopedAccess.ensureAccountInfoProtectedKeysCalls.isEmpty)
        XCTAssertTrue(accountManager.updateDeviceCalls.isEmpty)
        XCTAssertFalse(coordinator.hasCompletedMigration(for: .mock))
    }

    func testWhenMigrationSucceedsThenCurrentDeviceIsPatchedInBothFormatsAndMarkedComplete() async throws {
        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)

        XCTAssertEqual(scopedAccess.ensureAccountInfoProtectedKeysCalls.map(\.deviceId), [SyncAccount.mock.deviceId])
        XCTAssertEqual(deviceInfoCodec.encryptCalls.map(\.deviceInfo), [
            DeviceInfo(name: SyncAccount.mock.deviceName, type: SyncAccount.mock.deviceType)
        ])
        let call = try XCTUnwrap(accountManager.updateDeviceCalls.first)
        XCTAssertEqual(call.account.deviceId, SyncAccount.mock.deviceId)
        XCTAssertEqual(call.update.id, SyncAccount.mock.deviceId)
        XCTAssertEqual(call.update.name, "encrypted_\(SyncAccount.mock.deviceName)")
        XCTAssertEqual(call.update.type, "encrypted_\(SyncAccount.mock.deviceType)")
        XCTAssertEqual(call.update.info, deviceInfoCodec.encryptStub)
        XCTAssertTrue(coordinator.hasCompletedMigration(for: .mock))
    }

    func testWhenMigrationRunsTwiceThenCurrentDeviceIsPatchedOnce() async {
        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)
        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)

        XCTAssertEqual(accountManager.updateDeviceCalls.count, 1)
        XCTAssertEqual(scopedAccess.ensureAccountInfoProtectedKeysCalls.count, 1)
    }

    func testWhenCompletedMigrationIsResetAfterRenameThenCurrentDeviceIsPatchedAgainWithLatestName() async throws {
        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)
        let renamedAccount = SyncAccount(
            deviceId: SyncAccount.mock.deviceId,
            deviceName: "Renamed Device",
            deviceType: SyncAccount.mock.deviceType,
            userId: SyncAccount.mock.userId,
            primaryKey: SyncAccount.mock.primaryKey,
            secretKey: SyncAccount.mock.secretKey,
            token: SyncAccount.mock.token,
            state: .active)
        secureStore.theAccount = renamedAccount
        coordinator.reset()

        await coordinator.migrateCurrentDeviceIfNeeded(for: renamedAccount)

        XCTAssertEqual(accountManager.updateDeviceCalls.count, 2)
        let latestUpdate = try XCTUnwrap(accountManager.updateDeviceCalls.last?.update)
        XCTAssertEqual(latestUpdate.name, "encrypted_\(renamedAccount.deviceName)")
        XCTAssertEqual(deviceInfoCodec.encryptCalls.last?.deviceInfo.name, renamedAccount.deviceName)
        XCTAssertTrue(coordinator.hasCompletedMigration(for: renamedAccount))
    }

    func testWhenAccountIsRemovedDuringKeyPreparationThenMigrationStops() async throws {
        let keyPreparationStarted = expectation(description: "Key preparation started")
        let gate = AsyncGate()
        let accountInfoProtectedKey = try XCTUnwrap(accountInfoProtectedKey)
        scopedAccess.ensureAccountInfoProtectedKeysHandler = { [accountInfoProtectedKey] _ in
            keyPreparationStarted.fulfill()
            await gate.wait()
            return [accountInfoProtectedKey]
        }
        let migration = Task {
            await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)
        }
        await fulfillment(of: [keyPreparationStarted], timeout: 1)

        secureStore.theAccount = nil
        await gate.open()
        await migration.value

        XCTAssertTrue(accountManager.updateDeviceCalls.isEmpty)
        XCTAssertFalse(coordinator.hasCompletedMigration(for: .mock))
    }

    func testWhenAccountIsRemovedWhilePatchIsInFlightThenMigrationIsNotMarkedComplete() async throws {
        let patchStarted = expectation(description: "Patch started")
        let gate = AsyncGate()
        accountManager.updateDeviceHandler = { _, _ in
            patchStarted.fulfill()
            await gate.wait()
            return []
        }
        let migration = Task {
            await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)
        }
        await fulfillment(of: [patchStarted], timeout: 1)

        try secureStore.removeAccount()
        coordinator.reset()
        await gate.open()
        await migration.value

        XCTAssertFalse(coordinator.hasCompletedMigration(for: .mock))
    }

    func testWhenDeviceNameChangesDuringKeyPreparationThenLatestNameIsMigrated() async throws {
        let keyPreparationStarted = expectation(description: "Key preparation started")
        let gate = AsyncGate()
        let accountInfoProtectedKey = try XCTUnwrap(accountInfoProtectedKey)
        scopedAccess.ensureAccountInfoProtectedKeysHandler = { [accountInfoProtectedKey] _ in
            keyPreparationStarted.fulfill()
            await gate.wait()
            return [accountInfoProtectedKey]
        }
        let migration = Task {
            await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)
        }
        await fulfillment(of: [keyPreparationStarted], timeout: 1)
        let renamedAccount = SyncAccount(
            deviceId: SyncAccount.mock.deviceId,
            deviceName: "Renamed Device",
            deviceType: SyncAccount.mock.deviceType,
            userId: SyncAccount.mock.userId,
            primaryKey: SyncAccount.mock.primaryKey,
            secretKey: SyncAccount.mock.secretKey,
            token: SyncAccount.mock.token,
            state: .active)
        secureStore.theAccount = renamedAccount

        await gate.open()
        await migration.value

        let update = try XCTUnwrap(accountManager.updateDeviceCalls.first?.update)
        XCTAssertEqual(update.name, "encrypted_Renamed Device")
        XCTAssertEqual(deviceInfoCodec.encryptCalls.first?.deviceInfo.name, renamedAccount.deviceName)
        XCTAssertTrue(coordinator.hasCompletedMigration(for: renamedAccount))
    }

    func testWhenEnsuringAccountInfoKeysFailsThenLaterAttemptRetries() async {
        scopedAccess.ensureAccountInfoProtectedKeysError = TestError.expected

        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)

        XCTAssertTrue(accountManager.updateDeviceCalls.isEmpty)
        XCTAssertFalse(coordinator.hasCompletedMigration(for: .mock))

        scopedAccess.ensureAccountInfoProtectedKeysError = nil
        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)

        XCTAssertEqual(scopedAccess.ensureAccountInfoProtectedKeysCalls.count, 2)
        XCTAssertEqual(accountManager.updateDeviceCalls.count, 1)
        XCTAssertTrue(coordinator.hasCompletedMigration(for: .mock))
    }

    func testWhenPatchFailsThenLaterAttemptRetries() async {
        accountManager.updateDeviceError = SyncError.unexpectedStatusCode(500)

        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)

        XCTAssertEqual(accountManager.updateDeviceCalls.count, 1)
        XCTAssertFalse(coordinator.hasCompletedMigration(for: .mock))

        accountManager.updateDeviceError = nil
        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)

        XCTAssertEqual(accountManager.updateDeviceCalls.count, 2)
        XCTAssertTrue(coordinator.hasCompletedMigration(for: .mock))
    }

    func testWhenPatchIsUnauthorizedThenAccountIsPreservedAndMigrationIsNotMarkedComplete() async {
        accountManager.updateDeviceError = SyncError.unexpectedStatusCode(401)

        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)

        XCTAssertNotNil(secureStore.theAccount)
        XCTAssertFalse(coordinator.hasCompletedMigration(for: .mock))
    }

    func testWhenEncryptedDeviceInfoExceedsServerLimitThenMigrationIsNotPatchedOrMarkedComplete() async {
        deviceInfoCodec.encryptStub = String(repeating: "a", count: DeviceInfo.maximumEncryptedLength + 1)

        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)

        XCTAssertTrue(accountManager.updateDeviceCalls.isEmpty)
        XCTAssertFalse(coordinator.hasCompletedMigration(for: .mock))
    }

    func testWhenAccountChangesThenCompletedMigrationDoesNotSkipNewDevice() async {
        await coordinator.migrateCurrentDeviceIfNeeded(for: .mock)
        let replacementAccount = SyncAccount(
            deviceId: "replacement-device",
            deviceName: SyncAccount.mock.deviceName,
            deviceType: SyncAccount.mock.deviceType,
            userId: SyncAccount.mock.userId,
            primaryKey: SyncAccount.mock.primaryKey,
            secretKey: SyncAccount.mock.secretKey,
            token: SyncAccount.mock.token,
            state: .active)
        secureStore.theAccount = replacementAccount

        await coordinator.migrateCurrentDeviceIfNeeded(for: replacementAccount)

        XCTAssertEqual(accountManager.updateDeviceCalls.map(\.update.id), [SyncAccount.mock.deviceId, replacementAccount.deviceId])
        XCTAssertTrue(coordinator.hasCompletedMigration(for: replacementAccount))
    }

    private func makeCoordinator() -> DeviceInfoMigrationCoordinator {
        DeviceInfoMigrationCoordinator(
            accountManager: accountManager,
            scopedAccess: scopedAccess,
            crypter: CryptingMock(),
            deviceInfoCodec: deviceInfoCodec,
            secureStore: secureStore,
            keyValueStore: keyValueStore,
            canWriteUnifiedDeviceList: { [weak self] in self?.canWriteUnifiedDeviceList == true })
    }
}

private enum TestError: Error {
    case expected
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}

private final class DeviceInfoMigrationCodingMock: DeviceInfoCoding {

    struct EncryptCall {
        let deviceInfo: DeviceInfo
        let keyID: String
    }

    private(set) var encryptCalls: [EncryptCall] = []
    var encryptStub = "encrypted-device-info"
    var encryptError: Error?

    func encrypt(_ deviceInfo: DeviceInfo, using protectedKey: ProtectedKey) throws -> String {
        encryptCalls.append(EncryptCall(deviceInfo: deviceInfo, keyID: protectedKey.kid))
        if let encryptError {
            throw encryptError
        }
        return encryptStub
    }

    func encrypt(_ deviceInfo: DeviceInfo, using key: AccountInfoKey) throws -> String {
        throw DeviceInfoCodecError.invalidProtectedKey
    }

    func decrypt(_ encryptedDeviceInfo: String, using key: AccountInfoKey) throws -> DeviceInfo {
        throw DeviceInfoCodecError.invalidPayload
    }
}
