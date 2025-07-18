//
//  NavigationSessionRestorationTests.swift
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

#if os(macOS)

import Combine
import Common
import Swifter
import WebKit
import XCTest
@testable import Navigation

@available(macOS 12.0, iOS 15.0, *)
class NavigationSessionRestorationTests: DistributedNavigationDelegateTestsBase {

    func testWhenSessionIsRestored_navigationTypeIsSessionRestoration() throws {

        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        try server.start(8084)
        withWebView { webView in
            webView.interactionState = data.interactionStateData
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, status: 404, mime: "text/plain", headers: ["Server": "Swifter Unspecified"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
        ])
    }

    func testCustomSchemeURLSessionRestoration() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        try server.start(8084)
        withWebView { webView in
            webView.interactionState = data.customSchemeInteractionStateData
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .willStart(Nav(action: .init(req(urls.aboutBlank, [:], cachePolicy: .returnCacheDataElseLoad), .restore, src: main()), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didCommit(Nav(action: navAct(1), .started, .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),
        ])
    }

    func testGoBackAfterSessionRestoration() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        withWebView { webView in
            webView.interactionState = data.interactionStateData
        }
        waitForExpectations(timeout: 5)

        let eDidFinish2 = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish2.fulfill() }
        responder(at: 0).clear()
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: history[1], src: main(urls.local)),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(1), .committed)),
        ])
    }

    func testGoForwardAfterSessionRestoration() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        var sessionState = data.interactionStateData.plist
        sessionState["SessionHistory", as: [String: Any].self]!["SessionHistoryCurrentIndex"] = 0
        withWebView { webView in
            webView.interactionState = Data.sessionRestorationMagic + sessionState.plist
        }
        waitForExpectations(timeout: 5)

        let eDidFinish2 = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish2.fulfill() }

        withWebView { webView in
            _=webView.goForward()
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .backForw(1), from: history[1], src: main(urls.local1)),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(1), .committed)),
        ])
    }

    func testGoBackAfterSessionRestorationCacheFailure() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }

        // restore before server startup to raise cache failure
        withWebView { webView in
            webView.interactionState = data.interactionStateData
        }
        waitForExpectations(timeout: 5)

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)

        eDidFinish = expectation(description: "onDidFinish 2")
        withWebView { webView in
            _=webView.goForward()
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(-1004))), -1004),

            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: history[1], src: main()),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(0), .committed)),

            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .backForw(1), from: history[2], src: main(urls.local1)),
            .willStart(Nav(action: navAct(3), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(3), .started)),
            .response(Nav(action: navAct(3), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(3), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(3), .finished, resp: resp(1), .committed)),
        ])
    }

    func testGoForwardAfterSessionRestorationCacheFailure() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }

        // restore before server startup to raise cache failure
        var sessionState = data.interactionStateData.plist
        sessionState["SessionHistory", as: [String: Any].self]!["SessionHistoryCurrentIndex"] = 0

        withWebView { webView in
            webView.interactionState = sessionState.interactionStateData
        }
        waitForExpectations(timeout: 5)

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            _=webView.goForward()
        }
        waitForExpectations(timeout: 5)

        eDidFinish = expectation(description: "onDidFinish 2")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(-1004))), -1004),

            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .backForw(1), from: history[1], src: main()),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(0), .committed)),

            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: history[2], src: main(urls.local)),
            .willStart(Nav(action: navAct(3), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(3), .started)),
            .response(Nav(action: navAct(3), .responseReceived, resp: .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(3), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(3), .finished, resp: resp(1), .committed)),
        ])
    }

    func testWhenAboutBlankSessionIsRestored_navigationTypeIsSessionRestoration() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            webView.interactionState = data.aboutBlankAfterRegularNavigationInteractionStateData
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .willStart(Nav(action: .init(req(urls.aboutBlank, [:], cachePolicy: .returnCacheDataElseLoad), .restore, src: main()), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didCommit(Nav(action: navAct(1), .started, .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),
        ])
    }

}

#endif
