//
//  AutofillVaultUserScriptTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import WebKit
import UserScript
import Common
@testable import BrowserServicesKit

class AutofillVaultUserScriptTests: XCTestCase {

    lazy var hostProvider: UserScriptHostProvider = SecurityOriginHostProvider()

    lazy var userScript: AutofillUserScript = {
        let embeddedConfig =
        """
        {
            "features": {
                "autofill": {
                    "status": "enabled",
                    "exceptions": []
                }
            },
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!
        let privacyConfig = AutofillTestHelper.preparePrivacyConfig(embeddedConfig: embeddedConfig)
        let properties = ContentScopeProperties(gpcEnabled: false, sessionKey: "1234", messageSecret: "1234", featureToggles: ContentScopeFeatureToggles.allTogglesOn)
        let sourceProvider = DefaultAutofillSourceProvider(privacyConfigurationManager: privacyConfig,
                                                           properties: properties,
                                                           isDebug: false)
        return AutofillUserScript(scriptSourceProvider: sourceProvider, hostProvider: hostProvider)
    }()

    let userContentController = WKUserContentController()

    var encryptedMessagingParams: [String: Any] {
        return [
            "messageHandling": [
                "iv": Array(repeating: UInt8(1), count: 32),
                "key": Array(repeating: UInt8(1), count: 32),
                "secret": userScript.generatedSecret,
                "methodName": "test-methodName"
            ] as [String: Any]
        ]
    }

    let tld = TLD()

    @available(macOS 11, iOS 14, *)
    func testWhenAccountsForDomainRequested_ThenDelegateCalled() {
        class GetAccountsDelegate: MockSecureVaultDelegate {

            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestAccountsForDomain domain: String,
                                             completionHandler: @escaping ([SecureVaultModels.WebsiteAccount], SecureVaultModels.CredentialsProvider) -> Void) {
                completionHandler([
                    SecureVaultModels.WebsiteAccount(id: "1", username: "1@example.com", domain: "domain", created: Date(), lastUpdated: Date()),
                    SecureVaultModels.WebsiteAccount(id: "2", username: "2@example.com", domain: "domain", created: Date(), lastUpdated: Date())
                ], SecureVaultModels.CredentialsProvider(name: .duckduckgo, locked: false))
            }
        }

        let delegate = GetAccountsDelegate()
        userScript.vaultDelegate = delegate

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetAccounts", body: encryptedMessagingParams, webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertNotNil($0)
            XCTAssertNil($1)

            let data = ($0 as? String)?.data(using: .utf8)
            let response = try? JSONDecoder().decode(AutofillUserScript.RequestVaultAccountsResponse.self, from: data!)
            XCTAssertEqual(response?.success.count, 2)

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)
   }

    @available(macOS 11, iOS 14, *)
    func testWhenCredentialForAccountRequestedFromMatchingDomain_ThenDelegateCalled() {
        class GetCredentialsDelegate: MockSecureVaultDelegate {

            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestCredentialsForAccount accountId: String,
                                             completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?, SecureVaultModels.CredentialsProvider) -> Void) {
                completionHandler(.init(account: .init(id: accountId,
                                                       username: "1@example.com",
                                                       domain: "domain1.com",
                                                       created: Date(),
                                                       lastUpdated: Date()),
                                        password: "password".data(using: .utf8)!),
                                  SecureVaultModels.CredentialsProvider(name: .duckduckgo, locked: false))
            }

        }

        let randomAccountId = Int.random(in: 0 ..< Int.max) // JS will come through as a Int rather than Int64

        hostProvider = MockHostProvider(host: "domain1.com")

        let delegate = GetCredentialsDelegate()
        delegate.tld = tld
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["id"] = "\(randomAccountId)"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetAutofillCredentials", body: body, webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertNotNil($0)
            XCTAssertNil($1)

            let data = ($0 as? String)?.data(using: .utf8)
            let response = try? JSONDecoder().decode(AutofillUserScript.RequestVaultCredentialsForAccountResponse.self, from: data!)
            XCTAssertEqual(Int64(response!.success.id), Int64(randomAccountId))

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    @available(macOS 11, iOS 14, *)
    func testWhenCredentialForAccountRequestedAndRequestedDomainMatchesAfterRemovingWWWFromStoredDomainPrefix_ThenCredentialsReturned() {
        class GetCredentialsDelegate: MockSecureVaultDelegate {

            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestCredentialsForAccount accountId: String,
                                             completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?, SecureVaultModels.CredentialsProvider) -> Void) {

                completionHandler(.init(account: .init(id: accountId,
                                                       username: "1@example.com",
                                                       domain: "www.domain1.com",
                                                       created: Date(),
                                                       lastUpdated: Date()),
                                        password: "password".data(using: .utf8)!),
                                  SecureVaultModels.CredentialsProvider(name: .duckduckgo, locked: false))

            }

        }

        let randomAccountId = Int.random(in: 0 ..< Int.max) // JS will come through as a Int rather than Int64

        hostProvider = MockHostProvider(host: "domain1.com")

        let delegate = GetCredentialsDelegate()
        delegate.tld = tld
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["id"] = "\(randomAccountId)"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetAutofillCredentials",
                                          body: body,
                                          webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertNotEqual($0 as? String, "{}")
            XCTAssertNil($1)

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    @available(macOS 11, iOS 14, *)
    func testWhenCredentialForAccountRequestedAndRequestedDomainMatchesAfterRemovingWWWPrefixFromProvidedDomain_ThenCredentialsReturned() {
        class GetCredentialsDelegate: MockSecureVaultDelegate {

            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestCredentialsForAccount accountId: String,
                                             completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?, SecureVaultModels.CredentialsProvider) -> Void) {
                completionHandler(.init(account: .init(id: accountId,
                                                       username: "1@example.com",
                                                       domain: "domain1.com",
                                                       created: Date(),
                                                       lastUpdated: Date()),
                                        password: "password".data(using: .utf8)!),
                                  SecureVaultModels.CredentialsProvider(name: .duckduckgo, locked: false))

            }

        }

        let randomAccountId = Int.random(in: 0 ..< Int.max) // JS will come through as a Int rather than Int64

        hostProvider = MockHostProvider(host: "www.domain1.com")

        let delegate = GetCredentialsDelegate()
        delegate.tld = tld
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["id"] = "\(randomAccountId)"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetAutofillCredentials",
                                          body: body,
                                          webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertNotEqual($0 as? String, "{}")
            XCTAssertNil($1)

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    @available(macOS 11, iOS 14, *)
    func testWhenCredentialForAccountRequestedAndDomainsDontMatch_ThenCredentialsNotReturned() {
        class GetCredentialsDelegate: MockSecureVaultDelegate {

            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestCredentialsForAccount accountId: String,
                                             completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?, SecureVaultModels.CredentialsProvider) -> Void) {

                completionHandler(.init(account: .init(id: accountId,
                                                       username: "1@example.com",
                                                       domain: "domain1.com",
                                                       created: Date(),
                                                       lastUpdated: Date()),
                                        password: "password".data(using: .utf8)!),
                                  SecureVaultModels.CredentialsProvider(name: .duckduckgo, locked: false))

            }

        }

        let randomAccountId = Int.random(in: 0 ..< Int.max) // JS will come through as a Int rather than Int64

        let delegate = GetCredentialsDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["id"] = "\(randomAccountId)"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetAutofillCredentials", body: body, webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertEqual($0 as? String, "{}")
            XCTAssertNil($1)

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    @available(macOS 11, iOS 14, *)
    func testWhenStoreDataCalled_ThenDelegateIsCalled() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["credentials"] = ["username": "username@example.com", "password": "password"]

        let mockWebView = MockWebView()
        let message = MockUserScriptMessage(name: "storeFormData", body: body,
                                          host: "example.com", webView: mockWebView)

        userScript.processEncryptedMessage(message, from: userContentController)

        XCTAssertEqual(delegate.lastDomain, "example.com")
        XCTAssertEqual(delegate.lastUsername, "username@example.com")
        XCTAssertEqual(delegate.lastPassword, "password")
    }

    @available(macOS 11, iOS 14, *)
    func testWhenCreditCardForIdIsRequested_ThenDelegateIsCalled() {

        class GetCreditCardDelegate: MockSecureVaultDelegate {

            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestCreditCardWithId creditCardId: Int64,
                                             completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {

                completionHandler(.init(id: creditCardId,
                                        title: "Mock Card",
                                        cardNumber: "1234123412341234",
                                        cardholderName: "Dax",
                                        cardSecurityCode: "123",
                                        expirationMonth: 11,
                                        expirationYear: 2021))

            }

        }

        let randomCardId = Int.random(in: 0 ..< Int.max)

        let delegate = GetCreditCardDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["id"] = "\(randomCardId)"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetCreditCard", body: body, webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertNotNil($0)
            XCTAssertNil($1)

            let data = ($0 as? String)?.data(using: .utf8)
            let response = try? JSONDecoder().decode(AutofillUserScript.RequestAutoFillCreditCardResponse.self, from: data!)
            XCTAssertEqual(response?.success.id, Int64(randomCardId))

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)

    }

    @available(macOS 11, iOS 14, *)
    func testWhenIdentityForIdIsRequested_ThenDelegateIsCalled() {

        class GetCreditCardDelegate: MockSecureVaultDelegate {

            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestIdentityWithId identityId: Int64,
                                             completionHandler: @escaping (SecureVaultModels.Identity?) -> Void) {
                completionHandler(.init(id: identityId,
                                        title: "Identity",
                                        created: Date(),
                                        lastUpdated: Date(),
                                        firstName: "Dax",
                                        middleName: nil,
                                        lastName: nil,
                                        birthdayDay: 1,
                                        birthdayMonth: 2,
                                        birthdayYear: 3,
                                        addressStreet: nil,
                                        addressCity: nil,
                                        addressProvince: nil,
                                        addressPostalCode: nil,
                                        addressCountryCode: nil,
                                        homePhone: nil,
                                        mobilePhone: nil,
                                        emailAddress: nil))
            }

        }

        let randomIdentityId = Int.random(in: 0 ..< Int.max)

        let delegate = GetCreditCardDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["id"] = "\(randomIdentityId)"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetIdentity", body: body, webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertNotNil($0)
            XCTAssertNil($1)

            let data = ($0 as? String)?.data(using: .utf8)
            let response = try? JSONDecoder().decode(AutofillUserScript.RequestAutoFillIdentityResponse.self, from: data!)
            XCTAssertEqual(response?.success.id, Int64(randomIdentityId))

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)

    }

    func testWhenShowPasswordManagementUIIsCalled_ThenDelegateIsCalled() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        let mockWebView = MockWebView()
        let message = MockUserScriptMessage(name: "pmHandlerOpenManagePasswords", body: encryptedMessagingParams,
                                          host: "example.com", webView: mockWebView)

        userScript.processEncryptedMessage(message, from: userContentController)

        XCTAssertEqual(delegate.lastDomain, "example.com")
    }

    func testWhenShowCardManagementUIIsCalled_ThenDelegateIsCalled() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        let mockWebView = MockWebView()
        let message = MockUserScriptMessage(name: "pmHandlerOpenManageCreditCards", body: encryptedMessagingParams,
                                          host: "example.com", webView: mockWebView)

        userScript.processEncryptedMessage(message, from: userContentController)

        XCTAssertEqual(delegate.lastDomain, "example.com")
    }

    func testWhenShowIdentityManagementUIIsCalled_ThenDelegateIsCalled() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        let mockWebView = MockWebView()
        let message = MockUserScriptMessage(name: "pmHandlerOpenManageIdentities", body: encryptedMessagingParams,
                                          host: "example.com", webView: mockWebView)

        userScript.processEncryptedMessage(message, from: userContentController)

        XCTAssertEqual(delegate.lastDomain, "example.com")
    }

    func testWhenGetRuntimeConfigurationIsCalled_ThenDelegateIsCalled() {
        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        let mockWebView = MockWebView()
        let message = MockUserScriptMessage(name: "getRuntimeConfiguration", body: encryptedMessagingParams,
                                            host: "example.com", webView: mockWebView)

        userScript.processEncryptedMessage(message, from: userContentController)

        XCTAssertEqual(delegate.lastDomain, "example.com")
    }

    func testWhenInitializingAutofillData_WhenCredentialsAreProvidedWithoutAUsername_ThenAutofillDataIsStillInitialized() {
        let password = "password"
        let detectedAutofillData = [
            "credentials": [
                "password": password
            ]
        ]

        let autofillData = AutofillUserScript.DetectedAutofillData(dictionary: detectedAutofillData)

        XCTAssertNil(autofillData.creditCard)
        XCTAssertNil(autofillData.identity)
        XCTAssertNotNil(autofillData.credentials)

        XCTAssertEqual(autofillData.credentials?.username, nil)
        XCTAssertEqual(autofillData.credentials?.password, password)
    }

    func testWhenInitializingAutofillData_WhenCredentialsAreProvidedWithAUsername_ThenAutofillDataIsStillInitialized() {
        let username = "username"
        let password = "password"

        let detectedAutofillData = [
            "credentials": [
                "username": username,
                "password": password
            ]
        ]

        let autofillData = AutofillUserScript.DetectedAutofillData(dictionary: detectedAutofillData)

        XCTAssertNil(autofillData.creditCard)
        XCTAssertNil(autofillData.identity)
        XCTAssertNotNil(autofillData.credentials)

        XCTAssertEqual(autofillData.credentials?.username, username)
        XCTAssertEqual(autofillData.credentials?.password, password)
    }

    func testWhenGetAutofilldataIsCall_ThenMainAndSubtypesAreUsed() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["mainType"] = "credentials"
        body["subType"] = "username"
        body["trigger"] = "userInitiated"

        let mockWebView = MockWebView()
        let message = MockUserScriptMessage(name: "getAutofillData", body: body, host: "example.com", webView: mockWebView)

        userScript.processEncryptedMessage(message, from: userContentController)

        let predicate = NSPredicate(block: { _, _ -> Bool in
            return !delegate.receivedCallbacks.isEmpty
        })

        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: delegate.receivedCallbacks)

        wait(for: [expectation], timeout: 5)

        XCTAssertEqual(delegate.lastSubtype, AutofillUserScript.GetAutofillDataSubType.username)
    }

    func testWhenGetAutofilldataIsCalledWithUnknownMainType_ThenTheMessageIsIgnored() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["mainType"] = "creditCards" // <- unsupported main type
        body["subType"] = "anything_else"
        body["trigger"] = "userInitiated"

        let mockWebView = MockWebView()
        let message = MockUserScriptMessage(name: "getAutofillData", body: body, host: "example.com", webView: mockWebView)

        userScript.processEncryptedMessage(message, from: userContentController)
        XCTAssertNil(delegate.lastSubtype)
    }

    func testWhenGetAutofilldataIsCalledWithUnknownSubType_ThenTheMessageIsIgnored() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["mainType"] = "credentials"
        body["subType"] = "anything_else"
        body["trigger"] = "userInitiated"

        let mockWebView = MockWebView()
        let message = MockUserScriptMessage(name: "getAutofillData", body: body, host: "example.com", webView: mockWebView)

        userScript.processEncryptedMessage(message, from: userContentController)
        XCTAssertNil(delegate.lastSubtype)
    }

    func testWhenGetAutofillDataForCreditCardsCalled_ThenDelegateMethodCalled() {
        class CreditCardDelegate: MockSecureVaultDelegate {
            var didRequestCreditCardCalled = false
            var capturedTrigger: AutofillUserScript.GetTriggerType?
            let expectation: XCTestExpectation

            init(expectation: XCTestExpectation) {
                self.expectation = expectation
                super.init()
            }

            override func autofillUserScriptDidRequestCreditCard(_: AutofillUserScript,
                                                                 trigger: AutofillUserScript.GetTriggerType,
                                                                 completionHandler: @escaping (SecureVaultModels.CreditCard?, RequestVaultDataAction) -> Void) {
                didRequestCreditCardCalled = true
                capturedTrigger = trigger

                DispatchQueue.main.async {
                    completionHandler(nil, .none)
                    self.expectation.fulfill()
                }
            }
        }

        let expect = expectation(description: #function)
        let delegate = CreditCardDelegate(expectation: expect)
        userScript.vaultDelegate = delegate

        // Construct the message body
        var body = encryptedMessagingParams
        body["mainType"] = "creditCards"
        body["subType"] = "cardNumber"
        body["trigger"] = "userInitiated"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "getAutofillData", body: body, webView: mockWebView)

        userScript.userContentController(userContentController, didReceive: message) { _, _ in }

        waitForExpectations(timeout: 1.0) { error in
            if let error = error {
                XCTFail("Expectation failed with error: \(error)")
            }
        }

        XCTAssertTrue(delegate.didRequestCreditCardCalled, "Delegate should receive the credit-card request")
        XCTAssertEqual(delegate.capturedTrigger, .userInitiated)
    }

    func testWhenGetAutofillDataFocusCalledForCreditCards_ThenDelegateMethodCalled() throws {
        throw XCTSkip("Flaky test")

        class FocusDelegate: MockSecureVaultDelegate {
            var didCallDidFocus = false
            var capturedMainType: AutofillUserScript.GetAutofillDataMainType?
            let expectation: XCTestExpectation

            init(expectation: XCTestExpectation) {
                self.expectation = expectation
                super.init()
            }

            override func autofillUserScriptDidFocus(_: AutofillUserScript,
                                                     mainType: AutofillUserScript.GetAutofillDataMainType,
                                                     completionHandler: @escaping (SecureVaultModels.CreditCard?, RequestVaultDataAction) -> Void) {
                didCallDidFocus = true
                capturedMainType = mainType

                DispatchQueue.main.async {
                    completionHandler(nil, .none)
                    self.expectation.fulfill()
                }
            }
        }

        let expect = expectation(description: #function)
        let delegate = FocusDelegate(expectation: expect)
        userScript.vaultDelegate = delegate

        // Construct the message body
        var body = encryptedMessagingParams
        body["mainType"] = "creditCards"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "getAutofillDataFocus", body: body, webView: mockWebView)

        userScript.userContentController(userContentController, didReceive: message) { _, _ in }

        waitForExpectations(timeout: 1.0) { error in
            if let error = error {
                XCTFail("Expectation failed with error: \(error)")
            }
        }

        XCTAssertTrue(delegate.didCallDidFocus, "Delegate should receive focus request")
        XCTAssertEqual(delegate.capturedMainType, .creditCards)
    }

    func testWhenGetAutofillDataFocusCalledWithNilCard_ThenNoneActionReturned() {
        class FocusDelegate: MockSecureVaultDelegate {
            override func autofillUserScriptDidFocus(_: AutofillUserScript,
                                                     mainType: AutofillUserScript.GetAutofillDataMainType,
                                                     completionHandler: @escaping (SecureVaultModels.CreditCard?, RequestVaultDataAction) -> Void) {
                DispatchQueue.main.async {
                    completionHandler(nil, .none)
                }
            }
        }

        let delegate = FocusDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["mainType"] = "creditCards"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "getAutofillDataFocus", body: body, webView: mockWebView)

        let expect = expectation(description: #function)

        userScript.userContentController(userContentController, didReceive: message) { result, error in
            defer { expect.fulfill() }

            XCTAssertNil(error, "Should not receive an error")
            XCTAssertNotNil(result, "Should receive a result")

            guard let jsonString = result as? String, let data = jsonString.data(using: .utf8) else {
                XCTFail("Could not decode `RequestVaultCreditCardResponse`")
                return
            }

            do {
                let response = try JSONDecoder().decode(AutofillUserScript.RequestVaultCreditCardResponse.self, from: data)
                XCTAssertNil(response.success.creditCards)
                XCTAssertEqual(response.success.action, RequestVaultDataAction.none)
            } catch {
                XCTFail("Failed to decode response: \(error)")
            }
        }

        waitForExpectations(timeout: 1.0)
    }

    func testWhenGetAutofillDataFocusCalledForNonCreditCardType_ThenNilCardReturned() throws {
        throw XCTSkip("Flaky test")

        class FocusDelegate: MockSecureVaultDelegate {
            var capturedMainType: AutofillUserScript.GetAutofillDataMainType?

            override func autofillUserScriptDidFocus(_: AutofillUserScript,
                                                     mainType: AutofillUserScript.GetAutofillDataMainType,
                                                     completionHandler: @escaping (SecureVaultModels.CreditCard?, RequestVaultDataAction) -> Void) {
                capturedMainType = mainType
                DispatchQueue.main.async {
                    completionHandler(nil, .none)
                }
            }
        }

        let delegate = FocusDelegate()
        userScript.vaultDelegate = delegate

        // Test with different main types
        let mainTypes = ["credentials", "identities", "unknown"]
        let expectations = mainTypes.map { expectation(description: "Response for mainType: \($0)") }

        for (index, mainType) in mainTypes.enumerated() {
            var body = encryptedMessagingParams
            body["mainType"] = mainType

            let mockWebView = MockWebView()
            let message = MockWKScriptMessage(name: "getAutofillDataFocus", body: body, webView: mockWebView)
            let currentExpectation = expectations[index]

            userScript.userContentController(userContentController, didReceive: message) { result, error in
                defer { currentExpectation.fulfill() }

                XCTAssertNil(error, "Should not receive an error for mainType: \(mainType)")
                XCTAssertNotNil(result, "Should receive a result for mainType: \(mainType)")

                guard let jsonString = result as? String, let data = jsonString.data(using: .utf8) else {
                    XCTFail("Could not decode `RequestVaultCreditCardResponse` for mainType \(mainType)")
                    return
                }

                do {
                    let response = try JSONDecoder().decode(AutofillUserScript.RequestVaultCreditCardResponse.self, from: data)
                    XCTAssertNil(response.success.creditCards)
                    XCTAssertEqual(response.success.action, RequestVaultDataAction.none)
                } catch {
                    XCTFail("Failed to decode response for mainType \(mainType): \(error)")
                }
            }
        }

        wait(for: expectations, timeout: 2.0)
    }

    func testWhenMultipleRequestsForSameMessageType_PreviousRepliesAreCancelled() {
        class SlowFocusDelegate: MockSecureVaultDelegate {
            var completionHandlers: [(SecureVaultModels.CreditCard?, RequestVaultDataAction) -> Void] = []
            let firstCallExpectation: XCTestExpectation
            let secondCallExpectation: XCTestExpectation

            init(firstCallExpectation: XCTestExpectation, secondCallExpectation: XCTestExpectation) {
                self.firstCallExpectation = firstCallExpectation
                self.secondCallExpectation = secondCallExpectation
                super.init()
            }

            override func autofillUserScriptDidFocus(_: AutofillUserScript,
                                                     mainType: AutofillUserScript.GetAutofillDataMainType,
                                                     completionHandler: @escaping (SecureVaultModels.CreditCard?, RequestVaultDataAction) -> Void) {
                // Store the handler but don't call it immediately
                completionHandlers.append(completionHandler)

                if completionHandlers.count == 1 {
                    firstCallExpectation.fulfill()
                } else if completionHandlers.count == 2 {
                    secondCallExpectation.fulfill()
                }
            }
        }

        let firstDelegateCallExpect = expectation(description: "First delegate call")
        let secondDelegateCallExpect = expectation(description: "Second delegate call")
        let firstReplyExpect = expectation(description: "First reply received")
        let secondReplyExpect = expectation(description: "Second reply received")

        let delegate = SlowFocusDelegate(firstCallExpectation: firstDelegateCallExpect,
                                         secondCallExpectation: secondDelegateCallExpect)
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["mainType"] = "creditCards"

        let mockWebView = MockWebView()

        var firstReplyReceived = false
        var firstReplyResult: String?
        var secondReplyReceived = false
        var secondReplyResult: String?

        // Send first request
        let message1 = MockWKScriptMessage(name: "getAutofillDataFocus", body: body, webView: mockWebView)
        userScript.userContentController(userContentController, didReceive: message1) { result, error in
            firstReplyReceived = true
            firstReplyResult = result as? String
            firstReplyExpect.fulfill()
        }

        // Wait for first delegate call before sending second request
        wait(for: [firstDelegateCallExpect], timeout: 1.0)

        // Send second request before first completes
        let message2 = MockWKScriptMessage(name: "getAutofillDataFocus", body: body, webView: mockWebView)
        userScript.userContentController(userContentController, didReceive: message2) { result, error in
            secondReplyReceived = true
            secondReplyResult = result as? String
            secondReplyExpect.fulfill()
        }

        // Wait for second delegate call
        wait(for: [secondDelegateCallExpect], timeout: 1.0)

        // First reply should complete quickly with cancellation
        wait(for: [firstReplyExpect], timeout: 0.5)

        // Verify first reply was cancelled
        XCTAssertTrue(firstReplyReceived)
        if let firstResult = firstReplyResult,
           let data = firstResult.data(using: .utf8),
           let response = try? JSONDecoder().decode(AutofillUserScript.NoActionResponse.self, from: data) {
            XCTAssertEqual(response.success.action, .none)
        } else {
            XCTFail("First reply should have been a NoActionResponse")
        }

        // Complete the second request
        let mockCard = SecureVaultModels.CreditCard(
                id: 789,
                title: "Test Card",
                cardNumber: "4111111111111111",
                cardholderName: "Test User",
                cardSecurityCode: "123",
                expirationMonth: 12,
                expirationYear: 2025)

        XCTAssertEqual(delegate.completionHandlers.count, 2)
        delegate.completionHandlers[1](mockCard, .fill)

        // Wait for second reply
        wait(for: [secondReplyExpect], timeout: 1.0)

        // Second reply should have the actual card data
        XCTAssertTrue(secondReplyReceived)
        if let secondResult = secondReplyResult,
           let data = secondResult.data(using: .utf8),
           let response = try? JSONDecoder().decode(AutofillUserScript.RequestVaultCreditCardResponse.self, from: data) {
            XCTAssertEqual(response.success.creditCards?.id, "789")
            XCTAssertEqual(response.success.action, .fill)
        } else {
            XCTFail("Second reply should have been a valid credit card response")
        }
    }

    func testCancelAllPendingReplies() throws {
        throw XCTSkip("Flaky test")

        class NeverCompletingDelegate: MockSecureVaultDelegate {
            let delegateCalledExpectation: XCTestExpectation
            var callCount = 0

            init(delegateCalledExpectation: XCTestExpectation) {
                self.delegateCalledExpectation = delegateCalledExpectation
                super.init()
            }

            override func autofillUserScriptDidFocus(_: AutofillUserScript,
                                                     mainType: AutofillUserScript.GetAutofillDataMainType,
                                                     completionHandler: @escaping (SecureVaultModels.CreditCard?, RequestVaultDataAction) -> Void) {
                // Never call the completion handler
                callCount += 1
                if callCount == 1 {
                    delegateCalledExpectation.fulfill()
                }
            }

            override func autofillUserScriptDidRequestCreditCard(_: AutofillUserScript,
                                                                 trigger: AutofillUserScript.GetTriggerType,
                                                                 completionHandler: @escaping (SecureVaultModels.CreditCard?, RequestVaultDataAction) -> Void) {
                // Never call the completion handler
                callCount += 1
                if callCount == 2 {
                    delegateCalledExpectation.fulfill()
                }
            }
        }

        let delegateCalledExpect = expectation(description: "Delegate methods called")
        delegateCalledExpect.expectedFulfillmentCount = 2

        let delegate = NeverCompletingDelegate(delegateCalledExpectation: delegateCalledExpect)
        userScript.vaultDelegate = delegate

        let expFocus = expectation(description: "focus field no-action")
        let expGet = expectation(description: "getData no-action")

        // Send focus message
        var focusBody = encryptedMessagingParams
        focusBody["mainType"] = "creditCards"

        userScript.userContentController(userContentController,
                                         didReceive: MockWKScriptMessage(name: "getAutofillDataFocus",
                                                                         body: focusBody,
                                                                         webView: MockWebView())
        ) { result, error in
            defer { expFocus.fulfill() }

            guard let json = result as? String, let data = json.data(using: .utf8) else {
                XCTFail("Expected JSON string response for focus")
                return
            }

            do {
                let resp = try JSONDecoder().decode(AutofillUserScript.NoActionResponse.self, from: data)
                XCTAssertEqual(resp.success.action, .none)
            } catch {
                XCTFail("Failed to decode NoActionResponse for focus: \(error)")
            }
        }

        // Send getData message
        var getDataBody = encryptedMessagingParams
        getDataBody["mainType"] = "creditCards"
        getDataBody["subType"] = "cardNumber"
        getDataBody["trigger"] = "userInitiated"

        userScript.userContentController(userContentController,
                                         didReceive: MockWKScriptMessage(name: "getAutofillData",
                                                                         body: getDataBody,
                                                                         webView: MockWebView())
        ) { result, error in
            defer { expGet.fulfill() }

            guard let json = result as? String, let data = json.data(using: .utf8) else {
                XCTFail("Expected JSON string response for getData")
                return
            }

            do {
                let resp = try JSONDecoder().decode(AutofillUserScript.NoActionResponse.self, from: data)
                XCTAssertEqual(resp.success.action, .none)
            } catch {
                XCTFail("Failed to decode NoActionResponse for getData: \(error)")
            }
        }

        wait(for: [delegateCalledExpect], timeout: 1.0)

        // Now cancel all pending replies
        userScript.cancelAllPendingReplies()

        wait(for: [expFocus, expGet], timeout: 1.0)
    }

    func testWhenInvalidMessageBodyForGetAutofillDataFocus_ThenNothingHappens() {
        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        // Send message with invalid body structure
        var body = encryptedMessagingParams
        body["invalidKey"] = "invalidValue" // Missing mainType

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "getAutofillDataFocus", body: body, webView: mockWebView)

        let expect = expectation(description: #function)
        expect.isInverted = true // We expect no callback

        userScript.userContentController(userContentController, didReceive: message) { _, _ in
            expect.fulfill() // This should not be called
        }

        waitForExpectations(timeout: 2)

        // Verify delegate was not called
        XCTAssertFalse(delegate.receivedCallbacks.contains(.didRequestCreditCard))
    }
}

class MockSecureVaultDelegate: AutofillSecureVaultDelegate {

    enum CallbackType {
        case didRequestCreditCardsManagerForDomain
        case didRequestIdentitiesManagerForDomain
        case didRequestPasswordManagerForDomain
        case didRequestStoreDataForDomain
        case didRequestAccountsForDomain
        case didRequestCredentialsForDomain
        case didRequestCreditCard
        case didRequestRuntimeConfigurationForDomain
        case didRequestAutoFillInitDataForDomain
    }

    var receivedCallbacks: [CallbackType] = []

    var lastDomain: String?
    var lastUsername: String?
    var lastPassword: String?
    var lastSubtype: AutofillUserScript.GetAutofillDataSubType?
    var autofillWebsiteAccountMatcher: AutofillWebsiteAccountMatcher?
    var tld: TLD?

    public func autofillUserScript(_: AutofillUserScript, didRequestCreditCardsManagerForDomain domain: String) {
        lastDomain = domain
        receivedCallbacks.append(.didRequestCreditCardsManagerForDomain)
    }

    public func autofillUserScript(_: AutofillUserScript, didRequestIdentitiesManagerForDomain domain: String) {
        lastDomain = domain
        receivedCallbacks.append(.didRequestIdentitiesManagerForDomain)
    }

    func autofillUserScript(_: AutofillUserScript, didRequestPasswordManagerForDomain domain: String) {
        lastDomain = domain
        receivedCallbacks.append(.didRequestPasswordManagerForDomain)
    }

    func autofillUserScript(_: AutofillUserScript, didRequestStoreDataForDomain domain: String, data: AutofillUserScript.DetectedAutofillData) {
        lastDomain = domain
        lastUsername = data.credentials?.username
        lastPassword = data.credentials?.password
        receivedCallbacks.append(.didRequestStoreDataForDomain)
    }

    var didRequestAccountsForDomainCompletionHandler: (([BrowserServicesKit.SecureVaultModels.WebsiteAccount], BrowserServicesKit.SecureVaultModels.CredentialsProvider) -> Void)?

    func autofillUserScript(_: BrowserServicesKit.AutofillUserScript,
                            didRequestAccountsForDomain domain: String,
                            completionHandler: @escaping ([BrowserServicesKit.SecureVaultModels.WebsiteAccount], BrowserServicesKit.SecureVaultModels.CredentialsProvider) -> Void) {
        lastDomain = domain
        didRequestAccountsForDomainCompletionHandler = completionHandler
        receivedCallbacks.append(.didRequestAccountsForDomain)
    }

    func autofillUserScript(_: BrowserServicesKit.AutofillUserScript,
                            didRequestCredentialsForAccount accountId: String,
                            completionHandler: @escaping (BrowserServicesKit.SecureVaultModels.WebsiteCredentials?, BrowserServicesKit.SecureVaultModels.CredentialsProvider) -> Void) {
    }

    func autofillUserScript(_: BrowserServicesKit.AutofillUserScript,
                            didRequestCredentialsForDomain domain: String,
                            completionHandler: @escaping ([BrowserServicesKit.SecureVaultModels.WebsiteCredentials], BrowserServicesKit.SecureVaultModels.CredentialsProvider) -> Void) {
    }

    func autofillUserScriptDidRequestCreditCard(_: BrowserServicesKit.AutofillUserScript, trigger: BrowserServicesKit.AutofillUserScript.GetTriggerType, completionHandler: @escaping (BrowserServicesKit.SecureVaultModels.CreditCard?, BrowserServicesKit.RequestVaultDataAction) -> Void) {
        receivedCallbacks.append(.didRequestCreditCard)
    }

    var didRequestAutoFillInitDataForDomainCompletionHandler: (([BrowserServicesKit.SecureVaultModels.WebsiteCredentials],
                                                                [BrowserServicesKit.SecureVaultModels.Identity],
                                                                [BrowserServicesKit.SecureVaultModels.CreditCard],
                                                                BrowserServicesKit.SecureVaultModels.CredentialsProvider,
                                                                SecureVaultLoginsCount) -> Void)?

    func autofillUserScript(_: BrowserServicesKit.AutofillUserScript,
                            didRequestAutoFillInitDataForDomain domain: String,
                            completionHandler: @escaping ([BrowserServicesKit.SecureVaultModels.WebsiteCredentials], [BrowserServicesKit.SecureVaultModels.Identity], [BrowserServicesKit.SecureVaultModels.CreditCard], BrowserServicesKit.SecureVaultModels.CredentialsProvider, SecureVaultLoginsCount) -> Void) {
        didRequestAutoFillInitDataForDomainCompletionHandler = completionHandler
    }

    func autofillUserScript(_: AutofillUserScript,
                            didRequestCreditCardWithId creditCardId: Int64,
                            completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
    }

    func autofillUserScript(_: AutofillUserScript,
                            didRequestIdentityWithId identityId: Int64,
                            completionHandler: @escaping (SecureVaultModels.Identity?) -> Void) {
    }

    func autofillUserScript(_: BrowserServicesKit.AutofillUserScript,
                            didRequestCredentialsForDomain: String,
                            subType: BrowserServicesKit.AutofillUserScript.GetAutofillDataSubType,
                            trigger: BrowserServicesKit.AutofillUserScript.GetTriggerType,
                            completionHandler: @escaping (BrowserServicesKit.SecureVaultModels.WebsiteCredentials?, BrowserServicesKit.SecureVaultModels.CredentialsProvider, BrowserServicesKit.RequestVaultDataAction) -> Void) {
        lastSubtype = subType
        receivedCallbacks.append(.didRequestCredentialsForDomain)
        let provider = SecureVaultModels.CredentialsProvider(name: .duckduckgo, locked: false)

        completionHandler(nil, provider, .none)
    }

    func autofillUserScriptDidAskToUnlockCredentialsProvider(_: BrowserServicesKit.AutofillUserScript, andProvideCredentialsForDomain domain: String, completionHandler: @escaping ([BrowserServicesKit.SecureVaultModels.WebsiteCredentials], [BrowserServicesKit.SecureVaultModels.Identity], [BrowserServicesKit.SecureVaultModels.CreditCard], BrowserServicesKit.SecureVaultModels.CredentialsProvider) -> Void) {

    }

    func autofillUserScript(_: BrowserServicesKit.AutofillUserScript, didRequestRuntimeConfigurationForDomain domain: String, completionHandler: @escaping (String?) -> Void) {
        lastDomain = domain
        receivedCallbacks.append(.didRequestRuntimeConfigurationForDomain)
    }

    func autofillUserScriptDidOfferGeneratedPassword(_: BrowserServicesKit.AutofillUserScript, password: String, completionHandler: @escaping (Bool) -> Void) {
    }

    func autofillUserScriptDidFocus(_: AutofillUserScript, mainType: AutofillUserScript.GetAutofillDataMainType, completionHandler: @escaping (SecureVaultModels.CreditCard?, RequestVaultDataAction) -> Void) {
    }

    func autofillUserScript(_: AutofillUserScript, didSendPixel pixel: AutofillUserScript.JSPixel) {
    }
}

struct NoneEncryptingEncrypter: UserScriptEncrypter {

    func encryptReply(_ reply: String, key: [UInt8], iv: [UInt8]) throws -> (ciphertext: Data, tag: Data) {
        return (reply.data(using: .utf8)!, Data())
    }

}

struct MockHostProvider: UserScriptHostProvider {

    let host: String

    func hostForMessage(_ message: UserScriptMessage) -> String {
        return host
    }
}
