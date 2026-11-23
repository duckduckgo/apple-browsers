//
//  ContentScopeScriptSourceTests.swift
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

import BrowserServicesKitTestsUtils
import ContentScopeScripts
import PrivacyConfig
import PrivacyConfigTestsUtils
import WebKit
import XCTest
@testable import BrowserServicesKit
@testable import UserScript

final class ContentScopeScriptSourceTests: XCTestCase {

    private static let contexts: [ContentScopeScriptContext] = [
        .contentScope(),
        .contentScopeIsolated,
        .brokerProtection,
        .aiChatDataClearing,
        .aiChatHistory
    ]

    private var properties: ContentScopeProperties!
    private var privacyConfigurationManager: MockPrivacyConfigurationManager!

    override func setUp() {
        super.setUp()
        properties = ContentScopeProperties(gpcEnabled: true,
                                            sessionKey: "session-key",
                                            messageSecret: "message-secret",
                                            isInternalUser: true,
                                            debug: false,
                                            featureToggles: .init(emailProtection: false, emailProtectionIncontextSignup: false, credentialsAutofill: false,
                                                                  identitiesAutofill: false, creditCardsAutofill: false, credentialsSaving: false,
                                                                  passwordGeneration: false, inlineIconCredentials: false, thirdPartyCredentialsProvider: false,
                                                                  unknownUsernameCategorization: false, partialFormSaves: false,
                                                                  passwordVariantCategorization: false, inputFocusApi: false, autocompleteAttributeSupport: false),
                                            currentCohorts: [ContentScopeExperimentData(feature: "parent", subfeature: "experiment", cohort: "treatment")])
        let privacyConfig = MockPrivacyConfiguration()
        privacyConfig.userUnprotectedDomains = ["unprotected.example"]
        privacyConfigurationManager = MockPrivacyConfigurationManager(privacyConfig: privacyConfig,
                                                                      internalUserDecider: DefaultInternalUserDecider(store: MockInternalUserStoring()))
        // Characters that need escaping in a string literal, including U+2028 and U+2029, and a placeholder-like string
        privacyConfigurationManager.currentConfigString = #"{"features":{"gpc":{"state":"enabled","settings":{"#
            + #""text":"line\#u{2028}paragraph\#u{2029}quote\"slash\\\\ duck 🦆 $USER_PREFERENCES$"}}},"unprotectedTemporary":[]}"#
    }

    override func tearDown() {
        properties = nil
        privacyConfigurationManager = nil
        super.tearDown()
    }

    // MARK: - Output

    /// Sources before the dead placeholders were removed also replaced `$CONTENT_SCOPE$` and `$WEBKIT_MESSAGING_CONFIG$`.
    /// No bundle contains them, so the output must not change.
    func testWhenSourceIsGeneratedThenItMatchesTheSourceWithTheRemovedPlaceholders() throws {
        for scriptContext in Self.contexts {
            let source = try ContentScopeScriptSource(privacyConfigurationManager: privacyConfigurationManager,
                                                      properties: properties,
                                                      scriptContext: scriptContext,
                                                      privacyConfigurationJSONGenerator: nil).source

            XCTAssertEqual(source, try referenceSource(for: scriptContext), "\(scriptContext.fileName)")
        }
    }

    func testBundlesUseOnlyThePlaceholdersThatAreFilledIn() throws {
        let placeholder = try NSRegularExpression(pattern: #"\$[A-Z][A-Z_]*\$"#)
        for scriptContext in Self.contexts {
            let bundle = try JSFileCache.content(forFile: scriptContext.fileName, in: ContentScopeScripts.Bundle)
            let found = Set(placeholder.matches(in: bundle, range: NSRange(bundle.startIndex..., in: bundle)).compactMap {
                Range($0.range, in: bundle).map { String(bundle[$0]) }
            })

            XCTAssertEqual(found, ["$CONTENT_SCOPE_JSON$", "$USER_UNPROTECTED_DOMAINS$", "$USER_PREFERENCES$"], "\(scriptContext.fileName)")
        }
    }

    func testWhenScriptIsMadeFromASharedSourceThenItsSourceMatchesAScriptWithItsOwnSource() throws {
        for scriptContext in Self.contexts {
            let shared = try ContentScopeScriptSource(privacyConfigurationManager: privacyConfigurationManager,
                                                      properties: properties,
                                                      scriptContext: scriptContext,
                                                      privacyConfigurationJSONGenerator: nil)
            let ownSource = try ContentScopeUserScript(privacyConfigurationManager,
                                                       properties: properties,
                                                       scriptContext: scriptContext,
                                                       privacyConfigurationJSONGenerator: nil)

            let script = ContentScopeUserScript(source: shared)

            XCTAssertEqual(script.source, ownSource.source)
            XCTAssertEqual(script.scriptContext, ownSource.scriptContext)
            XCTAssertEqual(script.messageNames, ownSource.messageNames)
            XCTAssertEqual(script.requiresRunInPageContentWorld, ownSource.requiresRunInPageContentWorld)
        }
    }

    func testWhenSourceIsMadeInTheBackgroundThenItMatchesTheSourceMadeInPlace() async throws {
        let inPlace = try ContentScopeScriptSource(privacyConfigurationManager: privacyConfigurationManager,
                                                   properties: properties,
                                                   scriptContext: .contentScopeIsolated,
                                                   privacyConfigurationJSONGenerator: nil)

        let background = try await ContentScopeScriptSource.make(privacyConfigurationManager: privacyConfigurationManager,
                                                                 properties: properties,
                                                                 scriptContext: .contentScopeIsolated,
                                                                 privacyConfigurationJSONGenerator: nil)

        XCTAssertEqual(background.source, inPlace.source)
    }

    // MARK: - Sharing

    @MainActor
    func testWhenScriptsShareASourceThenTheyShareOneWKUserScript() async throws {
        let source = try ContentScopeScriptSource(privacyConfigurationManager: privacyConfigurationManager,
                                                  properties: properties,
                                                  scriptContext: .contentScope(),
                                                  privacyConfigurationJSONGenerator: nil)
        let first = ContentScopeUserScript(source: source)
        let second = ContentScopeUserScript(source: source)

        // Tabs install scripts through `UserScriptsProvider.userScripts`, so go through the protocol as they do
        let firstWKUserScript = await (first as UserScript).makeWKUserScript().wkUserScript
        let secondWKUserScript = await (second as UserScript).makeWKUserScript().wkUserScript

        XCTAssertTrue(firstWKUserScript === secondWKUserScript)
        XCTAssertTrue(second.makeWKUserScriptSync() === firstWKUserScript)
        XCTAssertTrue((second as UserScript).makeWKUserScriptSync() === firstWKUserScript)
        XCTAssertTrue(first.broker !== second.broker, "Each tab keeps its own broker")
    }

    @MainActor
    func testWhenSharedScriptIsMadeThenItIsWrappedLikeAnyOtherUserScript() async throws {
        let source = try ContentScopeScriptSource(privacyConfigurationManager: privacyConfigurationManager,
                                                  properties: properties,
                                                  scriptContext: .contentScopeIsolated,
                                                  privacyConfigurationJSONGenerator: nil)
        source.prepareForInjection()

        let wkUserScript = ContentScopeUserScript(source: source).makeWKUserScriptSync()

        XCTAssertEqual(wkUserScript.source, UserScriptSourcePreparation.prepare(source.source))
        XCTAssertEqual(wkUserScript.injectionTime, .atDocumentStart)
        XCTAssertFalse(wkUserScript.isForMainFrameOnly)
    }

    @MainActor
    func testWhenOneWKUserScriptIsAddedToSeveralControllersThenRemovingItFromOneLeavesTheOthers() {
        let script = SharedWKUserScript(source: "window.sharedScriptRuns = (window.sharedScriptRuns || 0) + 1",
                                        injectionTime: .atDocumentStart,
                                        forMainFrameOnly: false,
                                        requiresRunInPageContentWorld: true)
        let first = WKUserContentController()
        let second = WKUserContentController()

        first.addUserScript(script.makeWKUserScriptSync())
        second.addUserScript(script.makeWKUserScriptSync())
        first.removeAllUserScripts()

        XCTAssertTrue(first.userScripts.isEmpty)
        XCTAssertEqual(second.userScripts.count, 1)
        XCTAssertTrue(second.userScripts.first === script.makeWKUserScriptSync())
    }

    @MainActor
    func testWhenOneWKUserScriptIsAddedToSeveralWebViewsThenItRunsInEach() async throws {
        let script = SharedWKUserScript(source: "window.sharedScriptRuns = (window.sharedScriptRuns || 0) + 1",
                                        injectionTime: .atDocumentStart,
                                        forMainFrameOnly: false,
                                        requiresRunInPageContentWorld: true)
        let webViews = (0..<2).map { _ in
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.addUserScript(script.makeWKUserScriptSync())
            return WKWebView(frame: .zero, configuration: configuration)
        }
        // Removing the script from one web view's controller doesn't affect the other's
        webViews[0].configuration.userContentController.removeAllUserScripts()

        var runs = [Int]()
        for webView in webViews {
            let navigation = NavigationWaiter()
            webView.navigationDelegate = navigation
            webView.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://example.com"))
            await navigation.waitForFinish()
            let value = try await webView.callAsyncJavaScript("return window.sharedScriptRuns || 0", arguments: [:], in: nil, contentWorld: .page)
            runs.append(try XCTUnwrap(value as? Int))
        }

        XCTAssertEqual(runs, [0, 1])
    }

    // MARK: - Helpers

    /// The source as generated before the dead placeholders were removed, with the same replacement pass.
    private func referenceSource(for scriptContext: ContentScopeScriptContext) throws -> String {
        let config = try XCTUnwrap(String(data: privacyConfigurationManager.currentConfig, encoding: .utf8))
        let literal = try ContentScopeUserScript.javaScriptStringLiteral(for: config)
        let messagingConfig = WebkitMessagingConfig(webkitMessageHandlerNames: [scriptContext.messagingContextName],
                                                    secret: UUID().uuidString,
                                                    hasModernWebkitAPI: true)
        let unprotectedDomains = scriptContext.appliesUserUnprotectedDomains ? privacyConfigurationManager.privacyConfig.userUnprotectedDomains : []
        return try ContentScopeUserScript.loadJS(scriptContext.fileName, from: ContentScopeScripts.Bundle, withReplacements: [
            "$CONTENT_SCOPE_JSON$": literal,
            "$CONTENT_SCOPE$": "JSON.parse(\(literal))",
            "$USER_UNPROTECTED_DOMAINS$": try XCTUnwrap(String(data: JSONEncoder().encode(unprotectedDomains), encoding: .utf8)),
            "$USER_PREFERENCES$": try ContentScopeUserScript.encodeProperties(properties, scriptContext: scriptContext),
            "$WEBKIT_MESSAGING_CONFIG$": try XCTUnwrap(String(data: JSONEncoder().encode(messagingConfig), encoding: .utf8))
        ])
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func waitForFinish() async {
        guard !finished else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished = true
        continuation?.resume()
        continuation = nil
    }
}
