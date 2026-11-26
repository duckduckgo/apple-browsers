//
//  TabBarTouchDragHandlerTests.swift
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

import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class TabBarTouchDragHandlerTests: XCTestCase {

    private var collectionView: NSCollectionView!
    private var delegate: MockCollectionViewDelegate!
    private var handler: TabBarTouchDragHandler!

    override func setUp() async throws {
        try await super.setUp()
        guard #available(macOS 27.0, *) else {
            throw XCTSkip("Touch screens need macOS 27")
        }

        delegate = MockCollectionViewDelegate()
        collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        collectionView.delegate = delegate
        handler = TabBarTouchDragHandler(collectionView: collectionView)
    }

    override func tearDown() async throws {
        handler = nil
        collectionView = nil
        delegate = nil
        try await super.tearDown()
    }

    func testWhenInitializedThenAddsOnePressRecognizer() {
        XCTAssertEqual(handlerRecognizers.count, 1)
        XCTAssertTrue(handlerRecognizers.first is NSPressGestureRecognizer)
    }

    func testWhenInitializedThenRecognizerIgnoresMouseButtons() throws {
        let recognizer = try XCTUnwrap(handlerRecognizers.first as? NSPressGestureRecognizer)

        XCTAssertEqual(recognizer.buttonMask, 0)
    }

    func testWhenInitializedThenRecognizerAcceptsOnlyDirectTouches() throws {
        let recognizer = try XCTUnwrap(handlerRecognizers.first)

        XCTAssertEqual(recognizer.allowedTouchTypes, .direct)
    }

    func testWhenPressHasNotBegunThenDelegateIsNotCalled() throws {
        let recognizer = try XCTUnwrap(handlerRecognizers.first)
        let action = try XCTUnwrap(recognizer.action)

        _ = handler.perform(action, with: recognizer)

        XCTAssertEqual(recognizer.state, .possible)
        XCTAssertTrue(delegate.calls.isEmpty)
    }

    /// AppKit installs its own recognizers on the collection view, so only the handler's are inspected.
    private var handlerRecognizers: [NSGestureRecognizer] {
        collectionView.gestureRecognizers.filter { $0.target === handler }
    }
}

private final class MockCollectionViewDelegate: NSObject, NSCollectionViewDelegate {

    private(set) var calls = [String]()

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        calls.append(#function)
        return NSString()
    }

    func collectionView(_ collectionView: NSCollectionView, didChangeItemsAt indexPaths: Set<IndexPath>, to highlightState: NSCollectionViewItem.HighlightState) {
        calls.append(#function)
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        calls.append(#function)
    }
}
