//
//  HistoryTabExtensionTests.swift
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

import BrowserServicesKit
import Combine
import History
import Navigation
import SharedTestUtilities
import WebKit
import XCTest
import HistoryView

@testable import DuckDuckGo_Privacy_Browser

private struct MockScriptProvider: HistoryUserScriptProvider {
    var historyViewUserScript: HistoryViewUserScript
}

class HistoryTabExtensionTests: XCTestCase {

    @MainActor
    func testWhenNotCapturingHistory_ThenNoHistoryIsStored() {
        let historyCoordinatingMock = HistoryCoordinatingMock()

        let trackersPublisher: AnyPublisher<DetectedTracker, Never> = Empty().eraseToAnyPublisher()
        let urlPublisher: AnyPublisher<URL?, Never> = Empty().eraseToAnyPublisher()
        let titlePublisher: AnyPublisher<String?, Never> = Empty().eraseToAnyPublisher()

        let mockScriptProvider = MockScriptProvider(historyViewUserScript: HistoryViewUserScript())
        let scriptsSubject = CurrentValueSubject<MockScriptProvider, Never>(mockScriptProvider)
        let webViewSubject = PassthroughSubject<WKWebView, Never>()

        let historyTabExtension = HistoryTabExtension(
            isCapturingHistory: false,
            historyCoordinating: historyCoordinatingMock,
            trackersPublisher: trackersPublisher,
            urlPublisher: urlPublisher,
            titlePublisher: titlePublisher,
            scriptsPublisher: scriptsSubject.eraseToAnyPublisher(),
            webViewPublisher: webViewSubject.eraseToAnyPublisher()
        )

        let navigationIdentity = NavigationIdentity(nil)
        let responderChain = ResponderChain(responderRefs: [])
        let urlRequest = URLRequest(url: .duckDuckGo)
        let frameInfo = FrameInfo(frame: .mock())
        let navigationAction = NavigationAction(request: urlRequest, navigationType: .reload, currentHistoryItemIdentity: nil, redirectHistory: [], isUserInitiated: false, sourceFrame: frameInfo, targetFrame: nil, shouldDownload: false, mainFrameNavigation: nil)
        let navigation = Navigation(identity: navigationIdentity, responders: responderChain, state: .started, redirectHistory: [navigationAction], isCurrent: true, isCommitted: false)
        historyTabExtension.willStart(navigation)
        historyTabExtension.didCommit(navigation)

        XCTAssertFalse(historyCoordinatingMock.addVisitCalled)
        XCTAssertFalse(historyCoordinatingMock.updateTitleIfNeededCalled)
        XCTAssertFalse(historyCoordinatingMock.commitChangesCalled)
    }

    // MARK: - HistoryCoordinating.visits(matching:)

    @MainActor
    func testVisitsMatchingReturnsMatchingVisits() {
        let mock = HistoryCoordinatingMock()
        let url1 = URL(string: "https://example.com")!
        let url2 = URL(string: "https://test.org")!
        let visit1 = Visit(date: Date(), identifier: url1)
        let visit2 = Visit(date: Date(), identifier: url2)
        mock.allHistoryVisits = [visit1, visit2]

        let result = mock.visits(matching: [url1, url2])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0 === visit1 }))
        XCTAssertTrue(result.contains(where: { $0 === visit2 }))
    }

    @MainActor
    func testVisitsMatchingReturnsEmptyForUnknownIDs() {
        let mock = HistoryCoordinatingMock()
        mock.allHistoryVisits = [Visit(date: Date(), identifier: URL(string: "https://example.com")!)]

        let result = mock.visits(matching: [URL(string: "https://unknown.com")!])
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testVisitsMatchingReturnsMixedResults() {
        let mock = HistoryCoordinatingMock()
        let knownURL = URL(string: "https://example.com")!
        let unknownURL = URL(string: "https://unknown.com")!
        let visit = Visit(date: Date(), identifier: knownURL)
        mock.allHistoryVisits = [visit]

        let result = mock.visits(matching: [knownURL, unknownURL])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === visit)
    }

    @MainActor
    func testVisitsMatchingReturnsEmptyForEmptyIDs() {
        let mock = HistoryCoordinatingMock()
        mock.allHistoryVisits = [Visit(date: Date(), identifier: URL(string: "https://example.com")!)]

        let result = mock.visits(matching: [])
        XCTAssertTrue(result.isEmpty)
    }

}
