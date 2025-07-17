//
//  CredentialsDatabaseCleanerTests.swift
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

import XCTest
import Common
import GRDB
import SecureStorage
import SecureStorageTestsUtils
@testable import BrowserServicesKit

final class MockEventMapper: EventMapping<CredentialsCleanupError> {
    static var errors: [Error] = []

    public init() {
        super.init { event, _, _, _ in
            Self.errors.append(event.cleanupError)
        }
    }

    override init(mapping: @escaping EventMapping<CredentialsCleanupError>.Mapping) {
        fatalError("Use init()")
    }
}

final class MockSecureVaultErrorReporter: SecureVaultReporting {
    var _secureVaultInitFailed: (SecureStorageError) -> Void = { _ in }
    func secureVaultError(_ error: SecureStorageError) {
        _secureVaultInitFailed(error)
    }
}

extension AutofillVaultFactory {
    static func testFactory(databaseProvider: DefaultAutofillDatabaseProvider) -> AutofillVaultFactory {
        AutofillVaultFactory(makeCryptoProvider: {
            NoOpCryptoProvider()
        }, makeKeyStoreProvider: { _ in
            let provider = MockKeystoreProvider()
            provider._l1Key = "l1".data(using: .utf8)
            provider._encryptedL2Key = "encrypted".data(using: .utf8)
            return provider
        }, makeDatabaseProvider: { _, _ in
            databaseProvider
        })
    }
}

final class CredentialsDatabaseCleanerTests: XCTestCase {
    let simpleL1Key = "simple-key".data(using: .utf8)!
    var databaseLocation: URL!
    var databaseProvider: DefaultAutofillDatabaseProvider!

    var secureVaultFactory: AutofillVaultFactory!
    var secureVault: (any AutofillSecureVault)!

    var location: URL!
    var databaseCleaner: CredentialsDatabaseCleaner!
    var eventMapper: MockEventMapper!

    override func setUpWithError() throws {
        try super.setUpWithError()

        databaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        databaseProvider = try DefaultAutofillDatabaseProvider(file: databaseLocation, key: simpleL1Key)
        secureVaultFactory = AutofillVaultFactory.testFactory(databaseProvider: databaseProvider)
        secureVault = try secureVaultFactory.makeVault(reporter: nil)
        _ = try secureVault.authWith(password: "abcd".data(using: .utf8)!)

        eventMapper = MockEventMapper()
        MockEventMapper.errors.removeAll()
    }

    override func tearDownWithError() throws {
        try deleteDbFile()
        try super.tearDownWithError()
    }

    func testWhenSyncIsActiveThenCleanupIsCancelled() throws {
        let expectation = expectation(description: "removeSyncMetadataPendingDeletion")
        expectation.isInverted = true
        let removeSyncMetadataPendingDeletion: (Database) throws -> Int = { _ in
            expectation.fulfill()
            return 0
        }

        databaseCleaner = CredentialsDatabaseCleaner(
            secureVaultFactory: secureVaultFactory,
            secureVaultErrorReporter: MockSecureVaultErrorReporter(),
            errorEvents: eventMapper,
            removeSyncMetadataPendingDeletion: removeSyncMetadataPendingDeletion
        )

        databaseCleaner.isSyncActive = { true }

        databaseCleaner.removeSyncableCredentialsMetadataPendingDeletion()
        waitForExpectations(timeout: 1)
        XCTAssertEqual(MockEventMapper.errors.count, 1)
        let error = try XCTUnwrap(MockEventMapper.errors.first)
        XCTAssertTrue(error is CredentialsCleanupCancelledError)
    }

    func testWhenThereAreNoConflictsThenCleanerContextIsSavedOnce() throws {
        databaseCleaner = CredentialsDatabaseCleaner(
            secureVaultFactory: secureVaultFactory,
            secureVaultErrorReporter: MockSecureVaultErrorReporter(),
            errorEvents: eventMapper
        )

        try secureVault.storeCredentials(domain: "1", username: "1")
        try secureVault.storeCredentials(domain: "2", username: "2")

        var syncableCredentialsMetadata = try databaseProvider.db.read { database in
            try SecureVaultModels.SyncableCredentialsRecord.fetchAll(database)
        }

        XCTAssertEqual(syncableCredentialsMetadata.count, 2)

        let accountId = try XCTUnwrap(syncableCredentialsMetadata.first?.objectId)
        try secureVault.deleteWebsiteCredentialsFor(accountId: accountId)

        syncableCredentialsMetadata = try databaseProvider.db.read { database in
            try SecureVaultModels.SyncableCredentialsRecord.fetchAll(database)
        }

        XCTAssertEqual(syncableCredentialsMetadata.count, 2)

        databaseCleaner.removeSyncableCredentialsMetadataPendingDeletion()

        syncableCredentialsMetadata = try databaseProvider.db.read { database in
            try SecureVaultModels.SyncableCredentialsRecord.fetchAll(database)
        }

        XCTAssertTrue(MockEventMapper.errors.isEmpty)
        XCTAssertEqual(syncableCredentialsMetadata.count, 1)
    }

    func deleteDbFile() throws {
        do {
            let dbFileContainer = databaseLocation.deletingLastPathComponent()
            for file in try FileManager.default.contentsOfDirectory(atPath: dbFileContainer.path) {
                guard ["db", "bak"].contains((file as NSString).pathExtension) else { continue }
                try FileManager.default.removeItem(atPath: dbFileContainer.appendingPathComponent(file).path)
            }

        } catch let error as NSError {
            // File not found
            if error.domain != NSCocoaErrorDomain || error.code != 4 {
                throw error
            }
        }
    }
}

extension AutofillSecureVault {
    func storeCredentials(domain: String? = nil, username: String? = nil, password: String? = nil, notes: String? = nil) throws {
        let passwordData = password.flatMap { $0.data(using: .utf8) }
        let account = SecureVaultModels.WebsiteAccount(username: username, domain: domain, notes: notes)
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
        try storeWebsiteCredentials(credentials)
    }
}
