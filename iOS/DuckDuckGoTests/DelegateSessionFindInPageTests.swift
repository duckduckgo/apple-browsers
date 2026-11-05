//
//  DelegateSessionFindInPageTests.swift
//  DuckDuckGo
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

#if DEBUG
import WebKit
import XCTest
@testable import DuckDuckGo

@available(iOS 16.0, *)
@MainActor
final class DelegateSessionFindInPageTests: XCTestCase {
    func testWaitsForResultsBeforeSelectingAndTreatsNotFoundIndexAsUnselected() {
        let session = SessionSpy()
        let find = makeFind(session: session)
        XCTAssertTrue(find.search(forText: "needle"))
        find.refreshResults(generation: 1)
        XCTAssertTrue(session.directions.isEmpty)
        XCTAssertEqual(find.current, 0)

        session.resultCount = 3
        find.refreshResults(generation: 1)
        XCTAssertEqual(session.directions, [.forward])
        XCTAssertEqual(find.current, 0)
        XCTAssertEqual(find.total, 3)

        session.highlightedResultIndex = 0
        find.refreshResults(generation: 1)
        XCTAssertEqual(find.current, 1)
        find.refreshResults(generation: 1)
        XCTAssertEqual(session.directions, [.forward])
    }

    func testQueryReplacementRejectsOldObservationsAndClearIsDistinctFromEnd() {
        let session = SessionSpy()
        var retainedQuery = ""
        let find = makeFind(session: session) { retainedQuery = $0 }
        XCTAssertTrue(find.search(forText: "old"))
        XCTAssertTrue(find.search(forText: "new"))
        session.resultCount = 2
        session.highlightedResultIndex = 1

        find.refreshResults(generation: 1)
        XCTAssertEqual(find.total, 0)
        find.refreshResults(generation: 2)
        XCTAssertEqual(find.total, 2)
        XCTAssertEqual(find.current, 2)
        XCTAssertEqual(retainedQuery, "new")

        XCTAssertTrue(find.search(forText: ""))
        find.refreshResults(generation: 3)
        XCTAssertEqual(find.total, 0)
        XCTAssertEqual(find.current, 0)
        XCTAssertEqual(retainedQuery, "")
        XCTAssertEqual(session.queries, ["old", "new"])
        XCTAssertEqual(session.invalidations, 3)
        XCTAssertEqual(session.ends, 0)
    }

    func testNavigationUsesEngineDirectionsAndReadsWrappedIndex() {
        let session = SessionSpy()
        let find = makeFind(session: session)
        _ = find.search(forText: "needle")
        session.resultCount = 3
        session.highlightedResultIndex = 2
        find.next()
        XCTAssertEqual(session.directions, [.forward])
        session.highlightedResultIndex = 0
        find.refreshResults(generation: 1)
        XCTAssertEqual(find.current, 1)
        find.previous()
        XCTAssertEqual(session.directions, [.forward, .backward])
        session.highlightedResultIndex = 2
        find.refreshResults(generation: 1)
        XCTAssertEqual(find.current, 3)
    }

    func testEndIsIdempotentAndTimerDoesNotRetainTheAdapter() {
        let session = SessionSpy()
        var find: DelegateSessionFindInPage? = makeFind(session: session)
        weak var weakFind = find
        find?.done()
        find?.done()
        XCTAssertFalse(find?.search(forText: "late") ?? true)
        find?.next()
        session.resultCount = 3
        find?.refreshResults(generation: 0)
        XCTAssertEqual(find?.total, 0)
        find = nil
        XCTAssertNil(weakFind)
        XCTAssertEqual(session.ends, 1)
        XCTAssertTrue(session.queries.isEmpty)
    }

    func testDeinitializationEndsAnUnclosedSession() {
        let session = SessionSpy()
        var find: DelegateSessionFindInPage? = makeFind(session: session)
        weak var weakFind = find
        find = nil
        XCTAssertNil(weakFind)
        XCTAssertEqual(session.ends, 1)
    }

    func testFailureIsExplicitAndNeverUsesAnotherBackend() {
        let find = DelegateSessionFindInPage(webView: WKWebView(), query: "retained", queryChanged: { _ in }) { _ in
            throw WebKitDelegateFindSession.Failure.sessionUnavailable
        }
        XCTAssertEqual(find.diagnosticStatus, "EXPERIMENT FAILED · WebKit returned no session")
        XCTAssertEqual(find.searchTerm, "retained")
        XCTAssertEqual(find.total, 0)
        _ = find.search(forText: "")
        XCTAssertEqual(find.searchTerm, "")
        find.done()
    }

    private func makeFind(session: SessionSpy, queryChanged: @escaping (String) -> Void = { _ in }) -> DelegateSessionFindInPage {
        DelegateSessionFindInPage(webView: WKWebView(), query: "", queryChanged: queryChanged, sessionFactory: { _ in session })
    }
}

@available(iOS 16.0, *)
private final class SessionSpy: DelegateFindSession {
    var resultCount = 0
    var highlightedResultIndex = NSNotFound
    var isNativeUIVisible = false
    var queries: [String] = []
    var directions: [UITextStorageDirection] = []
    var invalidations = 0
    var ends = 0

    func search(_ query: String) { queries.append(query) }
    func highlight(_ direction: UITextStorageDirection) { directions.append(direction) }
    func invalidate() { invalidations += 1 }
    func end() { ends += 1 }
}
#endif
