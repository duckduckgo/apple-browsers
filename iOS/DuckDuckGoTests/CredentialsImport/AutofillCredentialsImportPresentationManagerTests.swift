//
//  AutofillCredentialsImportPresentationManagerTests.swift
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
@testable import BrowserServicesKit

final class AutofillCredentialsImportPresentationManagerTests: XCTestCase {
    
    private var manager: AutofillCredentialsImportPresentationManager!
    private var importState: MockAutofillLoginImportState!
    
    override func setUp() {
        super.setUp()
        importState = MockAutofillLoginImportState()
        manager = AutofillCredentialsImportPresentationManager(loginImportStateProvider: importState)
    }
    
    override func tearDown() {
        importState = nil
        manager = nil
        super.tearDown()
    }
    
    // MARK: - autofillUserScriptShouldShowPasswordImportDialog Tests
    
    func testWhenCredentialsForDomainAreNotEmpty_ThenAutofillUserScriptShouldShowPasswordImportDialogIsFalse() {
        let result = autofillUserScriptShouldShowPasswordImportDialogResult(credentials: createListOfCredentials())
        
        XCTAssertFalse(result)
    }
    
    func testWhenTotalCredentialsCountIs25OrMore_ThenAutofillUserScriptShouldShowPasswordImportDialogIsFalse() {
        let result = autofillUserScriptShouldShowPasswordImportDialogResult(totalCredentialsCount: 25)
        
        XCTAssertFalse(result)
    }
    
    func testWhenUserHasImportedLogins_ThenAutofillUserScriptShouldShowPasswordImportDialogIsFalse() {
        let result = autofillUserScriptShouldShowPasswordImportDialogResult(hasImportedLogins: true)
        
        XCTAssertFalse(result)
    }
    
    func testWhenAutofillIsDisabled_ThenAutofillUserScriptShouldShowPasswordImportDialogIsFalse() {
        let result = autofillUserScriptShouldShowPasswordImportDialogResult(isAutofillEnabled: false)
        
        XCTAssertFalse(result)
    }
    
    func testWhenHasNeverPromptWebsitesIsTrue_ThenAutofillUserScriptShouldShowPasswordImportDialogIsFalse() {
        let result = autofillUserScriptShouldShowPasswordImportDialogResult(hasNeverPromptWebsites: true)
        
        XCTAssertFalse(result)
    }
    
    func testWhenCredentialsImportPromoInBrowserPermanentlyDismissed_ThenAutofillUserScriptShouldShowPasswordImportDialogIsFalse() {
        let result = autofillUserScriptShouldShowPasswordImportDialogResult(isCredentialsImportPromoInBrowserPermanentlyDismissed: true)
        
        XCTAssertFalse(result)
    }
    
    func testWhenImportPromoInBrowserPromptFeatureDisabled_ThenAutofillUserScriptShouldShowPasswordImportDialogIsFalse() {
        let result = autofillUserScriptShouldShowPasswordImportDialogResult(isImportPromoInBrowserPromptFeatureEnabled: false)
        
        XCTAssertFalse(result)
    }
    
    @available(iOS 18.2, *)
    func testWhenAllOtherCredentialsImportConditionsAreMet_ThenAutofillUserScriptShouldShowPasswordImportDialogIsTrue() {
        let result = autofillUserScriptShouldShowPasswordImportDialogResult()
        
        XCTAssertTrue(result)
    }
    
    func testWhenBelowiOS18_2_ThenAutofillUserScriptShouldShowPasswordImportDialogIsFalse() throws {
        guard #unavailable(iOS 18.2) else {
            throw XCTSkip("This test only runs on iOS < 18.2")
        }
        
        let result = autofillUserScriptShouldShowPasswordImportDialogResult()
        
        XCTAssertFalse(result)
    }
    
    // MARK: - passwordsScreenShouldShowPasswordImportPromotion Tests
    
    func testWhenTotalCredentialsCountIs25OrMore_ThenPasswordsScreenShouldShowPasswordImportPromotionIsFalse() {
        let result = passwordsScreenShouldShowPasswordImportPromotionResult(totalCredentialsCount: 25)
        
        XCTAssertFalse(result)
    }
    
    func testWhenUserHasImportedLogins_ThenPasswordsScreenShouldShowPasswordImportPromotionIsFalse() {
        let result = passwordsScreenShouldShowPasswordImportPromotionResult(hasImportedLogins: true)
        
        XCTAssertFalse(result)
    }
    
    func testWhenImportPromoInPasswordsScreenFeatureDisabled_ThenPasswordsScreenShouldShowPasswordImportPromotionIsFalse() {
        let result = passwordsScreenShouldShowPasswordImportPromotionResult(isImportPromoInPasswordsScreenFeatureEnabled: false)
        
        XCTAssertFalse(result)
    }
    
    func testWhenCredentialsImportPromoInPasswordsScreenPermanentlyDismissed_ThenPasswordsScreenShouldShowPasswordImportPromotionIsFalse() {
        let result = passwordsScreenShouldShowPasswordImportPromotionResult(isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed: true)
        
        XCTAssertFalse(result)
    }
    
    func testWhenCredentialsImportPromptPresentationCountIs5OrMore_ThenAutofillUserScriptShouldShowPasswordImportDialogIsFalse() {
        importState.credentialsImportPromptPresentationCount = 5
        let result = autofillUserScriptShouldShowPasswordImportDialogResult()

        XCTAssertFalse(result)
    }

    func testWhenCredentialsImportPromptPresentationCountIsLessThan5_ThenAutofillUserScriptShouldShowPasswordImportDialogConsidersOtherConditions() {
        importState.credentialsImportPromptPresentationCount = 4
        let result = autofillUserScriptShouldShowPasswordImportDialogResult()

        if #available(iOS 18.2, *) {
            XCTAssertTrue(result)
        } else {
            XCTAssertFalse(result)
        }
    }

    @available(iOS 18.2, *)
    func testWhenAllPasswordsScreenImportConditionsAreMet_ThenPasswordsScreenShouldShowPasswordImportPromotionIsTrue() {
        let result = passwordsScreenShouldShowPasswordImportPromotionResult()
        
        XCTAssertTrue(result)
    }
    
    func testWhenBelowiOS18_2_ThenPasswordsScreenShouldShowPasswordImportPromotionIsFalse() throws {
        guard #unavailable(iOS 18.2) else {
            throw XCTSkip("This test only runs on iOS < 18.2")
        }
        
        let result = passwordsScreenShouldShowPasswordImportPromotionResult()
        
        XCTAssertFalse(result)
    }
    
    // MARK: - Dismissal Tests
    
    func testWhenPermanentCredentialsImportPromptDismissalIsRequested_ThenStateFlagIsSetToTrue() {
        manager.autofillUserScriptDidRequestPermanentCredentialsImportPromptDismissal()
        
        XCTAssertTrue(importState.isCredentialsImportPromoInBrowserPermanentlyDismissed)
    }
    
    func testWhenPasswordsScreenPermanentCredentialsImportPromptDismissalIsRequested_ThenStateFlagIsSetToTrue() {
        manager.passwordsScreenDidRequestPermanentCredentialsImportPromptDismissal()
        
        XCTAssertTrue(importState.isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed)
    }
    
    
    // MARK: - Helper Methods
    
    private func autofillUserScriptShouldShowPasswordImportDialogResult(
        credentials: [SecureVaultModels.WebsiteCredentials] = [],
        credentialsProvider: SecureVaultModels.CredentialsProvider = SecureVaultModels.CredentialsProvider(name: .duckduckgo, locked: false),
        totalCredentialsCount: Int = 24,
        hasImportedLogins: Bool = false,
        hasNeverPromptWebsites: Bool = false,
        isAutofillEnabled: Bool = true,
        isCredentialsImportPromoInBrowserPermanentlyDismissed: Bool = false,
        isImportPromoInBrowserPromptFeatureEnabled: Bool = true) -> Bool {
            
            importState.stubHasNeverPromptWebsitesForDomain = hasNeverPromptWebsites
            importState.hasImportedLogins = hasImportedLogins
            importState.isCredentialsImportPromoInBrowserPermanentlyDismissed = isCredentialsImportPromoInBrowserPermanentlyDismissed
            importState.isAutofillEnabled = isAutofillEnabled
            importState.isImportPromoInBrowserPromptFeatureEnabled = isImportPromoInBrowserPromptFeatureEnabled
            
            return manager.autofillUserScriptShouldShowPasswordImportDialog(
                domain: "test.com",
                credentials: credentials,
                credentialsProvider: credentialsProvider,
                totalCredentialsCount: totalCredentialsCount
            )
        }
    
    private func passwordsScreenShouldShowPasswordImportPromotionResult(
        totalCredentialsCount: Int = 24,
        hasImportedLogins: Bool = false,
        isImportPromoInPasswordsScreenFeatureEnabled: Bool = true,
        isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed: Bool = false) -> Bool {
            
            importState.hasImportedLogins = hasImportedLogins
            importState.isImportPromoInPasswordsScreenFeatureEnabled = isImportPromoInPasswordsScreenFeatureEnabled
            importState.isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed = isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed
            
            return manager.passwordsScreenShouldShowPasswordImportPromotion(totalCredentialsCount: totalCredentialsCount)
        }
    
    private func createListOfCredentials(withPassword password: Data? = nil) -> [SecureVaultModels.WebsiteCredentials] {
        var credentialsList = [SecureVaultModels.WebsiteCredentials]()
        for i in 0...10 {
            let account = SecureVaultModels.WebsiteAccount(
                id: "id\(i)",
                username: "username\(i)",
                domain: "domain.com",
                created: Date(),
                lastUpdated: Date()
            )
            let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password)
            credentialsList.append(credentials)
        }
        return credentialsList
    }
}

// MARK: - Mock Classes

final class MockAutofillLoginImportState: AutofillLoginImportStateProvider, AutofillLoginImportStateStoring {
    var isImportPromoInBrowserPromptFeatureEnabled: Bool = true
    
    var isImportPromoInPasswordsScreenFeatureEnabled: Bool = true

    var credentialsImportPromptPresentationCount: Int = 0

    var hasImportedLogins: Bool = false
    
    var isAutofillEnabled: Bool = true
    
    var isCredentialsImportPromoInBrowserPermanentlyDismissed: Bool = false
    
    var isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed: Bool = false
    
    var stubHasNeverPromptWebsitesForDomain = false
    func hasNeverPromptWebsitesFor(_ domain: String) -> Bool {
        stubHasNeverPromptWebsitesForDomain
    }
}
