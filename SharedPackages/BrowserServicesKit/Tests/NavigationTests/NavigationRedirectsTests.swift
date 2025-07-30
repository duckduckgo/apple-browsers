//
//  NavigationRedirectsTests.swift
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

#if os(macOS)

import Combine
import Common
import Swifter
import WebKit
import XCTest
@testable import Navigation

@available(macOS 12.0, iOS 15.0, *)
class NavigationRedirectsTests: DistributedNavigationDelegateTestsBase {

    func testClientRedirectFromHashedUrlToNonHashedUrl() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var counter = 0
        server.middleware = [{ [data] request in
            counter += 1
            if counter == 1 {
                return .ok(.html(data.clientRedirectData.utf8String()!))
            } else {
                return .ok(.html(data.html.utf8String()!))
            }
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "#1")
        let eDidFinish2 = expectation(description: "#2")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }
        responder(at: 0).onNavigationAction = { navigationAction, _ in .allow }

        withWebView { webView in
            _=webView.load(req(urls.local3Hashed))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local3Hashed), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local3Hashed, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local3.string]), .redirect(.client), from: history[1], redirects: [navAct(1)], src: main(urls.local3Hashed))),
            .didReceiveRedirect(navAct(2), Nav(action: navAct(1), .redirected(.client), resp: resp(0), .committed, isCurrent: false)),

            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed))
        ])
    }

    func testServerRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .raw(301, "Moved", ["Location": urls.local3.path]) { writer in
                    try! writer.write(data.empty)
                }
            case urls.local3.path:
                return .ok(.data(data.html))
            default:
                return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders.allowingExtraKeys), .redirect(.server), redirects: [navAct(1)], src: main()),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

            .navigationAction(req(urls.local3, defaultHeaders.allowingExtraKeys), .redirect(.server), redirects: [navAct(1), navAct(2)], src: main()),
            .didReceiveRedirect(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

            .response(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: .resp(urls.local3, status: 200, data.html.count))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .finished, resp: resp(0), .committed))
        ])
    }

    func testServerRedirectToSameDocument() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var counter = 0
        server.middleware = [{ [urls, data] request in
            counter += 1
            switch counter {
            case 1:
                return .ok(.data(data.html))
            case 2:
                return .raw(301, "Moved", ["Location": urls.localHashed.absoluteString]) { writer in
                    try! writer.write(data.empty)
                }
            default:
                return .ok(.data(data.html))
            }

        }]
        try server.start(8084)

        // first load local URL
        var eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)
        responder(at: 0).clear()

        // reload redirecting to localURL#navlink
        eDidFinish = expectation(description: "onDidFinish2")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.local, cachePolicy: .reloadRevalidatingCacheData))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local, cachePolicy: .reloadIgnoringLocalCacheData), .other, from: history[1], src: main(urls.local))),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),

            .navigationAction(NavAction(req(urls.localHashed, defaultHeaders.allowingExtraKeys, cachePolicy: .reloadIgnoringLocalCacheData), .redirect(.server), from: history[1], redirects: [navAct(2)], src: main(urls.local))),
            .didReceiveRedirect(Nav(action: navAct(3), redirects: [navAct(2)], .started)),
            .response(Nav(action: navAct(3), redirects: [navAct(2)], .responseReceived, resp: .resp(urls.localHashed, data.html.count))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(2)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(2)], .finished, resp: resp(1), .committed)),
        ])
    }

    func testRefreshHeaderRedirectWithDelay() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var eDidFinish = expectation(description: "onDidFinish")
        let eDidFinish2 = expectation(description: "onDidFinish2")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.html))
            default:
                return .raw(200, "OK", ["refresh": "1; url=" + urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, mime: "text/plain", headers: ["Refresh": "1; url=/2", "Server": "Swifter Unspecified"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client(delay: 1.0)), from: history[1], redirects: [navAct(1)], src: main(urls.local))),
            .didReceiveRedirect(navAct(2), Nav(action: navAct(1), .redirected(.client(delay: 1)), resp: resp(0), .committed, isCurrent: false)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed))
        ])
    }

    func testMetaRedirectAfterServerRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.metaRedirect))
            case urls.local3.path:
                return .raw(301, "Moved", ["Location": urls.local4.path]) { writer in
                    try! writer.write(data.empty)
                }
            case urls.local4.path:
                return .ok(.data(data.html))
            default:
                return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders.allowingExtraKeys), .redirect(.server), redirects: [navAct(1)], src: main()),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(0), .committed)),
            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2))),
            .didReceiveRedirect(navAct(3), Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(0), .committed, isCurrent: false)),

            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(0), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

            .navigationAction(req(urls.local4, defaultHeaders.allowingExtraKeys + ["Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),

            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, resp: resp(1), .committed))
        ])
    }

    func testClientRedirectAfterMetaRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        var counter = 0
        responder(at: 0).onDidFinish = { _ in
            counter += 1
            guard counter == 4 else { return }
            eDidFinish.fulfill()
        }

        var clientRedirectMade = false
        server.middleware = [{ [urls, data] request in
            switch request.path {
            case "/":
                return .ok(.data(data.metaRedirect))
            case urls.local3.path:
                defer { clientRedirectMade = true }
                return .ok(.data(clientRedirectMade ? data.clientRedirectData2 : data.clientRedirectData))
            default:
                return .ok(.data(data.html))
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client), from: history[1], redirects: [navAct(1)], src: main(urls.local))),
            .didReceiveRedirect(navAct(2), Nav(action: navAct(1), .redirected(.client), resp: resp(0), .committed, isCurrent: false)),

                .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local3, data.clientRedirectData.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),
            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local3.string]), .redirect(.client), from: history[1], redirects: [navAct(1), navAct(2)], src: main(urls.local3))),
            .didReceiveRedirect(navAct(3), Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(1), .committed, isCurrent: false)),

            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),
            .response(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: resp(1))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: resp(1), .committed)),
            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local3.string]), .redirect(.client), from: history[1], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local3))),
            .didReceiveRedirect(navAct(4), Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .redirected(.client), resp: resp(1), .committed, isCurrent: false)),

            .didFinish(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .finished, resp: resp(1), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),
            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: resp(3), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, resp: resp(3), .committed))
        ])
    }

    func testMetaRedirectAfterServerRedirectWithDidFinishReceivedBeforeWillStartNavigationAction() throws {
        navigationDelegateProxy.finishEventsDispatchTime = .beforeWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.metaRedirect))
            case urls.local3.path:
                return .raw(301, "Moved", ["Location": urls.local4.path]) { writer in
                    try! writer.write(data.empty)
                }
            case urls.local4.path:
                return .ok(.data(data.html))
            default:
                return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders.allowingExtraKeys), .redirect(.server), redirects: [navAct(1)], src: main()),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(0), .committed)),
            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2))),
            .didReceiveRedirect(navAct(3), Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(0), .committed, isCurrent: false)),

            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(0), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

            .navigationAction(req(urls.local4, defaultHeaders.allowingExtraKeys + ["Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),

            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, resp: resp(1), .committed))
        ])
    }

    func testMetaRedirectAfterServerRedirectWithDidFinishReceivedAfterWillStartNavigationAction() throws {
        navigationDelegateProxy.finishEventsDispatchTime = .afterWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.metaRedirect))
            case urls.local3.path:
                return .raw(301, "Moved", ["Location": urls.local4.path]) { writer in
                    try! writer.write(data.empty)
                }
            case urls.local4.path:
                return .ok(.data(data.html))
            default:
                return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders.allowingExtraKeys), .redirect(.server), redirects: [navAct(1)], src: main()),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(0), .committed)),
            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2))),
            .didReceiveRedirect(navAct(3), Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(0), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .approved, isCurrent: false)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(0), .committed, isCurrent: false)),

            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

            .navigationAction(req(urls.local4, defaultHeaders.allowingExtraKeys + ["Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),

            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, resp: resp(1), .committed))
        ])
    }

    func testClientRedirect() throws {
        navigationDelegateProxy.finishEventsDispatchTime = .beforeWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var counter = 0
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            counter += 1
            guard counter == 3 else { return }
            eDidFinish.fulfill()
        }

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.clientRedirectData.utf8String()!))
        }, { [urls, data] request in
            guard request.path == urls.local3.path else { return nil }
            return .ok(.html(data.clientRedirectData2.utf8String()!))
        }, { [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client), from: history[1], redirects: [navAct(1)], src: main(urls.local))),
            .didReceiveRedirect(navAct(2), Nav(action: navAct(1), .redirected(.client), resp: resp(0), .committed, isCurrent: false)),

            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local3, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),
            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local3.string]), .redirect(.client), from: history[1], redirects: [navAct(1), navAct(2)], src: main(urls.local3))),
            .didReceiveRedirect(navAct(3), Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(1), .committed, isCurrent: false)),

            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),
            .response(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: resp(2), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .finished, resp: resp(2), .committed))
        ])
    }

    func testClientRedirectWithDelay() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.delayedMetaRedirect.utf8String()!))
        }, { [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.metaRedirect.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client(delay: 1.0)), from: history[1], redirects: [navAct(1)], src: main(urls.local))),
            .didReceiveRedirect(navAct(2), Nav(action: navAct(1), .redirected(.client(delay: 1)), resp: resp(0), .committed, isCurrent: false)),

            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local3, data.html.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed))
        ])
    }

    func testClientRedirectWithoutWillPerformClientRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.enableWillPerformClientRedirect = false

        let eDidFinish1 = expectation(description: "onDidFinish")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.clientRedirectData.utf8String()!))
        }, { [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: main(urls.local)),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local3, data.html.count))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(1), .committed))
        ])
    }

    func testMetaRedirectAfterServerRedirectWithDidFinishReceivedAfterDidStartNavigationAction() throws {
        navigationDelegateProxy.finishEventsDispatchTime = .afterDidStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.metaRedirect))
            case urls.local3.path:
                return .raw(301, "Moved", ["Location": urls.local4.path]) { writer in
                    try! writer.write(data.empty)
                }
            case urls.local4.path:
                return .ok(.data(data.html))
            default:
                return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders.allowingExtraKeys), .redirect(.server), redirects: [navAct(1)], src: main()),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(0), .committed)),
            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2))),
            .didReceiveRedirect(navAct(3), Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(0), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(0), .committed, isCurrent: false)),

            .navigationAction(req(urls.local4, defaultHeaders.allowingExtraKeys + ["Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),
            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, resp: resp(1), .committed))
        ])
    }

    func testSameURLServerRedirects() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "eDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        var counter = 0
        server.middleware = [{ [urls, data] request in
            guard counter < 10 else {
                return .ok(.data(data.html))
            }
            counter += 1
            return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                try! writer.write(data.empty)
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        var expected: [TestsNavigationEvent] =  [

            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .navigationAction(req(urls.local2, defaultHeaders.allowingExtraKeys), .redirect(.server), redirects: [navAct(1)], src: main()),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            // .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1), navAct(2)...], .started)),

            .response(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 9), .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 9), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 9), .finished, resp: resp(0), .committed))

        ]
        while expected[expected.count - 4].redirectEvent!.redirects.count < 10 {
            expected.insert(.didReceiveRedirect(Nav(action: navAct(2),
                                                    redirects: [navAct(1)]
                                                    + .init(repeating: navAct(2), count: expected[expected.count - 4].redirectEvent!.redirects.count),
                                                    .started)), at: expected.count - 3)
        }

        assertHistory(ofResponderAt: 0, equalsTo: expected)
    }

    func testSameURLServerRedirectsFailing() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in
            eDidFail.fulfill()
        }

        var counter = 0
        server.middleware = [{ [urls, data] request in
            guard counter < 100 else {
                return .ok(.data(data.html))
            }
            counter += 1
            return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                try! writer.write(data.empty)
            }
        }]
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        var expected: [TestsNavigationEvent] =  [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders.allowingExtraKeys), .redirect(.server), redirects: [navAct(1)], src: main()),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            // ...didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1), navAct(2)...], .started)

            .didFail(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 19), .failed(WKError(NSURLErrorHTTPTooManyRedirects))), NSURLErrorHTTPTooManyRedirects)
        ]
        while expected[expected.count - 2].redirectEvent!.redirects.count < 20 {
            expected.insert(.didReceiveRedirect(Nav(action: navAct(2),
                                                    redirects: [navAct(1)]
                                                    + .init(repeating: navAct(2), count: expected[expected.count - 2].redirectEvent!.redirects.count),
                                                    .started)), at: expected.count - 1)
        }

        assertHistory(ofResponderAt: 0, equalsTo: expected)
    }

    func testDeveloperRedirectToSimulatedRequest() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        responder(at: 0).onNavigationAction = { [urls, data] action, _ in
            if action.url.matches(urls.local) {
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!, withExpectedNavigationType: .custom(.init(rawValue: "redir")))
                }
            } else {
                XCTAssertEqual(action.navigationType, .custom(.init(rawValue: "redir")))
                return .allow
            }
        }

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]

        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        XCTAssertFalse(navAct(1).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local), .other, src: main())),
            .didCancel(navAct(1), expected: 1),

            .navigationAction(NavAction(req(urls.https), .custom(.init(rawValue: "redir")), src: main())),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .started, .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, .committed))
        ])
    }

    func testDeveloperRedirectToAboutBlank() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        responder(at: 0).onNavigationAction = { [urls] action, _ in
            if action.url.matches(urls.local) {
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.load(req(urls.aboutBlank))
                }
            } else {
                XCTAssertEqual(action.navigationType, .custom(.init(rawValue: "redir")))
                return .allow
            }
        }

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]

        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        XCTAssertFalse(navAct(1).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local), .other, src: main())),
            .didCancel(navAct(1), expected: 1),

            .willStart(Nav(action: NavAction(req(urls.aboutBlank), .redirect(.developer), src: main()), redirects: [navAct(1)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .started, .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, .committed))
        ])
    }

    func testDeveloperRedirectCancellation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in
            eDidFail.fulfill()
        }

        responder(at: 0).onNavigationAction = { [urls] action, _ in
            if action.url.matches(urls.local) {
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.load(req(urls.local2))
                }
            } else {
                XCTAssertEqual(action.navigationType, .redirect(.developer))
                return .allow
            }
        }
        responder(at: 0).onNavigationResponse = { [urls] response in
            if response.url.matches(urls.local2) {
                return .cancel
            }
            return .allow
        }

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]

        try server.start(8084)

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        XCTAssertFalse(navAct(1).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local), .other, src: main())),
            .didCancel(navAct(1), expected: 1),

            .navigationAction(NavAction(req(urls.local2), .redirect(.developer), src: main())),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didFail(Nav(action: navAct(2), redirects: [navAct(1)], .failed(WKError(.frameLoadInterruptedByPolicyChange)), resp: resp(0)), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
    }

    func testDeveloperRedirectSequence() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        responder(at: 0).onNavigationAction = { [urls] action, _ in
            if action.url.matches(urls.local) {
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.load(req(urls.local2))
                    webView.load(req(urls.local3))
                }
            } else {
                return .allow
            }
        }

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]

        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        // sometimes NavigationAction #2 Task is cancelled and doesn‘t get get to responder
        responder(at: 0).history.removeAll(where: {
            if case .navigationAction(let navAction, _, _) = $0 {
                return navAction.navigationAction.identifier == 2
            } else if case .willStart(let nav, _) = $0 {
                return nav.navigationAction.navigationAction.identifier == 2
            } else if case .didFail(let nav, _, _) = $0 {
                return nav.navigationAction.navigationAction.identifier == 2
            }
            return false
        })
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local), .other, src: main())),
            .didCancel(navAct(1), expected: 2),

            // .navigationAction(NavAction(req(urls.local2), .redirect(.developer), src: main())),
            // .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .approved, isCurrent: false)),
            // .didFail(Nav(action: NavAction(req(urls.local2), .redirect(.developer), src: main()), redirects: [navAct(1)], .failed(WKError(NSURLErrorCancelled)), isCurrent: false), NSURLErrorCancelled),

            .navigationAction(NavAction(req(urls.local3), .redirect(.developer), src: main())),
            .willStart(Nav(action: navAct(3), redirects: [navAct(1)], .approved, isCurrent: false)),

            .didStart(Nav(action: navAct(3), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(3), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local3, data.html.count))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(1)], .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(1)], .finished, resp: resp(0), .committed))
        ])
    }

    func testWhenServerRedirectIsInterruptedThenDidFailProvisionalIsCalled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [urls, data] request in
            guard request.path == "/" else { return nil }

            return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                try! writer.write(data.empty)
            }
        }, { [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        responder(at: 0).onNavigationAction = { [urls] action, _ in
            if action.url.matches(urls.local2) {
                return .cancel
            }
            return .allow
        }
        let eOnDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in
            eOnDidFail.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders.allowingExtraKeys), .redirect(.server), redirects: [navAct(1)], src: main()),

            .didFail(Nav(action: navAct(2), redirects: [navAct(1)], .failed(WKError(.frameLoadInterruptedByPolicyChange))), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
    }

    func testWhenCustomSchemeNavigationIsInterruptedByNewRequestThenDidFailIsCalled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let lock = NSLock()
        defer {
            lock.try()
            lock.unlock()
        }

        lock.lock()
        server.middleware = [{ [data] request in
            lock.lock()
            lock.unlock()
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        testSchemeHandler.onRequest = { [responseData=data.html] task in
            task.didReceive(.response(for: task.request, mimeType: "text/html", expectedLength: responseData.count))
            task.didReceive(responseData.dropLast(5))
        }

        responder(at: 0).onNavigationAction = { _, _ in .allow }
        responder(at: 0).onDidCommit = { [unowned webView=withWebView(do: { $0 }), urls] nav in
            if nav.url.matches(urls.testScheme) {
                DispatchQueue.main.async {
                    webView.load(req(urls.local4))
                    lock.unlock()
                }
            }
        }

        let eOnDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eOnDidFinish.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.testScheme))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main(responderIdx: 0)),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.testScheme, status: nil, data.html.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local4), .other, from: history[1], src: main(urls.testScheme, responderIdx: 0))),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),

            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled)), resp: resp(0), .committed, isCurrent: false), NSURLErrorCancelled),

            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local4, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(1), .committed))
        ])
    }

    func testClientRedirectNavigationActionCancellation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .instant

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.html))
            default:
                return .raw(200, "OK", ["refresh": "1; url=" + urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)

        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            if navAction.url.matches(urls.local2) {
                return .cancel
            }
            return .allow
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, mime: "text/plain", headers: ["Refresh": "1; url=/2", "Server": "Swifter Unspecified"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client(delay: 1.0)), from: history[1], redirects: [navAct(1)], src: main(urls.local))),
            .didCancel(navAct(2)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),
        ])
    }

    func testClientRedirectNavigationActionCancellationWhenDidFinishReceivedAfterNavigationAction() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .afterWillStartNavigationAction

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.html))
            default:
                return .raw(200, "OK", ["refresh": "1; url=" + urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)

        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            if navAction.url.matches(urls.local2) {
                return .cancel
            }
            return .allow
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, mime: "text/plain", headers: ["Refresh": "1; url=/2", "Server": "Swifter Unspecified"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client(delay: 1.0)), from: history[1], redirects: [navAct(1)], src: main(urls.local))),
            .didCancel(navAct(2)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),
        ])
    }

    func testClientRedirectNavigationResponseCancellation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.html))
            default:
                return .raw(200, "OK", ["refresh": "1; url=" + urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)

        responder(at: 0).onNavigationResponse = { [urls] navResponse in
            if navResponse.url.matches(urls.local2) {
                return .cancel
            }
            return .allow
        }

        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in
            eDidFail.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, mime: "text/plain", headers: ["Refresh": "1; url=/2", "Server": "Swifter Unspecified"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client(delay: 1.0)), from: history[1], redirects: [navAct(1)], src: main(urls.local))),
            .didReceiveRedirect(navAct(2), Nav(action: navAct(1), .redirected(.client(delay: 1)), resp: resp(0), .committed, isCurrent: false)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didFail(Nav(action: navAct(2), redirects: [navAct(1)], .failed(WKError(.frameLoadInterruptedByPolicyChange)), resp: resp(1)), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
    }

    @MainActor
    func testUserInitiatedRedirectNotInterpretedAsClientRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let lock = NSLock()
        let unlock = { lock.unlock() }
        defer {
            lock.try()
            lock.unlock()
        }

        server.middleware = [{ [unowned webView=withWebView(do: { $0 }), unowned navigationDelegateProxy, urls, data] request in
            switch request.path {
            case urls.local3.path:
                DispatchQueue.main.async {
                    navigationDelegateProxy!.nextNavigationActionShouldBeUserInitiated = true
                    webView.evaluateJavaScript("window.location.href='\(urls.local2)'")
                }
                lock.lock()
                lock.unlock()

                return .ok(.data(data.html))
            case urls.local2.path:
                return .ok(.data(data.html))
            default:
                return .ok(.html(data.htmlWithIframe3.utf8String()!))
            }
        }]
        try server.start(8084)

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onNavigationAction = { @MainActor [urls] navAction, _ in
            if navAction.url.matches(urls.local2) {
#if _IS_USER_INITIATED_ENABLED
                XCTAssertTrue(navAction.isUserInitiated)
#endif
                unlock()
            }
            return .allow
        }
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        lock.lock()
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        // filter out iframe events
        responder(at: 0).history.removeAll {
            switch $0 {
            case .navigationAction(let navAct, _, _):
                return navAct.navigationAction.url.matches(urls.local3)
            case .navigationResponse(.response(let resp, _), _):
                return resp.response.url.matches(urls.local3)
            case .didCommit(let nav, _):
                return nav.navigationAction.navigationAction.url.matches(urls.local3)
            case .didFinish(let nav, _):
                return nav.navigationAction.navigationAction.url.matches(urls.local3)
            default:
                return false
            }
        }
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local), .other, src: main())),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            // user-initiated action
            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], .userInitiated, src: main(urls.local))),

            .willStart(Nav(action: navAct(3), .approved, isCurrent: false)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, isCurrent: false)),

            .didStart(Nav(action: navAct(3), .started)),
            .response(Nav(action: navAct(3), .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(3), .responseReceived, resp: resp(response(matching: urls.local2)), .committed)),
            .didFinish(Nav(action: navAct(3), .finished, resp: resp(response(matching: urls.local2)), .committed)),
        ])
    }

    // somewhat arguable: I don‘t know how to simulate failing navigation after it has performed client redirect
    // but just in case it can be failed we‘re handling it the same way as the one competed normally
    func testClientRedirectWithFailingInitialNavigation() throws {
        navigationDelegateProxy.didFailEventsDispatchTime = .beforeWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.clientRedirectData.utf8String()!))
        }, { [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        navigationDelegateProxy.replaceDidFinishWithDidFailWithError = WKError(.unknown)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client), from: history[1], redirects: [navAct(1)], src: main(urls.local))),
            .didReceiveRedirect(navAct(2), Nav(action: navAct(1), .redirected(.client), resp: resp(0), .committed, isCurrent: false)),

            .didFail(Nav(action: navAct(1), .failed(WKError(.unknown)), resp: resp(0), .committed, isCurrent: false), WKError.Code.unknown.rawValue),

            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local3, data.html.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),

            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed))
        ])
    }

    @MainActor
    func testClientRedirectInterruptedWithDeveloperRedirectDoesNotAppearInBackHistory() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var developerRedirectExpectation: XCTestExpectation!
        responder(at: 0).onNavigationAction = { @MainActor [urls] action, _ in
            if action.url.matches(urls.local3) {
                // Developer-redirect during client-redirected navigation
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.load(req(urls.local4))
                    developerRedirectExpectation.fulfill()
                }
            }
            return .allow
        }

        server.middleware = [{ [urls, data] request in
            guard request.path == urls.local2.path else { return nil }
            return .ok(.html(data.clientRedirectData.utf8String()!))
        }, { [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        // Load initial page (client-redirect.html)
        let eDidFinishInitial = expectation(description: "onDidFinish urls.local")
        let eDidFinishLocal2 = expectation(description: "onDidFinish urls.local2")
        let eDidFinishFinal = expectation(description: "onDidFinish urls.local4")

        responder(at: 0).onDidFinish = { [urls] navigation in
            if navigation.url.matches(urls.local) {
                eDidFinishInitial.fulfill()
            } else if navigation.url.matches(urls.local2) {
                eDidFinishLocal2.fulfill()
            } else if navigation.url.matches(urls.local4) {
                eDidFinishFinal.fulfill()
            }
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        wait(for: [eDidFinishInitial], timeout: 5)

        // Click the link to js-redir page (urls.local2), which client-redirects to urls.local3,
        // then developer-redirects to final destination (urls.local4)
        developerRedirectExpectation = expectation(description: "Developer-redirected")

        withWebView { webView in
            _=webView.load(req(urls.local2))
        }
        wait(for: [eDidFinishLocal2, eDidFinishFinal, developerRedirectExpectation], timeout: 5)

        withWebView { webView in
            // Validate back/forward history
            let backURLs = webView.backForwardList.backList.map(\.url)
            let forwardURLs = webView.backForwardList.forwardList.map(\.url)
            let currentURL = webView.backForwardList.currentItem?.url

            // js-redir page (urls.local2) should NOT appear in back history due to interrupted redirect
            XCTAssertEqual(backURLs.map { $0.separatedString }, [urls.local.separatedString])

            // Should have no forward history
            XCTAssertEqual(forwardURLs, [], "Should have no forward history")

            // Current URL should be final destination (urls.local4)
            XCTAssertEqual(currentURL?.separatedString, urls.local4.separatedString, "Current URL should be final destination after redirect")
        }
    }

    @MainActor
    func testClientRedirectInterruptedWithCustomNavigationTypeDoesNotAppearInBackHistory() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var developerRedirectExpectation: XCTestExpectation!
        responder(at: 0).onNavigationAction = { @MainActor [urls] action, _ in
            if action.url.matches(urls.local3) {
                // Developer-redirect during client-redirected navigation
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.load(req(urls.local4), withExpectedNavigationType: .custom(CustomNavigationType(rawValue: "redir")))
                    developerRedirectExpectation.fulfill()
                }
            }
            return .allow
        }

        server.middleware = [{ [urls, data] request in
            guard request.path == urls.local2.path else { return nil }
            return .ok(.html(data.clientRedirectData.utf8String()!))
        }, { [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        // Load initial page (client-redirect.html)
        let eDidFinishInitial = expectation(description: "onDidFinish urls.local")
        let eDidFinishLocal2 = expectation(description: "onDidFinish urls.local2")
        let eDidFinishFinal = expectation(description: "onDidFinish urls.local4")

        responder(at: 0).onDidFinish = { [urls] navigation in
            if navigation.url.matches(urls.local) {
                eDidFinishInitial.fulfill()
            } else if navigation.url.matches(urls.local2) {
                eDidFinishLocal2.fulfill()
            } else if navigation.url.matches(urls.local4) {
                eDidFinishFinal.fulfill()
            }
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        wait(for: [eDidFinishInitial], timeout: 5)

        // Click the link to js-redir page (urls.local2), which client-redirects to urls.local3,
        // then developer-redirects to final destination (urls.local4)
        developerRedirectExpectation = expectation(description: "Developer-redirected")

        withWebView { webView in
            _=webView.load(req(urls.local2))
        }
        wait(for: [eDidFinishLocal2, eDidFinishFinal, developerRedirectExpectation], timeout: 5)

        withWebView { webView in
            // Validate back/forward history
            let backURLs = webView.backForwardList.backList.map(\.url)
            let forwardURLs = webView.backForwardList.forwardList.map(\.url)
            let currentURL = webView.backForwardList.currentItem?.url

            // js-redir page (urls.local2) should NOT appear in back history due to interrupted redirect
            XCTAssertEqual(backURLs.map { $0.separatedString }, [urls.local.separatedString])

            // Should have no forward history
            XCTAssertEqual(forwardURLs, [], "Should have no forward history")

            // Current URL should be final destination (urls.local4)
            XCTAssertEqual(currentURL?.separatedString, urls.local4.separatedString, "Current URL should be final destination after redirect")
        }
    }

    @MainActor
    func testInterruptedClientRedirectInNewTabHasNoBackHistory() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var developerRedirectExpectation: XCTestExpectation!
        responder(at: 0).onNavigationAction = { @MainActor [urls] action, _ in
            if action.url.matches(urls.local3) {
                // Developer-redirect during client-redirected navigation
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.load(req(urls.local4))
                    developerRedirectExpectation.fulfill()
                }
            }
            return .allow
        }

        server.middleware = [{ [urls, data] request in
            guard request.path == urls.local2.path else { return nil }
            return .ok(.html(data.clientRedirectData.utf8String()!))
        }, { [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        // Simulate ⌘-click by directly loading the redirect link in a fresh webView
        developerRedirectExpectation = expectation(description: "Developer-redirected")
        let eDidFinishLocal2 = expectation(description: "onDidFinish urls.local2")
        let eDidFinishFinal = expectation(description: "onDidFinish urls.local4")

        responder(at: 0).onDidFinish = { [urls] navigation in
            if navigation.url.matches(urls.local2) {
                eDidFinishLocal2.fulfill()
            } else if navigation.url.matches(urls.local4) {
                eDidFinishFinal.fulfill()
            }
        }

        // Load the redirect URL directly (simulating ⌘-click on link)
        // This creates a fresh navigation context with no prior history
        // urls.local2 client-redirects to urls.local3, then developer-redirects to final destination (urls.local4)
        withWebView { webView in
            _=webView.load(req(urls.local2))
        }
        wait(for: [eDidFinishLocal2, eDidFinishFinal, developerRedirectExpectation], timeout: 5)

        withWebView { webView in
            // Validate new tab has no back history
            let backURLs = webView.backForwardList.backList.map(\.url)
            let forwardURLs = webView.backForwardList.forwardList.map(\.url)
            let currentURL = webView.backForwardList.currentItem?.url

            // Should have no back history (empty back list)
            XCTAssertEqual(backURLs, [], "New tab should have no back history")

            // Should have no forward history
            XCTAssertEqual(forwardURLs, [], "New tab should have no forward history")

            // Current URL should be final destination (urls.local4)
            XCTAssertEqual(currentURL?.separatedString, urls.local4.separatedString, "Current URL should be final destination after redirect")

            // Back button should be effectively disabled (no back history)
            XCTAssertFalse(webView.canGoBack, "Back button should be disabled in new tab")
        }
    }

    @MainActor
    func testDoubleClientRedirectBothInterruptedWithDeveloperRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var firstDeveloperRedirectExpectation: XCTestExpectation!
        var secondDeveloperRedirectExpectation: XCTestExpectation!
        responder(at: 0).onNavigationAction = { @MainActor [urls] action, _ in
            if action.url.matches(urls.local3) {
                // First developer-redirect during first client-redirected navigation
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.load(req(urls.local4))
                    firstDeveloperRedirectExpectation.fulfill()
                }
            } else if action.url.matches(urls.local2) {
                // Second developer-redirect during second client-redirected navigation
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.load(req(urls.local6))
                    secondDeveloperRedirectExpectation.fulfill()
                }
            }
            return .allow
        }

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local5.path:
                // First client redirect page: redirects to urls.local3
                return .ok(.html(data.clientRedirectData.utf8String()!))
            case urls.local4.path:
                // Second client redirect page: redirects to urls.local2
                return .ok(.html(data.clientRedirectData2.utf8String()!))
            default:
                return .ok(.data(data.html))
            }
        }]
        try server.start(8084)

        // Set up expectations dictionary for all navigation URLs
        var expectations: [String: XCTestExpectation] = [:]

        responder(at: 0).onDidFinish = { navigation in
            expectations[navigation.url.separatedString]?.fulfill() ?? { XCTFail("Unexpected navigation URL: \(navigation.url.separatedString)") }()
        }

        // Load initial page (client-redirect.html)
        expectations[urls.local.separatedString] = expectation(description: "onDidFinish urls.local")
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        // Navigate to first client-redirect page (urls.local5), which client-redirects to urls.local3,
        // then developer-redirects to urls.local4, which client-redirects to urls.local2,
        // then developer-redirects to final destination (urls.local6)
        firstDeveloperRedirectExpectation = expectation(description: "First Developer-redirect")
        secondDeveloperRedirectExpectation = expectation(description: "Second Developer-redirect")

        // Set up expectations for all URLs in the redirect chain (local3 and local2 would be interrupted by developer-redirect)
        expectations[urls.local5.separatedString] = expectation(description: "onDidFinish urls.local5")
        expectations[urls.local4.separatedString] = expectation(description: "onDidFinish urls.local4")
        expectations[urls.local6.separatedString] = expectation(description: "onDidFinish urls.local6")

        withWebView { webView in
            _=webView.load(req(urls.local5))
        }
        waitForExpectations(timeout: 5)

        withWebView { webView in
            // Validate back/forward history
            let backURLs = webView.backForwardList.backList.map(\.url)
            let forwardURLs = webView.backForwardList.forwardList.map(\.url)
            let currentURL = webView.backForwardList.currentItem?.url

            // Both client-redirect pages (urls.local5 and urls.local5) should NOT appear in back history due to interrupted redirects
            XCTAssertEqual(backURLs.map { $0.separatedString }, [urls.local.separatedString], "Back history should only contain initial page")

            // Should have no forward history
            XCTAssertEqual(forwardURLs, [], "Should have no forward history")

            // Current URL should be final destination (urls.local6)
            XCTAssertEqual(currentURL?.separatedString, urls.local6.separatedString, "Current URL should be final destination after double redirect")
        }
    }

}

#endif
