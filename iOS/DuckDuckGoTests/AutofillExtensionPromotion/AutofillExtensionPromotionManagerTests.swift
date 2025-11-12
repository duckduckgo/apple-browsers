//
//  AutofillExtensionPromotionManagerTests.swift
//  DuckDuckGo
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
import AuthenticationServices
@testable import DuckDuckGo
import Persistence
@testable import PersistenceTestingUtils
@testable import BrowserServicesKitTestsUtils

@available(iOS 18.0, *)
final class AutofillExtensionPromotionManagerTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockKeyValueStore: ThrowingKeyValueStoring!
    private var mockCredentialStore: MockASCredentialIdentityStore!
    private var manager: AutofillExtensionPromotionManager!

    override func setUpWithError() throws {
        try super.setUpWithError()

        mockFeatureFlagger = MockFeatureFlagger()
        mockKeyValueStore = try MockKeyValueFileStore(throwOnInit: nil)
        mockCredentialStore = MockASCredentialIdentityStore()
    }

    override func tearDownWithError() throws {
        mockFeatureFlagger = nil
        mockKeyValueStore = nil
        mockCredentialStore = nil
        manager = nil

        try super.tearDownWithError()
    }

    // MARK: - shouldShowPromotion Tests

    func testShouldShowPromotion_WhenFeatureDisabled_ReturnsFalse() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        let installDate = Date().addingTimeInterval(-8 * 24 * 60 * 60) // 8 days ago
        manager = makeManager(installDate: installDate, isEnabled: false)

        // When
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 5) { shouldShow in
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(result)
    }

    func testShouldShowPromotion_WhenPromotionPreviouslyDismissed_ReturnsFalse() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        try mockKeyValueStore.set(true, forKey: "com.duckduckgo.autofill.extension.promo.passwords.dismissed")
        let installDate = Date().addingTimeInterval(-8 * 24 * 60 * 60) // 8 days ago
        manager = makeManager(installDate: installDate, isEnabled: false)

        // When
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 5) { shouldShow in
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(result)
    }

    func testShouldShowPromotion_WhenInstallDateIsTooRecent_ReturnsFalse() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        let installDate = Date().addingTimeInterval(-3 * 24 * 60 * 60) // 3 days ago (less than 7 day minimum)
        manager = makeManager(installDate: installDate, isEnabled: false)

        // When
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 5) { shouldShow in
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(result)
    }

    func testShouldShowPromotion_WhenInstallDateIsNil_ReturnsFalse() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        manager = makeManager(installDate: nil, isEnabled: false)

        // When
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 5) { shouldShow in
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(result)
    }

    @available(iOS 18.0, *)
    func testShouldShowPromotion_WhenCredentialProviderAlreadyEnabled_ReturnsFalse() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        let installDate = Date().addingTimeInterval(-8 * 24 * 60 * 60) // 8 days ago
        manager = makeManager(installDate: installDate, isEnabled: true)

        // When
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 5) { shouldShow in
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(result)
    }

    func testShouldShowPromotion_WhenCredentialCountBelowMinimum_ReturnsFalse() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        let installDate = Date().addingTimeInterval(-8 * 24 * 60 * 60) // 8 days ago
        manager = makeManager(installDate: installDate, isEnabled: false)

        // When
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 3) { shouldShow in // Less than minimum of 4
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(result)
    }

    @available(iOS 18.0, *)
    func testShouldShowPromotion_WhenAllConditionsMet_ReturnsTrue() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        let installDate = Date().addingTimeInterval(-8 * 24 * 60 * 60) // 8 days ago
        manager = makeManager(installDate: installDate, isEnabled: false)

        // When
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 5) { shouldShow in
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        // Then
        XCTAssertTrue(result)
    }

    @available(iOS 18.0, *)
    func testShouldShowPromotion_WhenCredentialCountExactlyAtMinimum_ReturnsTrue() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        let installDate = Date().addingTimeInterval(-8 * 24 * 60 * 60) // 8 days ago
        manager = makeManager(installDate: installDate, isEnabled: false)

        // When
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 4) { shouldShow in // Exactly at minimum
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        // Then
        XCTAssertTrue(result)
    }

    @available(iOS 18.0, *)
    func testShouldShowPromotion_WhenInstallAgeExactlyAtMinimum_ReturnsTrue() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        let installDate = Date().addingTimeInterval(-7 * 24 * 60 * 60) // Exactly 7 days ago
        manager = makeManager(installDate: installDate, isEnabled: false)

        // When
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 5) { shouldShow in
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        // Then
        XCTAssertTrue(result)
    }

    // MARK: - markPromotionDismissed Tests

    func testMarkPromotionDismissed_SetsStoredValue() throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        let installDate = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        manager = makeManager(installDate: installDate, isEnabled: false)

        // When
        manager.markPromotionDismissed()

        // Then
        let storedValue = try mockKeyValueStore.object(forKey: "com.duckduckgo.autofill.extension.promo.passwords.dismissed") as? Bool
        XCTAssertEqual(storedValue, true)
    }

    func testMarkPromotionDismissed_PreventsPromotionFromShowing() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        let installDate = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        manager = makeManager(installDate: installDate, isEnabled: false)

        // When
        manager.markPromotionDismissed()

        // Then
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 5) { shouldShow in
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertFalse(result)
    }

    // MARK: - resetPromotionDismissal Tests

    func testResetPromotionDismissal_ClearsStoredValue() throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        let installDate = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        manager = makeManager(installDate: installDate, isEnabled: false)
        try mockKeyValueStore.set(true, forKey: "com.duckduckgo.autofill.extension.promo.passwords.dismissed")

        // When
        manager.resetPromotionDismissal()

        // Then
        let storedValue = try mockKeyValueStore.object(forKey: "com.duckduckgo.autofill.extension.promo.passwords.dismissed") as? Bool
        XCTAssertEqual(storedValue, false)
    }

    @available(iOS 18.0, *)
    func testResetPromotionDismissal_AllowsPromotionToShowAgain() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.canPromoteAutofillExtensionInPasswordManagement]
        let installDate = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        manager = makeManager(installDate: installDate, isEnabled: false)
        try mockKeyValueStore.set(true, forKey: "com.duckduckgo.autofill.extension.promo.passwords.dismissed")

        // When
        manager.resetPromotionDismissal()

        // Then
        let expectation = expectation(description: "Completion called")
        var result = false
        manager.shouldShowPromotion(totalCredentialsCount: 5) { shouldShow in
            result = shouldShow
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(result)
    }

    // MARK: - Helper Methods

    private func makeManager(installDate: Date?, isEnabled: Bool) -> AutofillExtensionPromotionManager {
        mockCredentialStore.isEnabled = isEnabled
        return AutofillExtensionPromotionManager(
            featureFlagger: mockFeatureFlagger,
            credentialStore: mockCredentialStore,
            keyValueStore: mockKeyValueStore,
            installDateProvider: { installDate },
            currentDateProvider: { Date() }
        )
    }
}
