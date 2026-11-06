//
//  HoveredLinkTabExtensionTests.swift
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

import Combine
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class HoveredLinkTabExtensionTests: XCTestCase {

    private var script: HoverUserScript!
    private var tabExtension: HoveredLinkTabExtension!
    private var cancellables = Set<AnyCancellable>()
    private let url = URL(string: "https://example.com/link")!

    override func setUp() {
        super.setUp()
        script = HoverUserScript()
        tabExtension = HoveredLinkTabExtension(hoverUserScriptPublisher: Just(script))
    }

    override func tearDown() {
        cancellables.removeAll()
        tabExtension = nil
        script = nil
        super.tearDown()
    }

    func testWhenNothingWasHoveredThenCurrentLinkIsNil() {
        XCTAssertNil(tabExtension.currentHoveredLink)
    }

    func testWhenScriptReportsLinkThenItIsTheCurrentLinkAndIsPublished() {
        var received = [URL?]()
        tabExtension.hoveredLinkPublisher.sink { received.append($0) }.store(in: &cancellables)

        tabExtension.hoverUserScript(script, didChange: url)

        XCTAssertEqual(tabExtension.currentHoveredLink, url)
        XCTAssertEqual(received, [url])
    }

    func testWhenSubscribingWhileLinkIsHoveredThenCurrentValueIsNotReplayed() {
        tabExtension.hoverUserScript(script, didChange: url)
        var received = [URL?]()

        tabExtension.hoveredLinkPublisher.sink { received.append($0) }.store(in: &cancellables)

        XCTAssertTrue(received.isEmpty, "A new subscriber, for example after a tab switch, must not get a stale link")
        XCTAssertEqual(tabExtension.currentHoveredLink, url)
    }

    func testWhenNewDocumentIsCommittedThenHoveredLinkIsForgottenAndPublishedAsNil() {
        tabExtension.hoverUserScript(script, didChange: url)
        var received = [URL?]()
        tabExtension.hoveredLinkPublisher.sink { received.append($0) }.store(in: &cancellables)

        tabExtension.resetForNewDocument()

        XCTAssertNil(tabExtension.currentHoveredLink)
        XCTAssertEqual(received, [nil])
        XCTAssertNil(script.lastURL)
    }

    func testWhenNewDocumentIsCommittedWithoutHoveredLinkThenNothingIsPublished() {
        var received = [URL?]()
        tabExtension.hoveredLinkPublisher.sink { received.append($0) }.store(in: &cancellables)

        tabExtension.resetForNewDocument()

        XCTAssertTrue(received.isEmpty)
    }

}
