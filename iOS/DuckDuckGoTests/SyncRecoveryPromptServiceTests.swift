//
//  SyncRecoveryPromptServiceTests.swift
//  DuckDuckGoTests
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Core
import BrowserServicesKit
import Persistence
import SecureStorage
@testable import DuckDuckGo
@testable import PersistenceTestingUtils
@testable import DDGSync

@MainActor
final class SyncRecoveryPromptServiceTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockSyncService: MockDDGSyncing!
    private var mockKeyValueStore: ThrowingKeyValueStoring!
    private var sut: SyncRecoveryPromptService!

    override func setUp() async throws {
        try await super.setUp()

        mockFeatureFlagger = MockFeatureFlagger()
        mockSyncService = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        mockKeyValueStore = try MockKeyValueFileStore(throwOnInit: nil)
    }

    override func tearDown() async throws {
        mockFeatureFlagger = nil
        mockSyncService = nil
        mockKeyValueStore = nil
        sut = nil

        try await super.tearDown()
    }

    // MARK: - shouldShowPrompt Tests

    func testShouldShowPrompt_WhenFeatureDisabled_ReturnsFalse() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true
        )

        // When
        let result = sut.shouldShowPrompt()

        // Then
        XCTAssertFalse(result)
    }

    func testShouldShowPrompt_DuringOnboarding_ReturnsFalse() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.newDeviceSyncPrompt]
        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: false
        )

        // When
        let result = sut.shouldShowPrompt()

        // Then
        XCTAssertFalse(result)
    }

    func testShouldShowPrompt_WhenAlreadyChecked_ReturnsFalse() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.newDeviceSyncPrompt]
        try mockKeyValueStore.set(true, forKey: "com.duckduckgo.syncrecovery.check.performed")
        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true
        )

        // When
        let result = sut.shouldShowPrompt()

        // Then
        XCTAssertFalse(result)
    }

    func testShouldShowPrompt_WhenSyncAlreadyEnabled_ReturnsFalse() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.newDeviceSyncPrompt]
        mockSyncService.account = SyncAccount(
            deviceId: "test-device",
            deviceName: "Test Device",
            deviceType: "phone",
            userId: "test-user",
            primaryKey: Data(),
            secretKey: Data(),
            token: "test-token",
            state: .active
        )
        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true
        )

        // When
        let result = sut.shouldShowPrompt()

        // Then
        XCTAssertFalse(result)
    }

    func testShouldShowPrompt_WhenAllConditionsMet_SetsPerformedCheckFlag() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.newDeviceSyncPrompt]
        mockSyncService.account = nil
        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true
        )

        // When
        _ = sut.shouldShowPrompt()

        let storedValue = try mockKeyValueStore.object(forKey: "com.duckduckgo.syncrecovery.check.performed") as? Bool
        XCTAssertEqual(storedValue, true)
    }

    func testShouldShowPrompt_SetsHasPerformedCheckFlag() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.newDeviceSyncPrompt]
        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true
        )

        // When
        _ = sut.shouldShowPrompt()

        // Then
        let storedValue = try mockKeyValueStore.object(forKey: "com.duckduckgo.syncrecovery.check.performed") as? Bool
        XCTAssertEqual(storedValue, true)
    }

    func testShouldShowPrompt_WhenVaultNotEmpty_ReturnsFalse() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.newDeviceSyncPrompt]
        mockSyncService.account = nil

        let mockVault = (try? MockSecureVaultFactory.makeVault(reporter: nil))!
        mockVault.storedAccounts = [
            SecureVaultModels.WebsiteAccount(id: "1", username: "user", domain: "example.com", created: Date(), lastUpdated: Date())
        ]

        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true,
            secureVault: mockVault
        )

        // When
        let result = sut.shouldShowPrompt()

        // Then
        XCTAssertFalse(result)
    }

    func testShouldShowPrompt_WhenVaultEmptyButNotFormerAutofillUser_ReturnsFalse() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.newDeviceSyncPrompt]
        mockSyncService.account = nil

        let mockVault = (try? MockSecureVaultFactory.makeVault(reporter: nil))!
        mockVault.storedAccounts = []

        let mockUserDefaults = UserDefaults(suiteName: "test")!
        mockUserDefaults.removeObject(forKey: AutofillUsageStore.Keys.autofillLastActiveKey)
        mockUserDefaults.removeObject(forKey: AutofillUsageStore.Keys.autofillFillDateKey)
        let mockAutofillStore = AutofillUsageStore(standardUserDefaults: mockUserDefaults, appGroupUserDefaults: nil)

        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true,
            secureVault: mockVault,
            autofillUsageStore: mockAutofillStore
        )

        // When
        let result = sut.shouldShowPrompt()

        // Then
        XCTAssertFalse(result)
    }

    func testShouldShowPrompt_WhenVaultEmptyAndFormerAutofillUser_WithVaultCreatedAfterAutofillUsage_ReturnsTrue() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.newDeviceSyncPrompt]
        mockSyncService.account = nil

        let mockVault = (try? MockSecureVaultFactory.makeVault(reporter: nil))!
        mockVault.storedAccounts = []

        let mockUserDefaults = UserDefaults(suiteName: "test")!
        let twoDaysAgo = Date().addingTimeInterval(-172800)
        mockUserDefaults.set(twoDaysAgo, forKey: AutofillUsageStore.Keys.autofillLastActiveKey)
        mockUserDefaults.set(twoDaysAgo, forKey: AutofillUsageStore.Keys.autofillFillDateKey)
        let mockAutofillStore = AutofillUsageStore(standardUserDefaults: mockUserDefaults, appGroupUserDefaults: nil)

        let yesterday = Date().addingTimeInterval(-86400)
        let mockVaultDateProvider = MockVaultDateProvider(vaultCreationDate: yesterday)

        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true,
            secureVault: mockVault,
            autofillUsageStore: mockAutofillStore,
            vaultDateProvider: mockVaultDateProvider
        )

        // When
        let result = sut.shouldShowPrompt()

        // Then
        XCTAssertTrue(result)
    }

    func testShouldShowPrompt_WhenVaultEmptyAndFormerAutofillUser_WithVaultCreatedBeforeAutofillUsage_ReturnsFalse() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.newDeviceSyncPrompt]
        mockSyncService.account = nil

        let mockVault = (try? MockSecureVaultFactory.makeVault(reporter: nil))!
        mockVault.storedAccounts = []

        let mockUserDefaults = UserDefaults(suiteName: "test")!
        let yesterday = Date().addingTimeInterval(-86400)
        mockUserDefaults.set(yesterday, forKey: AutofillUsageStore.Keys.autofillLastActiveKey)
        mockUserDefaults.set(yesterday, forKey: AutofillUsageStore.Keys.autofillFillDateKey)
        let mockAutofillStore = AutofillUsageStore(standardUserDefaults: mockUserDefaults, appGroupUserDefaults: nil)

        let twoDaysAgo = Date().addingTimeInterval(-172800)
        let mockVaultDateProvider = MockVaultDateProvider(vaultCreationDate: twoDaysAgo)

        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true,
            secureVault: mockVault,
            autofillUsageStore: mockAutofillStore,
            vaultDateProvider: mockVaultDateProvider
        )

        // When
        let result = sut.shouldShowPrompt()

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Presenter Tests

    func testPresenter_LazyInitialization() async {
        // Given
        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true
        )

        // When/Then - Presenter should be created lazily
        XCTAssertNotNil(sut.presenter)
        XCTAssertTrue(sut.presenter is SyncRecoveryPromptPresenter)
    }

    // MARK: - tryPresentSyncRecoveryPrompt Tests

    func testTryPresentSyncRecoveryPrompt_WhenShouldShowPromptFalse_ReturnsFalse() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [] // Feature disabled
        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true
        )
        let viewController = UIViewController()

        // When
        let result = sut.tryPresentSyncRecoveryPrompt(from: viewController) { _ in }

        // Then
        XCTAssertFalse(result)
    }

    func testTryPresentSyncRecoveryPrompt_WhenShouldShowPromptTrue_ReturnsTrue() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.newDeviceSyncPrompt]
        mockSyncService.account = nil
        sut = SyncRecoveryPromptService(
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            keyValueStore: mockKeyValueStore,
            isOnboardingComplete: true
        )
        let viewController = UIViewController()

        // When
        let result = sut.tryPresentSyncRecoveryPrompt(from: viewController) { _ in }

        XCTAssertNotNil(result)
    }
}

struct MockVaultDateProvider: VaultCreationDateProvider {
    let vaultCreationDate: Date?

    func getVaultCreationDate() -> Date? {
        return vaultCreationDate
    }
}
