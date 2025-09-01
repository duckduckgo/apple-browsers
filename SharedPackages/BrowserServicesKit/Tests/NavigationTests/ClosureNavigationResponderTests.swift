//
//  ClosureNavigationResponderTests.swift
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
class ClosureNavigationResponderTests: DistributedNavigationDelegateTestsBase {

    @MainActor
    func testWhenNavigationFinished_didFinishIsCalled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock()))

        server.middleware = [{ [urls, data] request in
            guard request.path == "/" else { return nil }
            return .raw(301, "Moved", ["Location": urls.local3.path]) { writer in
                try! writer.write(data.empty)
            }
        }, { [data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }, { [data] request in
            return .ok(.data(data.html))
        }]

        let navigator = withWebView { Navigator(webView: $0, distributedNavigationDelegate: navigationDelegate, currentNavigation: nil) }

        try server.start(8084)
        let eNavAction = expectation(description: "navigationAction")
        var navigationActionCounter = 0
        let eWillStart = expectation(description: "willStart")
        let eDidStart = expectation(description: "didStart")
        let eAuthenticationChallenge = expectation(description: "authenticationChallenge")
        let eRedirected = expectation(description: "redirected")
        let eResponse = expectation(description: "navigationResponse")
        let eDidCommit = expectation(description: "didCommit")
        let eNavigationDidFinish = expectation(description: "navigationDidFinish")

        navigator.load(req(urls.local))?
            .overrideResponders { _, _ in
                navigationActionCounter += 1
                guard navigationActionCounter == 2 else { return .next }
                eNavAction.fulfill()
                return .allow
            } willStart: { _ in
                eWillStart.fulfill()
            } didStart: { _ in
                eDidStart.fulfill()
            } authenticationChallenge: { _, _ in
                eAuthenticationChallenge.fulfill()
                return .next
            } redirected: { _, _ in
                eRedirected.fulfill()
            } navigationResponse: { _ in
                eResponse.fulfill()
                return .next
            } didCommit: { _ in
                eDidCommit.fulfill()
            } navigationDidFinish: { _ in
                eNavigationDidFinish.fulfill()
            } navigationDidFail: { _, _ in
                XCTFail("unexpected didFail")
            } navigationActionWillBecomeDownload: { _, _ in
                XCTFail("unexpected navigationActionWillBecomeDownload")
            } navigationActionDidBecomeDownload: { _, _ in
                XCTFail("unexpected navigationActionWillBecomeDownload")
            } navigationResponseWillBecomeDownload: { _, _ in
                XCTFail("unexpected navigationResponseWillBecomeDownload")
            } navigationResponseDidBecomeDownload: { _, _ in
                XCTFail("unexpected navigationResponseWillBecomeDownload")
            }

        waitForExpectations()
    }

    @MainActor
    func testWhenNavigationActionCancelled_didCancelIsCalled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock()))

        let navigator = withWebView { Navigator(webView: $0, distributedNavigationDelegate: navigationDelegate, currentNavigation: nil) }

        try server.start(8084)
        let eNavAction = expectation(description: "navigationAction")
        let eDidCancel = expectation(description: "didCancel")
        navigator.load(req(urls.local))?
            .overrideResponders { _, _ in
                eNavAction.fulfill()
                return .cancel
            } didCancel: { _, expected in
                XCTAssertNil(expected)
                eDidCancel.fulfill()
            } willStart: { _ in
                XCTFail("unexpected willStart")
            } didStart: { _ in
                XCTFail("unexpected didStart")
            } authenticationChallenge: { _, _ in
                XCTFail("unexpected authenticationChallenge")
                return .next
            } redirected: { _, _ in
                XCTFail("unexpected redirected")
            } navigationResponse: { _ in
                XCTFail("unexpected navigationResponse")
                return .next
            } didCommit: { _ in
                XCTFail("unexpected didCommit")
            } navigationDidFinish: { _ in
                XCTFail("unexpected didFinish")
            } navigationDidFail: { _, _ in
                XCTFail("unexpected didFail")
            } navigationActionWillBecomeDownload: { _, _ in
                XCTFail("unexpected navigationActionWillBecomeDownload")
            } navigationActionDidBecomeDownload: { _, _ in
                XCTFail("unexpected navigationActionWillBecomeDownload")
            } navigationResponseWillBecomeDownload: { _, _ in
                XCTFail("unexpected navigationResponseWillBecomeDownload")
            } navigationResponseDidBecomeDownload: { _, _ in
                XCTFail("unexpected navigationResponseWillBecomeDownload")
            }

        waitForExpectations()
    }

    @MainActor
    func testWhenNavigationActionRedirected_didCancelIsCalled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock()))

        let navigator = withWebView { Navigator(webView: $0, distributedNavigationDelegate: navigationDelegate, currentNavigation: nil) }

        try server.start(8084)
        let eNavAction = expectation(description: "navigationAction")
        let eDidCancel = expectation(description: "didCancel")

        navigator.load(req(urls.local))?
            .overrideResponders { [urls] navAction, _ in
                eNavAction.fulfill()

                return .redirect(navAction.mainFrameTarget!) { navigator in
                    navigator.load(req(urls.local2))?.overrideResponders { _, _ in .cancel }
                    navigator.load(req(urls.local3))?.overrideResponders { _, _ in .cancel }
                }
            } didCancel: { _, expected in
                XCTAssertEqual(expected?.count, 2)
                eDidCancel.fulfill()
            } willStart: { _ in
                XCTFail("unexpected willStart")
            } didStart: { _ in
                XCTFail("unexpected didStart")
            } authenticationChallenge: { _, _ in
                XCTFail("unexpected authenticationChallenge")
                return .next
            } redirected: { _, _ in
                XCTFail("unexpected redirected")
            } navigationResponse: { _ in
                XCTFail("unexpected navigationResponse")
                return .next
            } didCommit: { _ in
                XCTFail("unexpected didCommit")
            } navigationDidFinish: { _ in
                XCTFail("unexpected didFinish")
            } navigationDidFail: { _, _ in
                XCTFail("unexpected didFail")
            } navigationActionWillBecomeDownload: { _, _ in
                XCTFail("unexpected navigationActionWillBecomeDownload")
            } navigationActionDidBecomeDownload: { _, _ in
                XCTFail("unexpected navigationActionWillBecomeDownload")
            } navigationResponseWillBecomeDownload: { _, _ in
                XCTFail("unexpected navigationResponseWillBecomeDownload")
            } navigationResponseDidBecomeDownload: { _, _ in
                XCTFail("unexpected navigationResponseWillBecomeDownload")
            }

        waitForExpectations()
    }

    @MainActor
    func testWhenNavigationFails_didFailIsCalled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock()))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]

        let navigator = withWebView { Navigator(webView: $0, distributedNavigationDelegate: navigationDelegate, currentNavigation: nil) }

        try server.start(8084)
        let eResponse = expectation(description: "navigationResponse")
        let eNavigationDidFail = expectation(description: "navigationDidFail")

        navigator.load(req(urls.local))?
            .overrideResponders(navigationResponse: { _ in
                eResponse.fulfill()
                return .cancel
            }, didCommit: { _ in
                XCTFail("unexpected didCommit")
            }, navigationDidFinish: { _ in
                XCTFail("unexpected navigationDidFinish")
            }, navigationDidFail: { _, error in
                XCTAssertEqual(error.code, .frameLoadInterruptedByPolicyChange)
                eNavigationDidFail.fulfill()
            }, navigationActionWillBecomeDownload: { _, _ in
                XCTFail("unexpected navigationActionWillBecomeDownload")
            }, navigationActionDidBecomeDownload: { _, _ in
                XCTFail("unexpected navigationActionWillBecomeDownload")
            }, navigationResponseWillBecomeDownload: { _, _ in
                XCTFail("unexpected navigationResponseWillBecomeDownload")
            }, navigationResponseDidBecomeDownload: { _, _ in
                XCTFail("unexpected navigationResponseWillBecomeDownload")
            })

        waitForExpectations()
    }

    @MainActor
    func testPrependNavigationResponder() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        responder(at: 0).onNavigationAction = { _, _ in .cancel }
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        let eNavigationAction = expectation(description: "onNavigationAction")
        withWebView {
            Navigator(webView: $0, distributedNavigationDelegate: navigationDelegate, currentNavigation: nil)
                .load(req(urls.local))!
                .prependResponder { _, _ in
                    eNavigationAction.fulfill()
                    return .allow
                }
        }
        waitForExpectations()

        XCTAssertFalse(navAct(1).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            .willStart(Nav(action: NavAction(req(urls.local), .redirect(.developer), src: main()), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
        ])
    }

    @MainActor
    func testAppendNavigationResponder() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        responder(at: 0).onNavigationAction = { _, _ in .allow }
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        let eWillStart = expectation(description: "willStart")
        let eDidStart = expectation(description: "didStart")
        let eResponse = expectation(description: "navigationResponse")
        let eDidCommit = expectation(description: "didCommit")
        let eNavigationDidFinish = expectation(description: "navigationDidFinish")

        withWebView {
            Navigator(webView: $0, distributedNavigationDelegate: navigationDelegate, currentNavigation: nil)
                .load(req(urls.local))!
                .appendResponder { _, _ in
                    XCTFail("unexpected navigationAction")
                    return .cancel
                } willStart: { _ in
                    eWillStart.fulfill()
                } didStart: { _ in
                    eDidStart.fulfill()
                } authenticationChallenge: { _, _ in
                    XCTFail("unexpected authenticationChallenge")
                    return .next
                } redirected: { _, _ in
                    XCTFail("unexpected redirected")
                } navigationResponse: { _ in
                    eResponse.fulfill()
                    return .next
                } didCommit: { _ in
                    eDidCommit.fulfill()
                } navigationDidFinish: { _ in
                    eNavigationDidFinish.fulfill()
                } navigationDidFail: { _, _ in
                    XCTFail("unexpected didFail")
                } navigationActionWillBecomeDownload: { _, _ in
                    XCTFail("unexpected navigationActionWillBecomeDownload")
                } navigationActionDidBecomeDownload: { _, _ in
                    XCTFail("unexpected navigationActionWillBecomeDownload")
                } navigationResponseWillBecomeDownload: { _, _ in
                    XCTFail("unexpected navigationResponseWillBecomeDownload")
                } navigationResponseDidBecomeDownload: { _, _ in
                    XCTFail("unexpected navigationResponseWillBecomeDownload")
                }
        }
        waitForExpectations()

        XCTAssertFalse(navAct(1).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local), .redirect(.developer), src: main())),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
        ])
    }

    @MainActor
    func testWhenNavigationActionPolicyIsDownload_willAndDidBecomeDownloadCalled() throws {
        let navigator = withWebView { Navigator(webView: $0, distributedNavigationDelegate: navigationDelegate, currentNavigation: nil) }

        let eWillBecomeDownload = expectation(description: "WillBecomeDownload")
        let eDidBecomeDownload = expectation(description: "DidBecomeDownload")
        navigator.load(req(urls.local))?
            .overrideResponders { _, _ in
                return .download
            } didCommit: { _ in
                XCTFail("unexpected didCommit")
            } navigationDidFinish: { _ in
                XCTFail("unexpected navigationDidFinish")
            } navigationDidFail: { _, error in
                XCTFail("unexpected navigationDidFail")
            } navigationActionWillBecomeDownload: { _, _ in
                eWillBecomeDownload.fulfill()
            } navigationActionDidBecomeDownload: { _, _ in
                eDidBecomeDownload.fulfill()
            } navigationResponseWillBecomeDownload: { _, _ in
                XCTFail("unexpected navigationResponseWillBecomeDownload")
            } navigationResponseDidBecomeDownload: { _, _ in
                XCTFail("unexpected navigationResponseWillBecomeDownload")
            }

        waitForExpectations()
    }

    @MainActor
    func testWhenNavigationResponsePolicyIsDownload_willAndDidBecomeDownloadCalled() throws {
        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        let navigator = withWebView { Navigator(webView: $0, distributedNavigationDelegate: navigationDelegate, currentNavigation: nil) }

        let eResponse = expectation(description: "navigationResponse")
        let eWillBecomeDownload = expectation(description: "WillBecomeDownload")
        let eDidBecomeDownload = expectation(description: "DidBecomeDownload")
        let eDidFail = expectation(description: "DidFail")
        navigator.load(req(urls.local))?
            .overrideResponders { _, _ in
                return .allow
            } navigationResponse: { _ in
                eResponse.fulfill()
                return .download
            } navigationDidFinish: { _ in
                XCTFail("unexpected navigationDidFinish")
            } navigationDidFail: { _, error in
                XCTAssertEqual(error.code, .frameLoadInterruptedByPolicyChange)
                eDidFail.fulfill()
            } navigationActionWillBecomeDownload: { _, _ in
                XCTFail("unexpected navigationActionWillBecomeDownload")
            } navigationActionDidBecomeDownload: { _, _ in
                XCTFail("unexpected navigationActionWillBecomeDownload")
            } navigationResponseWillBecomeDownload: { _, _ in
                eWillBecomeDownload.fulfill()
            } navigationResponseDidBecomeDownload: { _, _ in
                eDidBecomeDownload.fulfill()
            }

        waitForExpectations()
    }

    @MainActor
    func testWhenWebContentProcessIsTerminated_webProcessDidTerminateAndNavigationDidFailReceived() throws {
        let eDidFail = expectation(description: "onDidFail")
        let eDidTerminate = expectation(description: "onDidTerminate")
        let responder = ClosureNavigationResponder(decidePolicy: { _, _ in
            .allow
        }, navigationResponse: { [unowned self] _ in
            self._webView.killWebContentProcess()
            return .next
        }, navigationDidFail: { nav, error in
            XCTAssertTrue(nav.isCurrent)
            XCTAssertEqual(error.userInfo[WKProcessTerminationReason.userInfoKey] as? WKProcessTerminationReason, WKProcessTerminationReason.crash)

            eDidFail.fulfill()
        }, webContentProcessDidTerminate: { reason in
            XCTAssertEqual(reason, .crash)
            eDidTerminate.fulfill()
        })
        navigationDelegate.setResponders(.struct(responder))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.utf8String()!))
        }]
        try server.start(8084)

        withWebView { webView in
            _=webView.load(req(urls.local1))
        }

        waitForExpectations()
    }

}

#endif
