//
//  NavigationAuthChallengeTests.swift
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
class NavigationAuthChallengeTests: DistributedNavigationDelegateTestsBase {

    func testWhenAuthenticationChallengeReceived_responderChainReceivesEvents() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in })
        )

        // 1st: .next
        let eOnAuthChallenge1 = expectation(description: "OnAuthChallenge 1 1")
        responder(at: 0).onDidReceiveAuthenticationChallenge = { _, _ in
            eOnAuthChallenge1.fulfill()
            return .next
        }
        // 2nd: .credential
        let eOnAuthChallenge2 = expectation(description: "OnAuthChallenge 2")
        responder(at: 1).onDidReceiveAuthenticationChallenge = { _, _ in
            eOnAuthChallenge2.fulfill()
            return .credential(URLCredential(user: "t", password: "t", persistence: .none))
        }
        // 3rd: not called
        responder(at: 2).onDidReceiveAuthenticationChallenge = { _, _ in XCTFail("Unexpected didReceiveAuthChallenge"); return .cancel }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }, { [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .started, nil, .gotAuth)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, .gotAuth)),
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, .gotAuth)),
        ])
    }

    func testWhenMultiAuthenticationChallengesReceived_responderChainReceivesEvents() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in })
        )

        responder(at: 0).onDidReceiveAuthenticationChallenge = { _, _ in .next }
        responder(at: 1).onDidReceiveAuthenticationChallenge = { challenge, _ in
            return .credential(URLCredential(user: "t", password: "t", persistence: .none))
        }
        responder(at: 2).onDidReceiveAuthenticationChallenge = { _, _ in .next }

        var frameID: UInt64!
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
#if _FRAME_HANDLE_ENABLED
            if navAction.url.path == urls.local3.path {
                frameID = navAction.targetFrame?.handle.frameID
                XCTAssertNotEqual(frameID, WKFrameInfo.defaultMainFrameHandle)
            }
#endif
            return .next
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            guard request.path == "/3" else { return nil }
            guard request.headers["authorization"] == nil else { return .ok(.data(data.html)) }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }, { [data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }, { [data] request in
            return .ok(.data(data.htmlWithIframe3))
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .started, nil, .gotAuth)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWithIframe3.count), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed, .gotAuth)),
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(main(responderIdx: 0).handle.frameID, urls.local), targ: frame(frameID, .empty, secOrigin: urls.local.securityOrigin)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed, .gotAuth)),
            .response(.resp(urls.local3, data.html.count, nil, .nonMain), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed, .gotAuth)),

            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, .gotAuth))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWithIframe3.count), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed, .gotAuth)),
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(main(responderIdx: 0).handle.frameID, urls.local), targ: frame(frameID, .empty, secOrigin: urls.local.securityOrigin)),
            .response(.resp(urls.local3, data.html.count, nil, .nonMain), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, .gotAuth)),
        ])
    }

    func testWhenAuthenticationChallengeReturnsNext_responderChainReceivesEvents() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in })
        )

        let eOnAuthChallenge3 = expectation(description: "OnAuthChallenge 1 1")
        responder(at: 0).onDidReceiveAuthenticationChallenge = { _, _ in .next }
        responder(at: 1).onDidReceiveAuthenticationChallenge = { _, _ in .next }
        responder(at: 2).onDidReceiveAuthenticationChallenge = { _, _ in
            eOnAuthChallenge3.fulfill()
            return .next
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .started, nil, .gotAuth)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, .gotAuth)),
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 1, equalsToHistoryOfResponderAt: 2)
    }

    func testWhenAuthenticationChallengeReturnsCancel_responderChainReceivesFailure() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in })
        )

        responder(at: 0).onDidReceiveAuthenticationChallenge = { _, _ in .next }
        responder(at: 1).onDidReceiveAuthenticationChallenge = { _, _ in .cancel }
        responder(at: 2).onDidReceiveAuthenticationChallenge = { _, _ in XCTFail("Unexpected onDidReceiveAuthenticationChallenge"); return .next }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFail = { _, _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .started, nil, .gotAuth)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled)), nil, .gotAuth), NSURLErrorCancelled)
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled)), nil, .gotAuth), NSURLErrorCancelled),
        ])
    }

    func testWhenAuthenticationChallengeRejected_responderChainReceivesEvents() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in })
        )

        responder(at: 0).onDidReceiveAuthenticationChallenge = { _, _ in .next }
        responder(at: 1).onDidReceiveAuthenticationChallenge = { _, _ in .rejectProtectionSpace }
        responder(at: 2).onDidReceiveAuthenticationChallenge = { _, _ in XCTFail("Unexpected onDidReceiveAuthenticationChallenge"); return .next }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .started, nil, .gotAuth)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, .gotAuth))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, .gotAuth)),
        ])
    }

}

#endif
