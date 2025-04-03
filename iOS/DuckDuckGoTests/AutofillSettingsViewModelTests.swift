//
//  AutofillSettingsViewModelTests.swift
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
@testable import DuckDuckGo
import BrowserServicesKit

final class AutofillSettingsViewModelTests: XCTestCase {
    
    private let appSettings = AppSettingsMock()
    private let vault = (try? MockSecureVaultFactory.makeVault(reporter: nil))!
    private var manager: AutofillNeverPromptWebsitesManager!
    private var mockDelegate: MockAutofillSettingsViewModelDelegate!
    private var viewModel: AutofillSettingsViewModel!
    
    override func setUpWithError() throws {
        super.setUp()
        setupUserDefault(with: #file)
        manager = AutofillNeverPromptWebsitesManager(secureVault: vault)
        mockDelegate = MockAutofillSettingsViewModelDelegate()
        
        viewModel = AutofillSettingsViewModel(
            appSettings: appSettings,
            autofillNeverPromptWebsitesManager: manager,
            secureVault: vault,
            source: .settings
        )
        viewModel.delegate = mockDelegate
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockDelegate = nil
        manager = nil

        try super.tearDownWithError()
    }
    
    func testInitCorrectlySetsSavePasswordsEnabled() {
        // Given
        appSettings.autofillCredentialsEnabled = true
        
        // When
        let viewModel = AutofillSettingsViewModel(
            appSettings: appSettings,
            autofillNeverPromptWebsitesManager: manager,
            secureVault: vault,
            source: .settings
        )
        
        // Then
        XCTAssertTrue(viewModel.savePasswordsEnabled)
    }
    
    func testInitCallsUpdatePasswordsCount() {
        // Given
        vault.storedAccounts = [
            SecureVaultModels.WebsiteAccount(id: "1", title: nil, username: "One", domain: "testsite.com", created: Date(), lastUpdated: Date()),
            SecureVaultModels.WebsiteAccount(id: "2", title: nil, username: "Two", domain: "testsite.com", created: Date(), lastUpdated: Date()),
            SecureVaultModels.WebsiteAccount(id: "3", title: nil, username: "Three", domain: "testsite.com", created: Date(), lastUpdated: Date()),
            SecureVaultModels.WebsiteAccount(id: "4", title: nil, username: "Four", domain: "testsite.com", created: Date(), lastUpdated: Date()),
            SecureVaultModels.WebsiteAccount(id: "5", title: nil, username: "Five", domain: "testsite.com", created: Date(), lastUpdated: Date())
        ]
        
        // When
        let viewModel = AutofillSettingsViewModel(
            appSettings: appSettings,
            autofillNeverPromptWebsitesManager: manager,
            secureVault: vault,
            source: .settings
        )
        
        // Then
        XCTAssertEqual(viewModel.passwordsCount, 5)
    }
    
    // MARK: - SavePasswordsEnabled Tests
    
    func testTogglingPasswordsEnabledUpdatesAppSettings() {
        // Given
        appSettings.autofillCredentialsEnabled = false
        
        // When
        viewModel.savePasswordsEnabled = true
        
        // Then
        XCTAssertTrue(appSettings.autofillCredentialsEnabled)
    }
    
    // MARK: - UpdatePasswordsCount Tests
    
    func testUpdatePasswordsCountWhenSecureVaultIsNil() {
        // Given
        let viewModel = AutofillSettingsViewModel(
            appSettings: appSettings,
            autofillNeverPromptWebsitesManager: manager,
            secureVault: nil,
            source: .settings
        )
        
        // When/Then (handles nil vault)
        viewModel.updatePasswordsCount()
    }
    
    func testUpdatePasswordsCountSuccess() {
        // Given
        vault.storedAccounts = [
            SecureVaultModels.WebsiteAccount(id: "1", title: nil, username: "One", domain: "testsite.com", created: Date(), lastUpdated: Date()),
            SecureVaultModels.WebsiteAccount(id: "2", title: nil, username: "Two", domain: "testsite.com", created: Date(), lastUpdated: Date()),
        ]
        
        
        // When
        viewModel.updatePasswordsCount()
        
        // Then
        XCTAssertEqual(viewModel.passwordsCount, 2)
        
        vault.storedAccounts.append(SecureVaultModels.WebsiteAccount(id: "3", title: nil, username: "Three", domain: "testsite.com", created: Date(), lastUpdated: Date()))
        
        viewModel.updatePasswordsCount()
        
        XCTAssertEqual(viewModel.passwordsCount, 3)
    }
    
    // MARK: - Navigation Tests
    
    func testNavigateToPasswords() {
        // When
        viewModel.navigateToPasswords()
        
        // Then
        XCTAssertTrue(mockDelegate.navigateToPasswordsCalled)
        XCTAssertTrue(mockDelegate.navigateToPasswordsViewModel === viewModel)
    }
    
    func testNavigateToFileImport() {
        // When
        viewModel.navigateToFileImport()
        
        // Then
        XCTAssertTrue(mockDelegate.navigateToFileImportCalled)
        XCTAssertTrue(mockDelegate.navigateToFileImportViewModel === viewModel)
    }
    
    func testNavigateToImportViaSync() {
        // When
        viewModel.navigateToImportViaSync()
        
        // Then
        XCTAssertTrue(mockDelegate.navigateToImportViaSyncCalled)
        XCTAssertTrue(mockDelegate.navigateToImportViaSyncViewModel === viewModel)
    }
    
    // MARK: - Excluded Sites Tests
    
    func testShouldShowNeverPromptResetWhenEmpty() {
        // Given
        XCTAssertTrue(manager.deleteAllNeverPromptWebsites())
        
        // Then
        XCTAssertFalse(viewModel.shouldShowNeverPromptReset())
    }
    
    func testShouldShowNeverPromptResetWhenNotEmpty() {
        // Given
        XCTAssertTrue(manager.deleteAllNeverPromptWebsites())
        XCTAssertNoThrow(try manager.saveNeverPromptWebsite("example.com"))
        
        // Then
        XCTAssertTrue(viewModel.shouldShowNeverPromptReset())
    }
    
    func testResetExcludedSitesShowsConfirmation() {
        // When
        viewModel.resetExcludedSites()
        
        // Then
        XCTAssertTrue(viewModel.showingResetConfirmation)
    }
    
    func testConfirmResetExcludedSites() {
        // Given
        XCTAssertTrue(manager.deleteAllNeverPromptWebsites())
        XCTAssertNoThrow(try manager.saveNeverPromptWebsite("example.com"))
        viewModel.showingResetConfirmation = true
        
        // When
        viewModel.confirmResetExcludedSites()
        
        // Then
        XCTAssertTrue(manager.neverPromptWebsites.isEmpty)
        XCTAssertFalse(viewModel.showingResetConfirmation)
    }
    
    func testCancelResetExcludedSites() {
        // Given
        XCTAssertTrue(manager.deleteAllNeverPromptWebsites())
        XCTAssertNoThrow(try manager.saveNeverPromptWebsite("example.com"))
        viewModel.showingResetConfirmation = true
        
        // When
        viewModel.cancelResetExcludedSites()
        
        // Then
        XCTAssertFalse(manager.neverPromptWebsites.isEmpty)
        XCTAssertFalse(viewModel.showingResetConfirmation)
    }
    
}

private class MockAutofillSettingsViewModelDelegate: AutofillSettingsViewModelDelegate {
    
    var navigateToPasswordsCalled = false
    var navigateToPasswordsViewModel: AutofillSettingsViewModel?
    
    var navigateToFileImportCalled = false
    var navigateToFileImportViewModel: AutofillSettingsViewModel?
    
    var navigateToImportViaSyncCalled = false
    var navigateToImportViaSyncViewModel: AutofillSettingsViewModel?
    
    func navigateToPasswords(viewModel: AutofillSettingsViewModel) {
        navigateToPasswordsCalled = true
        navigateToPasswordsViewModel = viewModel
    }
    
    func navigateToFileImport(viewModel: AutofillSettingsViewModel) {
        navigateToFileImportCalled = true
        navigateToFileImportViewModel = viewModel
    }
    
    func navigateToImportViaSync(viewModel: AutofillSettingsViewModel) {
        navigateToImportViaSyncCalled = true
        navigateToImportViaSyncViewModel = viewModel
    }
}
