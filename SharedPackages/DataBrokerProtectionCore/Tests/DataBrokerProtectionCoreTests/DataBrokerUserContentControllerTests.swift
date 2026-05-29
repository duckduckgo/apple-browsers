//
//  DataBrokerUserContentControllerTests.swift
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

import BrowserServicesKit
import Common
import PrivacyConfig
import TrackerRadarKit
import WebKit
import XCTest

@testable import DataBrokerProtectionCore
@testable import DataBrokerProtectionCoreTestsUtils

@MainActor
final class DataBrokerUserContentControllerTests: XCTestCase {

    private var ruleList: WKContentRuleList!

    override func setUp() async throws {
        try await super.setUp()
        // Install the WKUserContentController rule-list swizzle so installedContentRuleLists
        // mirrors the real WebKit-side state. Idempotent — safe to read on every setUp.
        _ = WKUserContentController.swizzleContentRuleListsMethodsOnce
        // Compile a minimal rule list so we can install a real WKContentRuleList in tests.
        ruleList = try await Self.compileMinimalRuleList(identifier: "DBPUCCTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let ruleList {
            try? await WKContentRuleListStore.default()?.removeContentRuleList(forIdentifier: ruleList.identifier)
        }
        ruleList = nil
        try await super.tearDown()
    }

    // MARK: - contentBlocking == nil

    func testWhenContentBlockingIsNil_thenOnlyIsolatedScriptIsInstalledAndNoRuleLists() async throws {
        let sut = try makeSUT(contentBlocking: nil)

        XCTAssertTrue(sut.installedContentRuleLists.isEmpty)
        XCTAssertEqual(sut.dataBrokerUserScripts?.userScripts.count, 1)
        XCTAssertNil(sut.dataBrokerUserScripts?.contentScopeUserScriptForTrackerProtection)
    }

    // MARK: - contentBlocking != nil

    func testWhenContentBlockingIsProvided_thenInstallsRuleListsAndAddsNonIsolatedScript() async throws {
        let mock = DBPWebViewContentBlockingMock(contentRuleLists: [ruleList])
        let sut = try makeSUT(contentBlocking: mock)

        XCTAssertEqual(sut.installedContentRuleLists.count, 1)
        XCTAssertEqual(sut.installedContentRuleLists.first?.identifier, ruleList.identifier)
        XCTAssertEqual(sut.dataBrokerUserScripts?.userScripts.count, 2)
        XCTAssertNotNil(sut.dataBrokerUserScripts?.contentScopeUserScriptForTrackerProtection)
    }

    // MARK: - cleanup

    func testWhenCleanUpBeforeClosingCalled_thenRuleListsAndScriptsAreCleared() async throws {
        let mock = DBPWebViewContentBlockingMock(contentRuleLists: [ruleList])
        let sut = try makeSUT(contentBlocking: mock)
        XCTAssertEqual(sut.installedContentRuleLists.count, 1)

        sut.cleanUpBeforeClosing()

        XCTAssertTrue(sut.installedContentRuleLists.isEmpty)
        XCTAssertNil(sut.dataBrokerUserScripts)
    }

    // MARK: - Helpers

    private func makeSUT(contentBlocking: DBPWebViewContentBlocking?) throws -> DataBrokerUserContentController {
        let privacyConfigManager = PrivacyConfigurationManagingMock()
        let prefs = ContentScopeProperties(
            gpcEnabled: false,
            sessionKey: UUID().uuidString,
            messageSecret: UUID().uuidString,
            featureToggles: ContentScopeFeatureToggles(
                emailProtection: false,
                emailProtectionIncontextSignup: false,
                credentialsAutofill: false,
                identitiesAutofill: false,
                creditCardsAutofill: false,
                credentialsSaving: false,
                passwordGeneration: false,
                inlineIconCredentials: false,
                thirdPartyCredentialsProvider: false,
                unknownUsernameCategorization: false,
                partialFormSaves: false,
                passwordVariantCategorization: false,
                inputFocusApi: false,
                autocompleteAttributeSupport: false
            )
        )
        return try DataBrokerUserContentController(
            with: privacyConfigManager,
            prefs: prefs,
            delegate: CCFCommunicationDelegateMock(),
            executionConfig: BrokerJobExecutionConfig(),
            shouldContinueActionHandler: { true },
            contentBlocking: contentBlocking
        )
    }

    private static func compileMinimalRuleList(identifier: String) async throws -> WKContentRuleList {
        let json = """
        [{"trigger":{"url-filter":".*","resource-type":["image"]},"action":{"type":"ignore-previous-rules"}}]
        """
        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default()?.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "test", code: -1))
                }
            }
        }
    }
}

// MARK: - Test doubles

private final class CCFCommunicationDelegateMock: CCFCommunicationDelegate {
    func loadURL(url: URL) async {}
    func extractedProfiles(profiles: [ExtractedProfile], meta: [String: Any]?) async {}
    func captchaInformation(captchaInfo: GetCaptchaInfoResponse) async {}
    func solveCaptcha(with response: SolveCaptchaResponse) async {}
    func success(actionId: String, actionType: ActionType) async {}
    func conditionSuccess(actions: [Action]) async {}
    func onError(error: Error) async {}
}
