//
//  PasskeyConditionalAbortUserScriptTests.swift
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

import PrivacyConfig
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class PasskeyConditionalAbortUserScriptTests: XCTestCase {

    /// Replaces the native `get`/`create` before the script under test wraps them. Records each call in
    /// `window.__calls` (with the returned promise); pending calls reject with `AbortError` when their signal aborts,
    /// unless the request sets `publicKey.ignoreAbort`. `publicKey.throwSync` makes the call throw synchronously. `priorConditionalAborted` records whether every earlier conditional
    /// request was already aborted when a modal request arrived. The test page isn't a secure context, so the
    /// stub also provides `CredentialsContainer` and `navigator.credentials` when WebKit doesn't expose them.
    private static let stubSource = """
        if (typeof CredentialsContainer === "undefined") {
            window.CredentialsContainer = class CredentialsContainer {};
        }
        if (!navigator.credentials) {
            Object.defineProperty(navigator, "credentials", { value: Object.create(CredentialsContainer.prototype), configurable: true });
        }
        window.__calls = [];
        const record = (kind, options) => {
            const call = { kind, options, signal: options && options.signal };
            if (kind !== "conditional") {
                call.priorConditionalAborted = window.__calls.filter((c) => c.kind === "conditional").every((c) => c.signal.aborted);
            }
            window.__calls.push(call);
            if (options && options.publicKey && options.publicKey.throwSync) { throw new Error("sync"); }
            call.promise = new Promise((resolve, reject) => {
                call.resolve = resolve;
                const signal = call.signal;
                if (!(signal instanceof AbortSignal) || (options.publicKey && options.publicKey.ignoreAbort)) { return; }
                const abort = () => reject(new DOMException("aborted", "AbortError"));
                if (signal.aborted) { abort(); } else { signal.addEventListener("abort", abort); }
            });
            return call.promise;
        };
        CredentialsContainer.prototype.get = function (options) {
            return record(options && options.mediation === "conditional" ? "conditional" : "modal", options);
        };
        CredentialsContainer.prototype.create = function (options) {
            return record("create", options);
        };
        """

    private var webView: WKWebView!

    override func tearDown() async throws {
        webView = nil
        try await super.tearDown()
    }

    // MARK: - Feature flag and setup

    func testWhenFlagIsOn_ThenScriptIsCreated() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.passkeyConditionalRequestGuard]

        XCTAssertNotNil(PasskeyConditionalAbortUserScript.make(featureFlagger: featureFlagger))
    }

    func testWhenFlagIsOff_ThenScriptIsNotCreated() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = []

        XCTAssertNil(PasskeyConditionalAbortUserScript.make(featureFlagger: featureFlagger))
    }

    func testThatScriptRunsAtDocumentStartInAllFramesInPageWorld() {
        let script = PasskeyConditionalAbortUserScript()

        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.forMainFrameOnly)
        XCTAssertTrue(script.requiresRunInPageContentWorld)
        XCTAssertTrue(script.messageNames.isEmpty)
    }

    // MARK: - Navigation

    func testWhenPageHides_ThenPendingConditionalRequestIsAborted() async throws {
        let aborted = try await run("""
            navigator.credentials.get({ mediation: "conditional", publicKey: {} }).catch(() => {});
            window.dispatchEvent(new Event("pagehide"));
            return window.__calls[0].signal.aborted;
            """)

        XCTAssertEqual(aborted as? Bool, true)
    }

    func testWhenPageIsHidden_ThenNewConditionalRequestIsRejectedWithoutReachingWebKit() async throws {
        let result = try await run("""
            window.dispatchEvent(new Event("pagehide"));
            const error = await navigator.credentials.get({ mediation: "conditional", publicKey: {} }).catch((error) => error);
            return [error.name, window.__calls.length];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? String, "AbortError")
        XCTAssertEqual(result?[1] as? Int, 0)
    }

    func testWhenPageIsShownAgain_ThenConditionalRequestsWork() async throws {
        let calls = try await run("""
            window.dispatchEvent(new Event("pagehide"));
            window.dispatchEvent(new Event("pageshow"));
            navigator.credentials.get({ mediation: "conditional", publicKey: {} }).catch(() => {});
            return window.__calls.length;
            """)

        XCTAssertEqual(calls as? Int, 1)
    }

    // MARK: - Overlap

    func testWhenModalGetStarts_ThenItWaitsForPendingConditionalRequestToBeAborted() async throws {
        let result = try await run("""
            navigator.credentials.get({ mediation: "conditional", publicKey: {} }).catch(() => {});
            navigator.credentials.get({ publicKey: {} });
            const callsBeforeWait = window.__calls.length;
            await new Promise((resolve) => setTimeout(resolve, 100));
            const modal = window.__calls[1];
            return [callsBeforeWait, modal.kind, modal.priorConditionalAborted];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? Int, 1)
        XCTAssertEqual(result?[1] as? String, "modal")
        XCTAssertEqual(result?[2] as? Bool, true)
    }

    func testWhenCreateStarts_ThenItWaitsForPendingConditionalRequestToBeAborted() async throws {
        let result = try await run("""
            navigator.credentials.get({ mediation: "conditional", publicKey: {} }).catch(() => {});
            navigator.credentials.create({ publicKey: {} });
            await new Promise((resolve) => setTimeout(resolve, 100));
            const create = window.__calls[1];
            return [create.kind, create.priorConditionalAborted];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? String, "create")
        XCTAssertEqual(result?[1] as? Bool, true)
    }

    func testWhenSecondConditionalRequestStarts_ThenItIsRejectedWithoutReachingWebKit() async throws {
        let result = try await run("""
            navigator.credentials.get({ mediation: "conditional", publicKey: {} }).catch(() => {});
            const error = await navigator.credentials.get({ mediation: "conditional", publicKey: {} }).catch((error) => error);
            return [window.__calls.length, window.__calls[0].signal.aborted, error.name];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? Int, 1)
        XCTAssertEqual(result?[1] as? Bool, false)
        XCTAssertEqual(result?[2] as? String, "NotAllowedError")
    }

    func testWhenPageRestartsConditionalRequestDuringModalRequest_ThenItIsHeldUntilModalRequestSettles() async throws {
        let result = try await run("""
            const restart = () => navigator.credentials.get({ mediation: "conditional", publicKey: {} }).catch(() => {});
            navigator.credentials.get({ mediation: "conditional", publicKey: {} }).catch(restart);
            navigator.credentials.get({ publicKey: {} });
            await new Promise((resolve) => setTimeout(resolve, 100));
            const kindsWhileModalPending = window.__calls.map((call) => call.kind);
            window.__calls[1].resolve(null);
            await new Promise((resolve) => setTimeout(resolve, 100));
            return [kindsWhileModalPending, window.__calls.map((call) => call.kind)];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? [String], ["conditional", "modal"])
        XCTAssertEqual(result?[1] as? [String], ["conditional", "modal", "conditional"])
    }

    func testWhenConditionalRequestIgnoresAbort_ThenModalRequestProceedsAfterOneSecondAndLaterOnesDontWait() async throws {
        let result = try await run("""
            navigator.credentials.get({ mediation: "conditional", publicKey: { ignoreAbort: true } });
            const start = Date.now();
            navigator.credentials.get({ publicKey: {} });
            while (window.__calls.length < 2) { await new Promise((resolve) => setTimeout(resolve, 20)); }
            const firstWait = Date.now() - start;
            navigator.credentials.get({ publicKey: {} });
            return [firstWait, window.__calls.length];
            """) as? [Int]

        XCTAssertGreaterThanOrEqual(result?[0] ?? 0, 900)
        XCTAssertEqual(result?[1], 3)
    }

    // MARK: - Correctness

    func testWhenPageAbortsConditionalRequest_ThenAbortIsForwardedWithReason() async throws {
        let result = try await run("""
            const controller = new AbortController();
            const request = navigator.credentials.get({ mediation: "conditional", signal: controller.signal, publicKey: {} });
            controller.abort("page reason");
            const error = await request.catch((error) => error);
            return [window.__calls[0].signal.aborted, window.__calls[0].signal.reason, error.name, window.__calls[0].signal !== controller.signal];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? Bool, true)
        XCTAssertEqual(result?[1] as? String, "page reason")
        XCTAssertEqual(result?[2] as? String, "AbortError")
        XCTAssertEqual(result?[3] as? Bool, true)
    }

    func testWhenPageAbortsAndRestartsRepeatedly_ThenRequestsAreNotTreatedAsReplacements() async throws {
        let result = try await run("""
            const errors = [];
            for (let i = 0; i < 3; i++) {
                const controller = new AbortController();
                navigator.credentials.get({ mediation: "conditional", signal: controller.signal, publicKey: {} })
                    .catch((error) => errors.push(error.name));
                await new Promise((resolve) => setTimeout(resolve, 50));
                controller.abort();
            }
            await new Promise((resolve) => setTimeout(resolve, 100));
            return [window.__calls.length, errors];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? Int, 3)
        XCTAssertEqual(result?[1] as? [String], ["AbortError", "AbortError", "AbortError"])
    }

    func testWhenSignalIsAlreadyAborted_ThenPendingConditionalRequestIsLeftAlone() async throws {
        let result = try await run("""
            navigator.credentials.get({ mediation: "conditional", publicKey: {} }).catch(() => {});
            const options = { mediation: "conditional", signal: AbortSignal.abort(), publicKey: {} };
            await navigator.credentials.get(options).catch(() => {});
            return [window.__calls[0].signal.aborted, window.__calls[1].options === options];
            """) as? [Bool]

        XCTAssertEqual(result, [false, true])
    }

    func testWhenRequestHasNoPublicKey_ThenItIsPassedThroughUnchanged() async throws {
        let result = try await run("""
            const options = { password: true, mediation: "conditional" };
            navigator.credentials.get(options);
            return window.__calls[0].options === options;
            """)

        XCTAssertEqual(result as? Bool, true)
    }

    func testWhenPageStartsNewRequestBeforeAbortingOldOne_ThenRequestsAreNotTreatedAsReplacements() async throws {
        let result = try await run("""
            const errors = [];
            let previous = null;
            for (let i = 0; i < 3; i++) {
                const controller = new AbortController();
                navigator.credentials.get({ mediation: "conditional", signal: controller.signal, publicKey: {} })
                    .catch((error) => errors.push(error.name));
                if (previous) { previous.abort(); }
                previous = controller;
                await new Promise((resolve) => setTimeout(resolve, 50));
            }
            await new Promise((resolve) => setTimeout(resolve, 100));
            return [window.__calls.length, errors];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? Int, 3)
        XCTAssertEqual(result?[1] as? [String], ["AbortError", "AbortError"])
    }

    func testWhenPageAbortsHeldRequest_ThenItRejectsImmediately() async throws {
        let result = try await run("""
            navigator.credentials.get({ publicKey: {} });
            const controller = new AbortController();
            const held = navigator.credentials.get({ mediation: "conditional", signal: controller.signal, publicKey: {} });
            controller.abort("page reason");
            const outcome = await Promise.race([held.catch((error) => error), new Promise((resolve) => setTimeout(() => resolve("still held"), 100))]);
            return [outcome, window.__calls.length];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? String, "page reason")
        XCTAssertEqual(result?[1] as? Int, 1)
    }

    func testWhenNoWaitIsNeeded_ThenWebKitPromiseIsReturned() async throws {
        let result = try await run("""
            const conditional = navigator.credentials.get({ mediation: "conditional", publicKey: {} });
            const conditionalIsNative = conditional === window.__calls[0].promise;
            conditional.catch(() => {});
            window.dispatchEvent(new Event("pagehide"));
            window.dispatchEvent(new Event("pageshow"));
            const create = navigator.credentials.create({ publicKey: {} });
            return [conditionalIsNative, create === window.__calls[1].promise];
            """) as? [Bool]

        XCTAssertEqual(result, [true, true])
    }

    func testWhenWebKitThrowsSynchronously_ThenPromiseIsRejected() async throws {
        let result = try await run("""
            const request = navigator.credentials.get({ mediation: "conditional", publicKey: { throwSync: true } });
            const error = await request.catch((error) => error);
            return [request instanceof Promise, error.message];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? Bool, true)
        XCTAssertEqual(result?[1] as? String, "sync")
    }

    func testWhenSignalIsNotAnAbortSignal_ThenRequestIsPassedThroughUnchanged() async throws {
        let result = try await run("""
            const options = { mediation: "conditional", signal: {}, publicKey: {} };
            navigator.credentials.get(options);
            return window.__calls[0].options === options;
            """)

        XCTAssertEqual(result as? Bool, true)
    }

    func testWhenOptionsAreInherited_ThenWebKitStillSeesThem() async throws {
        let result = try await run("""
            const options = Object.create({ mediation: "conditional", publicKey: { rpId: "example.com" } });
            navigator.credentials.get(options).catch(() => {});
            const received = window.__calls[0].options;
            return [window.__calls[0].kind, received.publicKey.rpId, received.signal instanceof AbortSignal];
            """) as? [Any]

        XCTAssertEqual(result?[0] as? String, "conditional")
        XCTAssertEqual(result?[1] as? String, "example.com")
        XCTAssertEqual(result?[2] as? Bool, true)
    }

    func testWhenConditionalRequestSettles_ThenPageAbortListenerIsRemoved() async throws {
        let result = try await run("""
            const controller = new AbortController();
            let listeners = 0;
            const add = controller.signal.addEventListener.bind(controller.signal);
            const remove = controller.signal.removeEventListener.bind(controller.signal);
            controller.signal.addEventListener = (...args) => { listeners++; add(...args); };
            controller.signal.removeEventListener = (...args) => { listeners--; remove(...args); };
            const request = navigator.credentials.get({ mediation: "conditional", signal: controller.signal, publicKey: {} });
            const listenersWhilePending = listeners;
            window.__calls[0].resolve(null);
            await request;
            return [listenersWhilePending, listeners];
            """) as? [Int]

        XCTAssertEqual(result, [1, 0])
    }

    // MARK: - Helpers

    private func run(_ functionBody: String) async throws -> Any? {
        if webView == nil {
            try await loadPage()
        }
        return try await webView.callAsyncJavaScript(functionBody, contentWorld: .page)
    }

    private func loadPage() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: Self.stubSource,
                                                                       injectionTime: .atDocumentStart,
                                                                       forMainFrameOnly: false,
                                                                       in: .page))
        configuration.userContentController.addUserScript(PasskeyConditionalAbortUserScript().makeWKUserScriptSync())
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://example.com/")!)
        for _ in 0..<100 {
            let state = try await webView.callAsyncJavaScript("return location.href + ' ' + document.readyState;", contentWorld: .page) as? String
            if state == "https://example.com/ complete" {
                self.webView = webView
                let stub = try await webView.callAsyncJavaScript("return typeof window.__calls;", contentWorld: .page) as? String
                XCTAssertEqual(stub, "object", "Stub didn't install")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Page didn't load")
    }
}
