//
//  AIChatSessionTests.swift
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
import Combine
import AIChat
import SharedTestUtilities
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AIChatSessionTests: XCTestCase {

    var session: AIChatSession!

    override func setUp() {
        super.setUp()
        AIChatFloatingWindowController.windowFactory = { contentRect in
            MockWindow(contentRect: contentRect, isVisible: false)
        }
        session = AIChatSession(state: AIChatState(initialAIChatURL: URL.blankPage.forAIChatSidebar()), burnerMode: .regular)
    }

    override func tearDown() {
        AIChatFloatingWindowController.windowFactory = { contentRect in
            AIChatFloatingWindow(contentRect: contentRect)
        }
        session = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func testInit_startsWithNilViewController() {
        XCTAssertNil(session.chatViewController)
    }

    func testInit_startsWithNilFloatingWindowController() {
        XCTAssertNil(session.floatingWindowController)
    }

    // MARK: - Make Chat View Controller

    func testMakeChatViewController_createsViewController() {
        let vc = session.makeChatViewController(tabID: "tab1")

        XCTAssertNotNil(vc)
        XCTAssertIdentical(session.chatViewController, vc)
    }

    func testMakeChatViewController_setsTabID() {
        let vc = session.makeChatViewController(tabID: "my-tab")

        XCTAssertEqual(vc.tabID, "my-tab")
    }

    func testMakeChatViewController_calledTwice_returnsSameInstance() {
        let first = session.makeChatViewController(tabID: "tab1")
        let second = session.makeChatViewController(tabID: "tab1")

        XCTAssertIdentical(first, second)
    }

    func testMakeChatViewController_withRestorationData_appliesItToVC() {
        session.state.restorationData = "saved-data"

        let vc = session.makeChatViewController(tabID: "tab1")

        XCTAssertNotNil(vc)
    }

    // MARK: - Snapshot Current URL

    func testSnapshotCurrentURL_withNoVC_doesNotCrash() {
        XCTAssertNil(session.chatViewController)
        session.snapshotCurrentURL()
        XCTAssertNil(session.state.aiChatURL)
    }

    func testSnapshotCurrentURL_withVC_snapshotsURL() {
        _ = session.makeChatViewController(tabID: "tab1")

        session.snapshotCurrentURL()

        XCTAssertNotNil(session.state.aiChatURL)
    }

    // MARK: - Current AI Chat URL

    func testCurrentAIChatURL_withNoVC_fallsBackToState() {
        let stateURL = session.state.currentAIChatURL
        XCTAssertEqual(session.currentAIChatURL, stateURL)
    }

    func testCurrentAIChatURL_withVC_readsFromVC() {
        let vc = session.makeChatViewController(tabID: "tab1")

        XCTAssertEqual(session.currentAIChatURL, vc.currentAIChatURL)
    }

    // MARK: - Tear Down

    func testTearDown_nilsOutViewController() {
        _ = session.makeChatViewController(tabID: "tab1")
        XCTAssertNotNil(session.chatViewController)

        session.tearDown(persistingState: false)

        XCTAssertNil(session.chatViewController)
    }

    func testTearDown_nilsOutFloatingWindowController() {
        session.floatingWindowController = AIChatFloatingWindowController(
            tabID: "tab1",
            chatViewController: session.makeChatViewController(tabID: "tab1"),
            tabViewModel: nil,
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600))

        session.tearDown(persistingState: false)

        XCTAssertNil(session.floatingWindowController)
    }

    func testTearDown_setsStateToHidden() {
        session.state.setSidebar()
        XCTAssertEqual(session.state.presentationMode, .sidebar)

        session.tearDown(persistingState: false)

        XCTAssertEqual(session.state.presentationMode, .hidden)
        XCTAssertEqual(session.state.presentationMode, .hidden)
    }

    func testTearDown_withPersistingState_snapshotsURL() {
        _ = session.makeChatViewController(tabID: "tab1")
        XCTAssertNil(session.state.aiChatURL)

        session.tearDown(persistingState: true)

        XCTAssertNotNil(session.state.aiChatURL)
    }

    func testTearDown_withoutPersistingState_doesNotSnapshotURL() {
        _ = session.makeChatViewController(tabID: "tab1")
        XCTAssertNil(session.state.aiChatURL)

        session.tearDown(persistingState: false)

        XCTAssertNil(session.state.aiChatURL)
    }
}
