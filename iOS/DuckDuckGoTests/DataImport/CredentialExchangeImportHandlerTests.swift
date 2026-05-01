//
//  CredentialExchangeImportHandlerTests.swift
//  DuckDuckGoTests
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

import XCTest
import AuthenticationServices
@testable import BrowserServicesKit
import Common
import SecureStorage
@testable import DuckDuckGo

@available(iOS 26.0, *)
final class CredentialExchangeImportHandlerTests: XCTestCase {

    func testWhenParsingApplePasswordsPayloadThenCustomTitleMultipleURLsAndPortAreMappedCorrectly() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "",
                    items: [
                        makeItem(
                            title: "Custom title",
                            scopeURLs: ["https://fill.dev"],
                            username: "testCustomTitle",
                            password: "tyqvej-muszoW-0jowco"
                        ),
                        makeItem(
                            title: "fill.dev",
                            scopeURLs: ["https://fill.dev"],
                            username: "test",
                            password: "xenqo1-kizhEm-womquc"
                        ),
                        makeItem(
                            title: "localhost:8000",
                            scopeURLs: [],
                            username: "dax@duck.com",
                            password: "hapcI9-dipvax-zitgib"
                        ),
                        makeItem(
                            title: "nytimes.com",
                            scopeURLs: ["https://myaccount.nytimes.com", "https://nytimes.com"],
                            username: "dax@duck.com",
                            password: "Xyzzoh-vufhap-2hokhy"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(
            importedCredentials,
            [
                ImportedLoginCredential(
                    title: "Custom title",
                    url: "fill.dev",
                    username: "testCustomTitle",
                    password: "tyqvej-muszoW-0jowco"
                ),
                ImportedLoginCredential(
                    url: "fill.dev",
                    username: "test",
                    password: "xenqo1-kizhEm-womquc"
                ),
                ImportedLoginCredential(
                    url: "localhost:8000",
                    username: "dax@duck.com",
                    password: "hapcI9-dipvax-zitgib"
                ),
                ImportedLoginCredential(
                    url: "nytimes.com",
                    username: "dax@duck.com",
                    password: "Xyzzoh-vufhap-2hokhy"
                )
            ]
        )
    }

    func testWhenTwoEquivalentCredentialsExistThenParserKeepsBothForImporterDeduplication() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "",
                    items: [
                        makeItem(
                            title: "example.com",
                            scopeURLs: ["https://example.com"],
                            username: "duplicate-user",
                            password: "duplicate-pass"
                        ),
                        makeItem(
                            title: "example.com",
                            scopeURLs: ["https://example.com"],
                            username: "duplicate-user",
                            password: "duplicate-pass"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(
            importedCredentials,
            [
                ImportedLoginCredential(
                    url: "example.com",
                    username: "duplicate-user",
                    password: "duplicate-pass"
                ),
                ImportedLoginCredential(
                    url: "example.com",
                    username: "duplicate-user",
                    password: "duplicate-pass"
                )
            ]
        )
    }

    func testWhenUsernameFieldIsBlankThenAccountEmailIsUsedAsFallbackUsername() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "fallback@duck.com",
                    items: [
                        makeItem(
                            title: "Custom title",
                            subtitle: "portal.example.com",
                            scopeURLs: nil,
                            username: "   ",
                            password: "account-fallback-password"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(
            importedCredentials,
            [
                ImportedLoginCredential(
                    title: "Custom title",
                    url: "portal.example.com",
                    username: "fallback@duck.com",
                    password: "account-fallback-password"
                )
            ]
        )
    }

    func testWhenScopeContainsWWWAndOtherSubdomainsThenWWWDomainIsPreferred() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "",
                    items: [
                        makeItem(
                            title: "Portal login",
                            scopeURLs: ["https://m.example.com", "https://www.example.com", "https://account.example.com"],
                            username: "duck-user",
                            password: "duck-password"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(importedCredentials.count, 1)
        XCTAssertEqual(importedCredentials.first?.url, "www.example.com")
    }

    func testWhenScopeContainsOnlySubdomainsThenShortestHostIsPreferred() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "",
                    items: [
                        makeItem(
                            title: "Account login",
                            scopeURLs: ["https://a.b.example.com", "https://sub.example.com", "https://x.sub.example.com"],
                            username: "duck-user",
                            password: "duck-password"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(importedCredentials.count, 1)
        XCTAssertEqual(importedCredentials.first?.url, "sub.example.com")
    }

    func testWhenScopeContainsEqualDepthSubdomainsThenAlphabeticallyFirstHostIsPreferred() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "",
                    items: [
                        makeItem(
                            title: "Account login",
                            scopeURLs: ["https://b.example.com", "https://a.example.com"],
                            username: "duck-user",
                            password: "duck-password"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(importedCredentials.count, 1)
        XCTAssertEqual(importedCredentials.first?.url, "a.example.com")
    }

    func testWhenScopeAndSubtitleAreMissingAndTitleIsURLThenTitleHostIsUsedAsDomain() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "",
                    items: [
                        makeItem(
                            title: "https://account.duck.com/login",
                            scopeURLs: nil,
                            username: "duck-user",
                            password: "duck-password"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(importedCredentials.count, 1)
        XCTAssertEqual(importedCredentials.first?.url, "account.duck.com")
    }

    func testWhenScopeAndSubtitleAreMissingAndTitleIsNotDomainThenDomainIsEmptyString() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "",
                    items: [
                        makeItem(
                            title: "My important account",
                            scopeURLs: nil,
                            username: "duck-user",
                            password: "duck-password"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(importedCredentials.count, 1)
        XCTAssertEqual(importedCredentials.first?.url, "")
    }

    func testWhenCredentialIsNotBasicAuthenticationOrHasNoPasswordThenCredentialIsSkipped() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "",
                    items: [
                        makeItem(
                            title: "Ignored credential types",
                            scopeURLs: ["https://valid.example.com"],
                            credentials: [
                                makeNoteCredential(content: "ignored-note"),
                                makeBasicAuthenticationCredential(username: "missing-password", password: nil),
                                makeBasicAuthenticationCredential(username: "kept-user", password: "kept-password")
                            ]
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(importedCredentials.count, 1)
        XCTAssertEqual(importedCredentials.first?.url, "valid.example.com")
        XCTAssertEqual(importedCredentials.first?.username, "kept-user")
        XCTAssertEqual(importedCredentials.first?.password, "kept-password")
    }

    func testWhenCredentialUsernameIsBlankThenAccountUsernameIsPreferredOverEmail() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "account-username",
                    email: "account-email@duck.com",
                    items: [
                        makeItem(
                            title: "Account fallback",
                            subtitle: "fallback.example.com",
                            scopeURLs: nil,
                            username: "  ",
                            password: "fallback-password"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(importedCredentials.count, 1)
        XCTAssertEqual(importedCredentials.first?.username, "account-username")
    }

    func testWhenCredentialAndAccountUsernamesAndEmailAreBlankThenUsernameDefaultsToEmptyString() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: " ",
                    email: "\n",
                    items: [
                        makeItem(
                            title: "No username sources",
                            subtitle: "nouser.example.com",
                            scopeURLs: nil,
                            username: nil,
                            password: "fallback-password"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(importedCredentials.count, 1)
        XCTAssertEqual(importedCredentials.first?.username, "")
    }

    func testWhenTitleMatchesSelectedDomainExactlyThenTitleIsDropped() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "",
                    items: [
                        makeItem(
                            title: "localhost",
                            subtitle: "localhost",
                            scopeURLs: nil,
                            username: "duck-user",
                            password: "duck-password"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(importedCredentials.count, 1)
        XCTAssertNil(importedCredentials.first?.title)
        XCTAssertEqual(importedCredentials.first?.url, "localhost")
    }

    func testWhenTitleMatchesParentHostOfSelectedDomainThenTitleIsDropped() {
        let sut = makeSUT()
        let credentialData = makeCredentialData(
            accounts: [
                makeAccount(
                    userName: "",
                    email: "",
                    items: [
                        makeItem(
                            title: "localhost",
                            subtitle: "api.localhost",
                            scopeURLs: nil,
                            username: "duck-user",
                            password: "duck-password"
                        )
                    ]
                )
            ]
        )

        let importedCredentials = sut.importedLoginCredentials(from: credentialData)

        XCTAssertEqual(importedCredentials.count, 1)
        XCTAssertNil(importedCredentials.first?.title)
        XCTAssertEqual(importedCredentials.first?.url, "api.localhost")
    }
}

@available(iOS 26.0, *)
private extension CredentialExchangeImportHandlerTests {

    func makeSUT() -> CredentialExchangeImportHandler {
        CredentialExchangeImportHandler(
            loginImporter: MockLoginImporter(),
            reporter: MockSecureVaultReporting(),
            tld: TLD()
        )
    }

    func makeCredentialData(accounts: [ASImportableAccount]) -> ASExportedCredentialData {
        ASExportedCredentialData(
            accounts: accounts,
            formatVersion: .v1,
            exporterRelyingPartyIdentifier: "apple.com",
            exporterDisplayName: "Apple Passwords",
            timestamp: Date(timeIntervalSince1970: 1_776_542_457)
        )
    }

    func makeAccount(userName: String, email: String, items: [ASImportableItem]) -> ASImportableAccount {
        ASImportableAccount(
            id: makeIdentifier(),
            userName: userName,
            email: email,
            fullName: nil,
            collections: [],
            items: items
        )
    }

    func makeItem(title: String,
                  subtitle: String? = nil,
                  scopeURLs: [String]?,
                  username: String?,
                  password: String) -> ASImportableItem {
        makeItem(
            title: title,
            subtitle: subtitle,
            scopeURLs: scopeURLs,
            credentials: [makeBasicAuthenticationCredential(username: username, password: password)]
        )
    }

    func makeItem(title: String,
                  subtitle: String? = nil,
                  scopeURLs: [String]?,
                  credentials: [ASImportableCredential]) -> ASImportableItem {
        ASImportableItem(
            id: makeIdentifier(),
            created: Date(timeIntervalSince1970: 1_776_542_400),
            lastModified: Date(timeIntervalSince1970: 1_776_542_400),
            title: title,
            subtitle: subtitle,
            favorite: false,
            scope: makeScope(scopeURLs),
            credentials: credentials,
            tags: []
        )
    }

    func makeBasicAuthenticationCredential(username: String?, password: String?) -> ASImportableCredential {
        .basicAuthentication(
            .init(
                userName: username.map { makeStringField(value: $0) },
                password: password.map { makePasswordField(value: $0) }
            )
        )
    }

    func makeNoteCredential(content: String) -> ASImportableCredential {
        .note(
            .init(
                content: makeStringField(value: content)
            )
        )
    }

    func makeScope(_ scopeURLs: [String]?) -> ASImportableCredentialScope? {
        guard let scopeURLs else {
            return nil
        }

        return ASImportableCredentialScope(
            urls: scopeURLs.map(makeURL),
            androidApps: []
        )
    }

    func makeURL(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            fatalError("Invalid URL in test data: \(value)")
        }
        return url
    }

    func makeStringField(value: String) -> ASImportableEditableField {
        ASImportableEditableField(
            id: makeIdentifier(),
            fieldType: .string,
            value: value
        )
    }

    func makePasswordField(value: String) -> ASImportableEditableField {
        ASImportableEditableField(
            id: makeIdentifier(),
            fieldType: .concealedString,
            value: value
        )
    }

    func makeIdentifier() -> Data {
        Data(UUID().uuidString.utf8)
    }
}
