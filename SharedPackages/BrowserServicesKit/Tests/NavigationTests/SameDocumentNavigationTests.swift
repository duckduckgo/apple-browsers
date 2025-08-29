//
//  SameDocumentNavigationTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED

import Combine
import Common
import Swifter
import WebKit
import XCTest
import os.log
@testable import Navigation

@available(macOS 12.0, iOS 15.0, *)
class SameDocumentNavigationTests: DistributedNavigationDelegateTestsBase {

    override func setUp() {
        super.setUp()

        setenv("OS_LOG_CAPTURE", "1", 1)
        setenv("OS_LOG_DEBUG", "1", 1)
    }

    func testGoBackWithSameDocumentNavigation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "#1")
        responder(at: 0).onDidFinish = { _ in
            Logger.general.info("expectation \(eDidFinish.description): didFinish")
            eDidFinish.fulfill()
        }
        responder(at: 0).onNavigationAction = { navigationAction, _ in .allow }

        // #1 load URL
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        // #2 load URL#namedlink1
        eDidFinish = expectation(description: "#2")
        responder(at: 0).onSameDocumentNavigation = { _, type in
            if type == .sessionStatePop {
                Logger.general.info("expectation \(eDidFinish.description): sessionStatePop")
                eDidFinish.fulfill()
            }
        }
        withWebView { webView in
            _=webView.load(req(urls.localHashed1))
        }
        waitForExpectations()

        // #3 load URL#namedlink2
        eDidFinish = expectation(description: "#3")
        withWebView { webView in
            webView.evaluateJavaScript("window.location.href = '\(urls.localHashed2.string)'")
        }
        waitForExpectations()

        // #4 load URL#namedlink3
        eDidFinish = expectation(description: "#4")
        withWebView { webView in
            webView.evaluateJavaScript("window.location.href = '\(urls.localHashed3.string)'")
        }
        waitForExpectations()

        // #4.1 go back to URL#namedlink2
        eDidFinish = expectation(description: "#4.1")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations()
        // #4.2 go back to URL#namedlink1
        eDidFinish = expectation(description: "#4.2")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations()
        // #4.3 go forward to URL#namedlink2
        eDidFinish = expectation(description: "#4.3")
        withWebView { webView in
            _=webView.goForward()
        }
        waitForExpectations()
        // #4.4 go forward to URL#namedlink3
        eDidFinish = expectation(description: "#4.4")
        withWebView { webView in
            _=webView.goForward()
        }
        waitForExpectations()

        // #5 load URL#
        eDidFinish = expectation(description: "#5")
        withWebView { webView in
            webView.evaluateJavaScript("window.location.href = '\(urls.localHashed.string)'")
        }
        waitForExpectations()

        // #6 load URL
        eDidFinish = expectation(description: "#6")
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        // #7 go back to URL#
        // !! here‘s the WebKit bug: no forward item will be present here
        eDidFinish = expectation(description: "#7")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations()

        // #8 go back to URL#namedlink
        eDidFinish = expectation(description: "#8")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1 load URL
            .navigationAction(/*#1*/req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

            // #2 load URL#namedlink1
            .willStart(Nav(action: NavAction(/*#2*/req(urls.localHashed1), .sameDocumentNavigation(.anchorNavigation), from: history[1], src: main(urls.local)), .approved, isCurrent: false)),
            .didSameDocumentNavigation(Nav(action: NavAction(/*#3*/req(urls.localHashed1, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[1], src: main(urls.localHashed1)), .finished, isCurrent: false), 3),
            .didSameDocumentNavigation(Nav(action: navAct(2), .finished), 0),

            // #3 load URL#namedlink2
            .willStart(Nav(action: NavAction(/*#4*/req(urls.localHashed2, defaultHeaders + ["Referer": urls.local.separatedString]), .sameDocumentNavigation(.anchorNavigation), from: history[3], .userInitiated, src: main(urls.localHashed1)), .approved, isCurrent: false)),
            .didSameDocumentNavigation(Nav(action: NavAction(/*#5*/req(urls.localHashed2, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[3], .userInitiated, src: main(urls.localHashed2)), .finished, isCurrent: false), 3),
            .didSameDocumentNavigation(Nav(action: navAct(4), .finished), 0),

            // #4 load URL#namedlink3
            .willStart(Nav(action: NavAction(/*#6*/req(urls.localHashed3, defaultHeaders + ["Referer": urls.local.separatedString]), .sameDocumentNavigation(.anchorNavigation), from: history[5], src: main(urls.localHashed2)), .approved, isCurrent: false)),
            .didSameDocumentNavigation(Nav(action: NavAction(/*#7*/req(urls.localHashed3, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[5], .userInitiated, src: main(urls.localHashed3)), .finished, isCurrent: false), 3),
            .didSameDocumentNavigation(Nav(action: navAct(6), .finished), 0),

            // #4.1 go back to URL#namedlink2
            .didSameDocumentNavigation(Nav(action: NavAction(/*#8*/req(urls.localHashed2, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[7], src: main(urls.localHashed2)), .finished), 3),
            .didSameDocumentNavigation(Nav(action: navAct(6), .finished, isCurrent: false), 0),

            // #4.2 go back to URL#namedlink1
            .didSameDocumentNavigation(Nav(action: NavAction(/*#9*/req(urls.localHashed1, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[5], src: main(urls.localHashed1)), .finished), 3),
            .didSameDocumentNavigation(Nav(action: navAct(6), .finished, isCurrent: false), 0),

            // #4.3 go forward to URL#namedlink2
            .didSameDocumentNavigation(Nav(action: NavAction(/*#10*/req(urls.localHashed2, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[3], src: main(urls.localHashed2)), .finished), 3),
            .didSameDocumentNavigation(Nav(action: navAct(6), .finished, isCurrent: false), 0),

            // #4.3 go forward to URL#namedlink3
            .didSameDocumentNavigation(Nav(action: NavAction(/*#11*/req(urls.localHashed3, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[5], src: main(urls.localHashed3)), .finished), 3),
            .didSameDocumentNavigation(Nav(action: navAct(6), .finished, isCurrent: false), 0),

            // goBack/goForward ignored for same doc decidePolicyForNavigationAction not called

            // #5 load URL#
            .willStart(Nav(action: NavAction(/*#12*/req(urls.localHashed, defaultHeaders + ["Referer": urls.local.separatedString]), .sameDocumentNavigation(.anchorNavigation), from: history[7], .userInitiated, src: main(urls.localHashed3)), .approved, isCurrent: false)),
            .didSameDocumentNavigation(Nav(action: NavAction(/*#13*/req(urls.localHashed, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[7], .userInitiated, src: main(urls.localHashed)), .finished, isCurrent: false), 3),
            .didSameDocumentNavigation(Nav(action: navAct(12), .finished), 0),

            // #6 load URL
            .navigationAction(NavAction(/*#14*/req(urls.local), .other, from: history[13], src: main(urls.localHashed))),
            .willStart(Nav(action: navAct(14), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(14), .started)),
            .response(Nav(action: navAct(14), .responseReceived, resp: resp(0))),
            .didCommit(Nav(action: navAct(14), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(14), .finished, resp: resp(0), .committed)),

            // #7 go back to URL#
            .willStart(Nav(action: NavAction(/*#15*/req(urls.localHashed, defaultHeaders.allowingExtraKeys), .backForw(-1), from: history[14], src: main(urls.local)), .approved, isCurrent: false)),
            .didSameDocumentNavigation(Nav(action: NavAction(/*#16*/req(urls.localHashed, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[14], src: main(urls.localHashed)), .finished), 3),
            .didSameDocumentNavigation(Nav(action: navAct(15), .finished, isCurrent: false), 0),

            // #8 go back to URL#namedlink
            .willStart(Nav(action: NavAction(req(urls.localHashed, defaultHeaders.allowingExtraKeys), .backForw(-1), from: history[16], src: main(urls.localHashed)), .approved, isCurrent: false)),
            .didSameDocumentNavigation(Nav(action: NavAction(req(urls.localHashed, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[16], src: main(urls.localHashed)), .finished), 3)
        ])
    }

    func testJSHistoryManipulation() throws {
        let customCallbacksHandler = CustomCallbacksHandler()
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })), .weak(customCallbacksHandler))

        server.middleware = [{ [data] request in
            XCTAssertEqual(request.path, "/")
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()
        responder(at: 0).clear()

        eDidFinish = expectation(description: "onDidFinish 2")

        var didPushStateCounter = 0
        let eDidSameDocumentNavigation = expectation(description: "onDidSameDocumentNavigation")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            didPushStateCounter += 1
            if didPushStateCounter == 4 {
                eDidSameDocumentNavigation.fulfill()
            }
        }

        // #1 push /1, /3, /2, go back
        withWebView { webView in
            webView.evaluateJavaScript("history.pushState({page: 1}, '1', '/1')", in: nil, in: WKContentWorld.page) { _ in
                webView.evaluateJavaScript("history.pushState({page: 3}, '3', '/3')", in: nil, in: WKContentWorld.page) { _ in
                    webView.evaluateJavaScript("history.pushState({page: 2}, '2', '/2')", in: nil, in: WKContentWorld.page) { _ in
                        webView.evaluateJavaScript("history.go(-1)", in: nil, in: WKContentWorld.page) { _ in
                            eDidFinish.fulfill()
                        }
                    }
                }
            }
        }
        waitForExpectations()

        // #2 navigate from pseudo `/3` to `/3#hashed`
        var eDidGoBack = expectation(description: "onDidGoToNamedLink")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            if type == .sessionStatePop { eDidGoBack.fulfill() }
        }
        withWebView { webView in
            _=webView.load(req(urls.local3Hashed))
        }
        waitForExpectations()

        // #3 go back
        eDidGoBack = expectation(description: "onDidGoBack")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations()

        // #4 go back
        eDidGoBack = expectation(description: "onDidGoBack 2")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1
            // push /1
            .didSameDocumentNavigation(Nav(action: NavAction(/*#2*/req(urls.local1, [:]), .sameDocumentNavigation(.sessionStatePush), from: history[1], .userInitiated, src: main(urls.local1)), .finished), 1),
            // push /3
            .didSameDocumentNavigation(Nav(action: NavAction(/*#3*/req(urls.local3, [:]), .sameDocumentNavigation(.sessionStatePush), from: history[2], .userInitiated, src: main(urls.local3)), .finished), 1),
            // push /2
            .didSameDocumentNavigation(Nav(action: NavAction(/*#4*/req(urls.local2, [:]), .sameDocumentNavigation(.sessionStatePush), from: history[3], .userInitiated, src: main(urls.local2)), .finished), 1),
            // go back to /3
            .didSameDocumentNavigation(Nav(action: NavAction(/*#5*/req(urls.local3, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[4], .userInitiated, src: main(urls.local3)), .finished), 3),

            // #2 navigate from pseudo `/3` to `/3#hashed`
            .willStart(Nav(action: NavAction(/*#6*/req(urls.local3Hashed), .sameDocumentNavigation(.anchorNavigation), from: history[3], src: main(urls.local3)), .approved, isCurrent: false)),
            .didSameDocumentNavigation(Nav(action: NavAction(/*#7*/req(urls.local3Hashed, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[3], src: main(urls.local3Hashed)), .finished, isCurrent: false), 3),
            .didSameDocumentNavigation(Nav(action: navAct(6), .finished), 0),

            // #3 go back
            .didSameDocumentNavigation(Nav(action: NavAction(/*#8*/req(urls.local3, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[7], src: main(urls.local3)), .finished), 3),
            .didSameDocumentNavigation(Nav(action: navAct(6), .finished, isCurrent: false), 0),

            // #4 go back
            .didSameDocumentNavigation(Nav(action: NavAction(/*#9*/req(urls.local1, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[3], src: main(urls.local1)), .finished), 3)
        ])
    }

    func testSameDocumentNavigations() throws {
        let customCallbacksHandler = CustomCallbacksHandler()
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })), .weak(customCallbacksHandler))

        server.middleware = [{ [data] request in
            XCTAssertEqual(request.path, "/")
            return .ok(.html(data.sameDocumentTestData.utf8String()!))
        }]
        try server.start(8084)

        // 1. Load the Initial Page
        var eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()
        responder(at: 0).clear()

        // 2. Anchor Navigation (#target)
        var expectedNavigationTypes = [WKSameDocumentNavigationType]()
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            let idx = expectedNavigationTypes.firstIndex(of: type)
            XCTAssertNotNil(idx, type.debugDescription)
            _=idx.map { expectedNavigationTypes.remove(at: $0) }
            if expectedNavigationTypes.isEmpty {
                eDidFinish.fulfill()
            }
        }
        eDidFinish = expectation(description: "Anchor navigation")
        expectedNavigationTypes = [.sessionStatePop, .anchorNavigation]
        withWebView { webView in
            webView.evaluateJavaScript("performNavigation('anchorNavigation')")
        }
        waitForExpectations()

        // 2. Session State Push (#target2)
        eDidFinish = expectation(description: "Session State Push")
        expectedNavigationTypes = [.sessionStatePush]
        withWebView { webView in
            webView.evaluateJavaScript("performNavigation('sessionStatePush')")
        }
        waitForExpectations()

        // 3. Session State Replace (#target3)
        eDidFinish = expectation(description: "Session State Replace")
        expectedNavigationTypes = [.sessionStateReplace]
        withWebView { webView in
            webView.evaluateJavaScript("performNavigation('sessionStateReplace')")
        }
        waitForExpectations()

        // 4. Session State Pop (#target)
        eDidFinish = expectation(description: "Session State Pop")
        expectedNavigationTypes = [.sessionStatePop, .anchorNavigation]
        withWebView { webView in
            webView.evaluateJavaScript("performNavigation('sessionStatePop')")
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            // 2. Anchor Navigation (#target)
            .willStart(Nav(action: /*#2*/NavAction(req(urls.localTarget, defaultHeaders + ["Referer": urls.local.separatedString]), .sameDocumentNavigation(.anchorNavigation), from: history[1], .userInitiated, src: main(urls.local)), .approved, isCurrent: false)),
            .didSameDocumentNavigation(Nav(action: /*#3*/NavAction(req(urls.localTarget, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[1], .userInitiated, src: main(urls.localTarget)), .finished, isCurrent: false), 3),
            .didSameDocumentNavigation(Nav(action: navAct(2), .finished), 0),

            // 2. Session State Push (#target2)
            .didSameDocumentNavigation(Nav(action: /*#4*/NavAction(req(urls.localTarget2, [:]), .sameDocumentNavigation(.sessionStatePush), from: history[3], .userInitiated, src: main(urls.localTarget2)), .finished), 1),

            // 3. Session State Replace (#target3)
            .didSameDocumentNavigation(Nav(action: /*#5*/NavAction(req(urls.localTarget3, [:]), .sameDocumentNavigation(.sessionStateReplace), from: history[4], .userInitiated, src: main(urls.localTarget3)), .finished), 2),

            // 4. Session State Pop (#target)
            .didSameDocumentNavigation(Nav(action: /*#6*/NavAction(req(urls.localTarget, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[4], .userInitiated, src: main(urls.localTarget)), .finished), 3),
            .didSameDocumentNavigation(Nav(action: navAct(2), .finished, isCurrent: false), 0)
        ])
    }

    func testClientRedirectToSameDocument() throws {
        let customCallbacksHandler = CustomCallbacksHandler()
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })), .weak(customCallbacksHandler))

        server.middleware = [{ [data] request in
            return .ok(.html(data.sameDocumentClientRedirectData.utf8String()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "#1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        responder(at: 0).onNavigationAction = { navigationAction, _ in .allow }

        let eDidSameDocumentNavigation = expectation(description: "#2")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            if type == .sessionStatePop { eDidSameDocumentNavigation.fulfill() }
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        if case .didCommit = responder(at: 0).history[5] {
            responder(at: 0).history.insert(responder(at: 0).history[5], at: 4)
        }
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.sameDocumentClientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .didReceiveRedirect(NavAction(req(urls.localHashed1, defaultHeaders + ["Referer": urls.local.separatedString]), .sameDocumentNavigation(.anchorNavigation), from: history[1], src: main(urls.local)), Nav(action: navAct(1), .redirected(.client), resp: resp(0), .committed)),
            .willStart(Nav(action: NavAction(req(urls.localHashed1, defaultHeaders + ["Referer": urls.local.separatedString]), .sameDocumentNavigation(.anchorNavigation), from: history[1], src: main(urls.local)), .approved, isCurrent: false)),

            .didSameDocumentNavigation(Nav(action: NavAction(req(urls.localHashed1, [:]), .sameDocumentNavigation(.sessionStatePop), from: history[1], src: main(urls.localHashed1)), .finished, isCurrent: false), 3),
            .didSameDocumentNavigation(Nav(action: navAct(2), .finished), 0),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, isCurrent: false)),
        ])
    }

    func testClientRedirectUsingSessionStatePush() throws {
        let customCallbacksHandler = CustomCallbacksHandler()
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })), .weak(customCallbacksHandler))

        server.middleware = [{ [data] request in
            return .ok(.html(data.sessionStatePushClientRedirectData.utf8String()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "#1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        responder(at: 0).onNavigationAction = { navigationAction, _ in .allow }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        if case .didCommit = responder(at: 0).history[5] {
            responder(at: 0).history.insert(responder(at: 0).history[5], at: 4)
        }
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.sessionStatePushClientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .didSameDocumentNavigation(Nav(action: NavAction(req(urls.localHashed1, [:]), .sameDocumentNavigation(.sessionStatePush), from: history[1], src: main(urls.localHashed1)), .finished, isCurrent: false), 1),

            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, isCurrent: true)),
        ])
    }

}

#endif
