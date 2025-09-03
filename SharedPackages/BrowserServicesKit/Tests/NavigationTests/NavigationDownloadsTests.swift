//
//  NavigationDownloadsTests.swift
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
class NavigationDownloadsTests: DistributedNavigationDelegateTestsBase {

    func testDownloadNavigationAction() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        responder(at: 0).onNavigationAction = { _, params in
            return .download
        }

        let eNavActionBecameDownload = expectation(description: "onNavActionBecameDownload")
        responder(at: 0).onNavActionBecameDownload = { _, _ in
            eNavActionBecameDownload.fulfill()
        }

        withWebView { webView in
            _=webView.load(URLRequest(url: urls.local))
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .navActionWillBecomeDownload(navAct(1)),
            .navActionBecameDownload(navAct(1), urls.local)
        ])
    }

    func testDownloadNavigationActionFromFrame() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .afterDidStartNavigationAction
        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithIframe3.utf8String()!))
        }, { [data, urls] request in
            guard request.path == urls.local3.path else { return nil }
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        var frameID: UInt64!
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            if navAction.url.path == urls.local3.path {
#if _FRAME_HANDLE_ENABLED
                frameID = navAction.targetFrame?.handle.frameID
                XCTAssertNotEqual(frameID, WKFrameInfo.defaultMainFrameHandle)
#endif
                return .download
            }
            return .next
        }

        let eNavActionBecameDownload = expectation(description: "onNavActionBecameDownload")
        responder(at: 0).onNavActionBecameDownload = { _, _ in
            eNavActionBecameDownload.fulfill()
        }
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(main(responderIdx: 0).handle.frameID, urls.local), targ: frame(frameID, .empty, secOrigin: urls.local.securityOrigin)),
            .navActionWillBecomeDownload(navAct(2)),

            .navActionBecameDownload(navAct(2), urls.local3),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),
        ])
    }

    func testDownloadNavigationResponse() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data, urls] request in
            guard request.path == "/" else { return nil }
            return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                try! writer.write(data.empty)
            }
        }, { [data] request in
            return .ok(.data(data.html, contentType: "application/zip"))
        }]
        try server.start(8084)

        responder(at: 0).onNavigationAction = { _, params in
            return .allow
        }
        responder(at: 0).onNavigationResponse = { resp in
            XCTAssertFalse(resp.canShowMIMEType)
            XCTAssertFalse(resp.shouldDownload)
            XCTAssertEqual(resp.httpResponse?.isSuccessful, true)
            return .download
        }
        let eNavResponseBecameDownload = expectation(description: "onNavResponseBecameDownload")
        responder(at: 0).onNavResponseBecameDownload = { _, _ in
            eNavResponseBecameDownload.fulfill()
        }
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in
            eDidFail.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .navigationAction(req(urls.local2, defaultHeaders.allowingExtraKeys), .redirect(.server), redirects: [navAct(1)], src: main()),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, mime: "application/zip", data.html.count, headers: .default + ["Content-Type": "application/zip"], nil, .cantShow))),
            .navResponseWillBecomeDownload(0),
            .navResponseBecameDownload(0, urls.local2),

            .didFail(Nav(action: navAct(2), redirects: [navAct(1)], .failed(WKError(.frameLoadInterruptedByPolicyChange)), resp: resp(0)), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue),
        ])
    }

    func testDownloadNavigationResponseFromFrame() throws {
        let didFinishLoadingFrameHandler = CustomCallbacksHandler()
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })), .weak(didFinishLoadingFrameHandler))

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithIframe3.utf8String()!))
        }, { [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        var frameID: UInt64!
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
#if _FRAME_HANDLE_ENABLED
            if navAction.url.path == urls.local1.path {
                frameID = navAction.targetFrame?.handle.frameID
                XCTAssertNotEqual(frameID, WKFrameInfo.defaultMainFrameHandle)
            }
#endif
            return .next
        }
        responder(at: 0).onNavigationResponse = { _ in
            .download
        }

        let eNavResponseBecameDownload = expectation(description: "onNavResponseBecameDownload")
        responder(at: 0).onNavResponseBecameDownload = { _, _ in
            eNavResponseBecameDownload.fulfill()
        }
        let eDidFailLoadingFrame = expectation(description: "didFailLoadingFrame")
        didFinishLoadingFrameHandler.didFailProvisionalLoadInFrame = { request, frame, _ in
            eDidFailLoadingFrame.fulfill()
        }

        responder(at: 0).clear()
        withWebView { webView in
            webView.evaluateJavaScript("window.frames[0].location.href = '\(urls.local1.string)'")
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(main(responderIdx: 0).handle.frameID, urls.local), targ: frame(frameID, urls.local3)),
            .response(.resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil),
            .navResponseWillBecomeDownload(2),
            .navResponseBecameDownload(2, urls.local1),
        ])
    }

    func testMultipleDownloadNavigationActions() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .afterDidStartNavigationAction

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWith3iFrames.utf8String()!))
        }, { [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        var frameIDs = [String: UInt64]()
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            guard navAction.url.matches(urls.local) else {
#if _FRAME_HANDLE_ENABLED
                frameIDs[navAction.url.path] = navAction.targetFrame?.handle.frameID
                XCTAssertNotEqual(navAction.targetFrame?.handle.frameID, WKFrameInfo.defaultMainFrameHandle)
#endif
                return .download
            }
            return .next
        }

        let eNavActionBecameDownload = expectation(description: "onNavActionBecameDownload")
        eNavActionBecameDownload.expectedFulfillmentCount = 3
        responder(at: 0).onNavActionBecameDownload = { _, _ in
            eNavActionBecameDownload.fulfill()
        }
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWith3iFrames.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(main(responderIdx: 0).handle.frameID, urls.local), targ: frame(frameIDs[urls.local2.path], .empty, secOrigin: urls.local.securityOrigin))),
            .navActionWillBecomeDownload(navAct(2)),
            .navActionBecameDownload(navAct(2), urls.local2),

            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(main(responderIdx: 0).handle.frameID, urls.local), targ: frame(frameIDs[urls.local3.path], .empty, secOrigin: urls.local.securityOrigin))),
            .navActionWillBecomeDownload(navAct(3)),
            .navActionBecameDownload(navAct(3), urls.local3),

            .navigationAction(NavAction(req(urls.local4, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(main(responderIdx: 0).handle.frameID, urls.local), targ: frame(frameIDs[urls.local4.path], .empty, secOrigin: urls.local.securityOrigin))),
            .navActionWillBecomeDownload(navAct(4)),
            .navActionBecameDownload(navAct(4), urls.local4),

            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),
        ])
    }

    func testMultipleDownloadNavigationResponses() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .afterDidStartNavigationAction

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWith3iFrames.utf8String()!))
        }, { [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        var frameIDs = [String: UInt64]()
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            if !navAction.url.matches(urls.local) {
#if _FRAME_HANDLE_ENABLED
                frameIDs[navAction.url.path] = navAction.targetFrame?.handle.frameID
                XCTAssertNotEqual(navAction.targetFrame?.handle.frameID, WKFrameInfo.defaultMainFrameHandle)
#endif
            }
            return .allow
        }
        responder(at: 0).onNavigationResponse = { [urls] navResponse in
            guard navResponse.url.matches(urls.local) else {
                return .download
            }
            return .allow
        }

        let eNavResponseBecameDownload = expectation(description: "onNavResponseBecameDownload")
        eNavResponseBecameDownload.expectedFulfillmentCount = 3
        responder(at: 0).onNavResponseBecameDownload = { _, _ in
            eNavResponseBecameDownload.fulfill()
        }
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWith3iFrames.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(main(responderIdx: 0).handle.frameID, urls.local), targ: frame(frameIDs[urls.local2.path], .empty, secOrigin: urls.local.securityOrigin))),
            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(main(responderIdx: 0).handle.frameID, urls.local), targ: frame(frameIDs[urls.local3.path], .empty, secOrigin: urls.local.securityOrigin))),
            .navigationAction(NavAction(req(urls.local4, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(main(responderIdx: 0).handle.frameID, urls.local), targ: frame(frameIDs[urls.local4.path], .empty, secOrigin: urls.local.securityOrigin))),

            .response(.resp(urls.local2, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .navResponseWillBecomeDownload(1),
            .navResponseBecameDownload(response(matching: urls.local2), urls.local2),

            .response(.resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .navResponseWillBecomeDownload(2),
            .navResponseBecameDownload(response(matching: urls.local3), urls.local3),

            .response(.resp(urls.local4, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .navResponseWillBecomeDownload(3),
            .navResponseBecameDownload(response(matching: urls.local4), urls.local4),

            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),
        ])
    }

    func testDownloadCancellation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish")

        responder(at: 0).onNavigationAction = { _, _ in .download }
        responder(at: 0).onNavActionBecameDownload = { _, download in
            (download as WebKitDownload).cancel { _ in
                eDidFinish.fulfill()
            }
        }

        withWebView { webView in
            _=webView.load(URLRequest(url: urls.local))
        }
        waitForExpectations()
    }

}

#endif
