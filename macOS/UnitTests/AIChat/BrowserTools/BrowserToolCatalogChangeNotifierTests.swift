//
//  BrowserToolCatalogChangeNotifierTests.swift
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
@testable import AIChat

@MainActor
final class BrowserToolCatalogChangeNotifierTests: XCTestCase {

    private var changes: PassthroughSubject<Void, Never>!
    private var notifier: BrowserToolCatalogChangeNotifier!

    override func setUp() {
        super.setUp()
        changes = PassthroughSubject()
    }

    override func tearDown() {
        notifier = nil
        changes = nil
        super.tearDown()
    }

    func testWhenSignatureIsUnchangedThenNothingIsAnnounced() async {
        var announcements = 0
        notifier = BrowserToolCatalogChangeNotifier(changes: changes.eraseToAnyPublisher(),
                                                    signature: { ["a", "b"] },
                                                    onChange: { announcements += 1 })

        changes.send(())
        changes.send(())
        await Task.yield()

        XCTAssertEqual(announcements, 0)
    }

    func testWhenSignatureChangesThenItIsAnnouncedOnce() async {
        var enabled = ["a"]
        var announcements = 0
        notifier = BrowserToolCatalogChangeNotifier(changes: changes.eraseToAnyPublisher(),
                                                    signature: { enabled },
                                                    onChange: { announcements += 1 })

        enabled = ["a", "b"]
        changes.send(())
        await settle()
        changes.send(())
        await settle()

        XCTAssertEqual(announcements, 1)
    }

    func testWhenSignatureChangesBackThenEachChangeIsAnnounced() async {
        var enabled = ["a"]
        var announcements = 0
        notifier = BrowserToolCatalogChangeNotifier(changes: changes.eraseToAnyPublisher(),
                                                    signature: { enabled },
                                                    onChange: { announcements += 1 })

        enabled = []
        changes.send(())
        await settle()
        enabled = ["a"]
        changes.send(())
        await settle()

        XCTAssertEqual(announcements, 2)
    }

    private func settle() async {
        for _ in 0..<20 where true { await Task.yield() }
    }
}
