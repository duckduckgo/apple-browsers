//
//  DistributedNavigationDelegateTestsHelpers.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import os.log
import Swifter
import WebKit
import XCTest

@testable import Navigation

@objc private protocol WebProcessPoolPrivate: AnyObject {
    @objc(_setWebProcessCountLimit:) static func setWebProcessCountLimit(_ webProcessCountLimit: UInt)
}

@available(macOS 12.0, iOS 15.0, *)
class DistributedNavigationDelegateTestsBase: XCTestCase {

    var navigationDelegateProxy: NavigationDelegateProxy!

    var navigationDelegate: DistributedNavigationDelegate { navigationDelegateProxy.delegate }
    var testSchemeHandler: TestNavigationSchemeHandler! = TestNavigationSchemeHandler()
    var server: SafeHttpServer!

    var currentHistoryItemIdentityCancellable: AnyCancellable!
    var history = [UInt64: HistoryItemIdentity]()

    var _webView: WKWebView!
    @discardableResult
    func withWebView<T>(do block: (WKWebView) throws -> T) rethrows -> T {
        let webView = _webView ?? {
            let webView = makeWebView()
            _webView = webView
            return webView
        }()
        return try autoreleasepool {
            try block(webView)
        }
    }

    static let data = DataSource()
    var data: DataSource { Self.data }
    static let urls = URLs()
    var urls: URLs { Self.urls }

    override func setUp() {
        NavigationAction.resetIdentifier()

        server?.stop()
        server = SafeHttpServer()
        navigationDelegateProxy = DistributedNavigationDelegateTests.makeNavigationDelegateProxy()
        self.navigationDelegate.responders.forEach { responder in
            (responder as? NavigationResponderMock)?.reset(defaultHandler: { [testName=name] in
                XCTFail("[\(testName)] unexpected event received: \($0)")
            })
        }

        unsafeBitCast(WKProcessPool.self, to: WebProcessPoolPrivate.Type.self).setWebProcessCountLimit(5)
    }

    override func tearDown() {
        self.testSchemeHandler = nil
        server.stop()
        server = nil
        self.navigationDelegate.responders.forEach { responder in
            (responder as? NavigationResponderMock)?.reset(defaultHandler: { [testName=name] in
                XCTFail("[\(testName)] event received after test completed: \($0)")
            })
        }
        if let _webView {
            if let navigationDelegateProxy {
                let navigationDelegateProxyKey = UnsafeRawPointer(bitPattern: "navigationDelegateProxyKey".hashValue)!
                objc_setAssociatedObject(_webView, navigationDelegateProxyKey, navigationDelegateProxy, .OBJC_ASSOCIATION_RETAIN)
            }
            self._webView = nil
        }
        navigationDelegateProxy = nil
        currentHistoryItemIdentityCancellable = nil
        history.removeAll()
    }

}

@available(macOS 12.0, iOS 15.0, *)
extension DistributedNavigationDelegateTestsBase {

    static func makeNavigationDelegateProxy() -> NavigationDelegateProxy {
        NavigationDelegateProxy(delegate: DistributedNavigationDelegate())
    }

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(testSchemeHandler, forURLScheme: TestNavigationSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = navigationDelegateProxy
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
        currentHistoryItemIdentityCancellable = navigationDelegate.$currentHistoryItemIdentity.sink { [unowned self] (historyItem: HistoryItemIdentity?) in
            guard let historyItem,
                  !self.history.contains(where: { $0.value == historyItem }),
                  let lastNavigationAction = self.responder(at: 0)?.navigationActionsCache.max
            else { return }

            self.history[lastNavigationAction] = historyItem
            // os_log("added history item #%d: %s", type: .debug, Int(lastNavigationAction), historyItem.debugDescription)
        }
#endif
        return webView
    }

    struct URLs {
        let https = URL(string: "https://duckduckgo.com/")!

        let testScheme = URL(string: TestNavigationSchemeHandler.scheme + "://duckduckgo.com")!

        let local = URL(string: "http://localhost:8084")!
        let local1 = URL(string: "http://localhost:8084/1")!
        let local2 = URL(string: "http://localhost:8084/2")!
        let local3 = URL(string: "http://localhost:8084/3")!
        let local4 = URL(string: "http://localhost:8084/4")!
        let local5 = URL(string: "http://localhost:8084/5")!
        let local6 = URL(string: "http://localhost:8084/6")!

        let localHashed = URL(string: "http://localhost:8084#")!
        let localHashed1 = URL(string: "http://localhost:8084#navlink")!
        let localHashed2 = URL(string: "http://localhost:8084#navlink2")!
        let localHashed3 = URL(string: "http://localhost:8084#navlink3")!
        let local3Hashed = URL(string: "http://localhost:8084/3#navlink")!

        let localTarget = URL(string: "http://localhost:8084/#target")!
        let localTarget2 = URL(string: "http://localhost:8084/#target2")!
        let localTarget3 = URL(string: "http://localhost:8084/#target3")!

        let aboutBlank = URL(string: "about:blank")!

        let post3 = URL(string: "http://localhost:8084/post3.html")!
    }

    struct DataSource {
        let empty = Data()
        let html = """
            <html>
                <body>
                    some data<br/>
                    <a id="navlink" /><br/>
                    <a id="navlink2" /><br/>
                    <a id="navlink3" /><br/>
                </body>
            </html>
        """.data(using: .utf8)!
        let htmlWithIframe3 = "<html><body><iframe src='/3'></iframe></body></html>".data(using: .utf8)!
        let htmlWith3iFrames = """
        <html><body>
            <iframe src='/2'></iframe>
            <iframe src='/3'></iframe>
            <iframe src='/4'></iframe>
        </body></html>
        """.data(using: .utf8)!
        let htmlWithOpenInNewWindow: Data = {
            """
                <html><body>
                <script language='JavaScript'>
                    window.open("http://localhost:8084/2", "_blank");
                </script>
                </body></html>
            """.data(using: .utf8)!
        }()
        let htmlWithOpenInNewWindowLink: Data = {
            """
                <html><body>
                <a id="lnk" target="_blank" href="http://localhost:8084/2">the link</a>
                </body></html>
            """.data(using: .utf8)!
        }()

        let metaRedirect = """
        <html>
            <head>
                <meta http-equiv="Refresh" content="0; URL=http://localhost:8084/3" />
            </head>
        </html>
        """.data(using: .utf8)!
        let delayedMetaRedirect = """
        <html>
            <head>
                <meta http-equiv="Refresh" content="1; URL=http://localhost:8084/3" />
            </head>
        </html>
        """.data(using: .utf8)!

        let clientRedirectData: Data = """
            <html><body>
            <script language='JavaScript'>
                window.parent.location.replace("http://localhost:8084/3");
            </script>
            </body></html>
        """.data(using: .utf8)!

        let clientRedirectData2: Data = """
            <html><body>
            <script language='JavaScript'>
                window.parent.location.replace("http://localhost:8084/2");
            </script>
            </body></html>
        """.data(using: .utf8)!

        let sameDocumentClientRedirectData: Data = """
            <html><body>
            <script language='JavaScript'>
                window.parent.location.replace("http://localhost:8084/#navlink");
            </script>
            </body></html>
        """.data(using: .utf8)!

        let sessionStatePushClientRedirectData: Data = """
            <html><body>
            <script language='JavaScript'>
                history.pushState({ page: 1 }, "navlink", "#navlink");
            </script>
            </body></html>
        """.data(using: .utf8)!

        let sameDocumentTestData: Data = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <title>Same-document Navigation Test</title>
        </head>
        <body>

        <h1 id="target">Target Element</h1><br />
        <h1 id="target2">Target Element 2</h1><br />
        <h1 id="target3">Target Element 3</h1><br />

        <script>
          // Function to simulate same-document navigation
          function performNavigation(type) {
            switch (type) {
            case 'anchorNavigation':
              // Trigger anchor navigation
              window.location.href = '#target';
              break;

            case 'sessionStatePush':
              // Trigger session state push
              history.pushState({ page: 1 }, "title 1", "#target2");
              break;

            case 'sessionStateReplace':
              // Trigger session state replace
              history.replaceState({ page: 2 }, "title 2", "#target3");
              break;

            case 'sessionStatePop':
              // Trigger session state pop
              history.back();
              break;

            default:
              console.error('Invalid navigation type');
            }
          }
        </script>

        </body>
        </html>
        """.data(using: .utf8)!

        let customSchemeInteractionStateData = Data.sessionRestorationMagic + """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            <key>IsAppInitiated</key>
            <true/>
            <key>RenderTreeSize</key>
            <integer>3</integer>
            <key>SessionHistory</key>
            <dict>
            <key>SessionHistoryCurrentIndex</key>
            <integer>0</integer>
            <key>SessionHistoryEntries</key>
            <array>
                <dict>
                    <key>SessionHistoryEntryData</key>
                    <data>
                    AAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAeLI8QbDyBQAA
                    AAAAAAAAAP////8AAAAAd7I8QbDyBQD/////AAAAAAAA
                    AAAAAAAAAAAAAP////8=
                    </data>
                    <key>SessionHistoryEntryOriginalURL</key>
                    <string>\(TestNavigationSchemeHandler.scheme)://duckduckgo.com</string>
                    <key>SessionHistoryEntryShouldOpenExternalURLsPolicyKey</key>
                    <integer>1</integer>
                    <key>SessionHistoryEntryTitle</key>
                    <string></string>
                    <key>SessionHistoryEntryURL</key>
                    <string>about:blank</string>
                </dict>
            </array>
            <key>SessionHistoryVersion</key>
            <integer>1</integer>
            </dict>
            </dict>
            </plist>
        """.data(using: .utf8)!

        let aboutBlankAfterRegularNavigationInteractionStateData = Data.sessionRestorationMagic + """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            <key>IsAppInitiated</key>
            <true/>
            <key>RenderTreeSize</key>
            <integer>3</integer>
            <key>SessionHistory</key>
            <dict>
            <key>SessionHistoryCurrentIndex</key>
            <integer>1</integer>
            <key>SessionHistoryEntries</key>
            <array>
                <dict>
                    <key>SessionHistoryEntryData</key>
                    <data>
                    AAAAAAAAAAACAAAAAAAAAAAAAAAAAAAARIMiXLDyBQAA
                    AAAAAAAAAP////8AAAAAQ4MiXLDyBQD/////AAAAAAAA
                    AAAAAIA/AAAAAP////8=
                    </data>
                    <key>SessionHistoryEntryOriginalURL</key>
                    <string>http://localhost:8084/</string>
                    <key>SessionHistoryEntryShouldOpenExternalURLsPolicyKey</key>
                    <integer>1</integer>
                    <key>SessionHistoryEntryTitle</key>
                    <string></string>
                    <key>SessionHistoryEntryURL</key>
                    <string>http://localhost:8084/</string>
                </dict>
                <dict>
                    <key>SessionHistoryEntryData</key>
                    <data>
                    AAAAAAAAAAACAAAAAAAAAAAAAAAAAAAARoMiXLDyBQAA
                    AAAAAAAAAP////8AAAAARYMiXLDyBQD/////AAAAAAAA
                    AAAAAAAAAAAAAP////8=
                    </data>
                    <key>SessionHistoryEntryOriginalURL</key>
                    <string>about:blank</string>
                    <key>SessionHistoryEntryShouldOpenExternalURLsPolicyKey</key>
                    <integer>1</integer>
                    <key>SessionHistoryEntryTitle</key>
                    <string></string>
                    <key>SessionHistoryEntryURL</key>
                    <string>about:blank</string>
                </dict>
            </array>
            <key>SessionHistoryVersion</key>
            <integer>1</integer>
            </dict>
            </dict>
            </plist>
        """.data(using: .utf8)!

        let interactionStateData = Data.sessionRestorationMagic + """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            <key>IsAppInitiated</key>
            <true/>
            <key>RenderTreeSize</key>
            <integer>7</integer>
            <key>SessionHistory</key>
            <dict>
            <key>SessionHistoryCurrentIndex</key>
            <integer>1</integer>
            <key>SessionHistoryEntries</key>
            <array>
                <dict>
                    <key>SessionHistoryEntryData</key>
                    <data>
                    AAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAqehUL2XwBQAA
                    AAAAAAAAAP////8AAAAAqOhUL2XwBQD/////AAAAAAAA
                    AAAAAIA/AAAAAP////8=
                    </data>
                    <key>SessionHistoryEntryOriginalURL</key>
                    <string>http://localhost:8084/1</string>
                    <key>SessionHistoryEntryShouldOpenExternalURLsPolicyKey</key>
                    <integer>1</integer>
                    <key>SessionHistoryEntryTitle</key>
                    <string></string>
                    <key>SessionHistoryEntryURL</key>
                    <string>http://localhost:8084/1</string>
                </dict>
                <dict>
                    <key>SessionHistoryEntryData</key>
                    <data>
                    AAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAq+hUL2XwBQAA
                    AAAAAAAAAP////8AAAAAquhUL2XwBQD/////AAAAAAAA
                    AAAAAAAAAAAAAP////8=
                    </data>
                    <key>SessionHistoryEntryOriginalURL</key>
                    <string>http://localhost:8084/</string>
                    <key>SessionHistoryEntryShouldOpenExternalURLsPolicyKey</key>
                    <integer>1</integer>
                    <key>SessionHistoryEntryTitle</key>
                    <string></string>
                    <key>SessionHistoryEntryURL</key>
                    <string>http://localhost:8084/</string>
                </dict>
            </array>
            <key>SessionHistoryVersion</key>
            <integer>1</integer>
            </dict>
            </dict>
            </plist>
        """.data(using: .utf8)!
    }

    func responder(at index: Int) -> NavigationResponderMock! {
        for (idx, responder) in navigationDelegate.responders.enumerated() where idx == index {
            return responder as? NavigationResponderMock
        }
        return nil
    }

    func navAct(_ idx: UInt64, file: StaticString = #file, line: UInt = #line) -> NavAction {
        return responder(at: 0).navigationActionsCache.dict[idx] ??
            .init(.init(url: URL(string: "no-navigation-action-at-\(idx)")!), .other, src: .mainFrame(for: WKWebView()), targ: nil)
    }
    func resp(_ idx: Int) -> NavResponse {
        return responder(at: 0).navigationResponses[idx]
    }

    func response(matching url: URL) -> Int {
        responder(at: 0).navigationResponses.firstIndex(where: { $0.url.matches(url) })!
    }

    // MARK: FrameInfo mocking

    func main(webView webViewArg: WKWebView? = nil, _ current: URL = .empty, secOrigin: SecurityOrigin? = nil, responderIdx: Int? = nil) -> FrameInfo {
        if let responderIdx, let mainFrame = responder(at: responderIdx).mainFrame, current == .empty, secOrigin == nil {
            return mainFrame
        }
        return withWebView { webView in
            let handle = if let responderIdx, let mainFrame = responder(at: responderIdx).mainFrame {
                mainFrame.handle
            } else {
                webViewArg?.mainFrameHandle ?? webView.mainFrameHandle
            }
            return FrameInfo(webView: webViewArg ?? webView, handle: handle, isMainFrame: true, url: current, securityOrigin: secOrigin ?? current.securityOrigin)
        }
    }

    func frame(_ frameID: UInt64!, _ url: URL, secOrigin: SecurityOrigin? = nil) -> FrameInfo {
        withWebView { webView in
            FrameInfo(webView: webView, handle: .init(rawValue: frameID), isMainFrame: false, url: url, securityOrigin: secOrigin ?? url.securityOrigin)
        }
    }
    func frame(_ frameID: UInt64!, _ url: String, secOrigin: SecurityOrigin? = nil) -> FrameInfo {
        frame(frameID, URL(string: url)!, secOrigin: secOrigin)
    }

    // Event sequence checking
    func assertHistory(ofResponderAt responderIdx: Int, equalsTo rhs: [TestsNavigationEvent], file: StaticString = #file, line: UInt = #line, useEventLine: Bool = true) {
        let lhs = responder(at: responderIdx).history
        var rhs = rhs
        var lastEventLine = line
        let rhsMap = rhs.enumerated().reduce(into: [Int: TestsNavigationEvent]()) { $0[$1.offset] = $1.element }
        var idx2subst = 0
        for idx in 0..<max(lhs.count, rhs.count) {
            let event1 = lhs.indices.contains(idx) ? lhs[idx] : nil
            var idx2: Int! = (event1 != nil ? rhs.firstIndex(where: { event2 in compare("", event1, event2) == nil }) : nil)
            if let idx2 {
                // events are equal
                rhs.remove(at: idx2)
                idx2subst += 1
                continue
            } else if let originalEvent2 = rhsMap[idx], originalEvent2.type == event1?.type,
                      let idx = rhs.firstIndex(where: { event2 in compare("", originalEvent2, event2) == nil }) {
                idx2 = idx
            } else {
                idx2 = idx - idx2subst
            }

            let event2 = rhs.indices.contains(idx2) ? rhs.remove(at: idx2) : nil
            let line = useEventLine ? (event2?.line ?? lastEventLine) : line
            lastEventLine = line

            guard event1 != nil || event2 != nil else { continue }
            if let diff = compare(Mirror(reflecting: event1 ?? event2!).children.first!.label!, event1, event2) {
                printEncoded(responder: responderIdx)

                XCTFail("\n#\(idx): " + diff, file: file, line: line)
            }
        }
    }

    func assertHistory(ofResponderAt responderIdx: Int, equalsToHistoryOfResponderAt responderIdx2: Int,
                       file: StaticString = #file,
                       line: UInt = #line) {
        assertHistory(ofResponderAt: responderIdx, equalsTo: responder(at: responderIdx2).history, file: file, line: line, useEventLine: false)
    }

    func encodedResponderHistory(at idx: Int = 0) -> String {
        withWebView { webView in
            responder(at: idx).history.encoded(with: urls, webView: webView, dataSource: data, history: history, responderNavigationResponses: responder(at: 0).navigationResponses)
        }
    }

    func printEncoded(responder idx: Int = 0) {
        Logger.navigation.error("Responder #\(idx) history encoded:")
        let encodedHistory = encodedResponderHistory(at: idx)
        Logger.navigation.error("\(encodedHistory)")
    }

}

#endif
