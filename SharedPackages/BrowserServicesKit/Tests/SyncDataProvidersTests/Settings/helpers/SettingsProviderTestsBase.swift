//
//  SettingsProviderTestsBase.swift
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

import BrowserServicesKit
import Common
import CoreData
import DDGSync
import Foundation
import Persistence
import XCTest
@testable import SyncDataProviders

class MockEmailManagerStorage: EmailManagerStorage {

    var mockError: EmailKeychainAccessError?

    var mockUsername: String?
    var mockToken: String?
    var mockAlias: String?
    var mockCohort: String?
    var mockLastUseDate: String?

    var storeTokenCallback: ((String, String, String?) -> Void)?
    var storeAliasCallback: ((String) -> Void)?
    var storeLastUseDateCallback: ((String) -> Void)?
    var deleteAliasCallback: (() -> Void)?
    var deleteAuthenticationStateCallback: (() -> Void)?
    var deleteWaitlistStateCallback: (() -> Void)?

    func getUsername() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockUsername
    }

    func getToken() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockToken
    }

    func getAlias() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockAlias
    }

    func getCohort() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockCohort
    }

    func getLastUseDate() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockLastUseDate
    }

    func store(token: String, username: String, cohort: String?) throws {
        if let storeTokenCallback {
            storeTokenCallback(token, username, cohort)
        } else {
            mockToken = token
            mockUsername = username
            mockCohort = cohort
        }
    }

    func store(alias: String) throws {
        storeAliasCallback?(alias)
    }

    func store(lastUseDate: String) throws {
        storeLastUseDateCallback?(lastUseDate)
    }

    func deleteAlias() {
        deleteAliasCallback?()
    }

    func deleteAuthenticationState() {
        if let deleteAuthenticationStateCallback {
            deleteAuthenticationStateCallback()
        } else {
            mockToken = nil
            mockUsername = nil
            mockCohort = nil
        }
    }

    func deleteWaitlistState() {
        deleteWaitlistStateCallback?()
    }

}

internal class SettingsProviderTestsBase: XCTestCase {
    var emailManagerStorage: MockEmailManagerStorage!
    var emailManager: EmailManager!
    var metadataDatabase: CoreDataDatabase!
    var metadataDatabaseLocation: URL!
    var crypter = CryptingMock()
    var provider: SettingsProvider!
    var testSettingSyncHandler: TestSettingSyncHandler!

    func setUpSyncMetadataDatabase() {
        metadataDatabaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = DDGSync.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "SyncMetadata") else {
            XCTFail("Failed to load model")
            return
        }
        metadataDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: metadataDatabaseLocation, model: model)
        metadataDatabase.loadStore()
    }

    override func setUpWithError() throws {
        super.setUp()

        emailManagerStorage = MockEmailManagerStorage()
        emailManager = EmailManager(storage: emailManagerStorage)
        let emailProtectionSyncHandler = EmailProtectionSyncHandler(emailManager: emailManager)
        testSettingSyncHandler = .init()

        setUpSyncMetadataDatabase()

        provider = SettingsProvider(
            metadataDatabase: metadataDatabase,
            metadataStore: LocalSyncMetadataStore(database: metadataDatabase),
            settingsHandlers: [emailProtectionSyncHandler, testSettingSyncHandler],
            syncDidUpdateData: {}
        )
    }

    override func tearDown() {
        try? metadataDatabase.tearDown(deleteStores: true)
        metadataDatabase = nil
        try? FileManager.default.removeItem(at: metadataDatabaseLocation)

        provider = nil
        emailManager = nil
        super.tearDown()
    }

    // MARK: - Helpers

    func fetchAllSettingsMetadata(in context: NSManagedObjectContext) -> [SyncableSettingsMetadata] {
        var metadata = [SyncableSettingsMetadata]()
        let request = SyncableSettingsMetadata.fetchRequest()
        context.performAndWait {
            do {
                metadata = try context.fetch(request)
            } catch {
                XCTFail("Failed to fetch from SyncMetadataStore")
            }
        }
        return metadata
    }

    func handleSyncResponse(sent: [Syncable] = [], received: [Syncable], clientTimestamp: Date = Date(), serverTimestamp: String = "1234") async throws {
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }

    func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date = Date(), serverTimestamp: String = "1234") async throws {
        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }
}
