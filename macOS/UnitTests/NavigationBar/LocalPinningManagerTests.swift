//
//  LocalPinningManagerTests.swift
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

import Testing
import VPN

@testable import DuckDuckGo_Privacy_Browser

/// Serialized: every test clears and reads the shared UserDefaults-backed pinning state.
@Suite(.serialized)
final class LocalPinningManagerTests {

    init() {
        UserDefaultsWrapper<Any>.clearAll()
    }

    deinit {
        UserDefaultsWrapper<Any>.clearAll()
    }

    private func createManager() -> LocalPinningManager {
        return LocalPinningManager()
    }

    @available(iOS 16, macOS 13, *)
    @Test("When toggling pinning for a view and view is not pinned, then view becomes pinned", .timeLimit(.minutes(1)))
    func testWhenTogglingPinningForAView_AndViewIsNotPinned_ThenViewBecomesPinned() {
        let manager = createManager()

        #expect(!manager.isPinned(.autofill))
        #expect(!manager.isPinned(.bookmarks))

        manager.togglePinning(for: .autofill)

        #expect(manager.isPinned(.autofill))
        #expect(!manager.isPinned(.bookmarks))
    }

    @available(iOS 16, macOS 13, *)
    @Test("When toggling pinning for a view and view is already pinned, then view becomes unpinned", .timeLimit(.minutes(1)))
    func testWhenTogglingPinningForAView_AndViewIsAlreadyPinned_ThenViewBecomesUnpinned() {
        let manager = createManager()

        #expect(!manager.isPinned(.autofill))
        #expect(!manager.isPinned(.bookmarks))

        manager.togglePinning(for: .autofill)

        #expect(manager.isPinned(.autofill))
        #expect(!manager.isPinned(.bookmarks))

        manager.togglePinning(for: .autofill)

        #expect(!manager.isPinned(.autofill))
        #expect(!manager.isPinned(.bookmarks))
    }

    @available(iOS 16, macOS 13, *)
    @Test("When changing pinned views, then notification is posted", .timeLimit(.minutes(1)))
    func testWhenChangingPinnedViews_ThenNotificationIsPosted() async {
        await confirmation("Pinned views changed notification") { confirmation in
            NotificationCenter.default.addObserver(forName: .PinnedViewsChanged, object: nil, queue: .main) { _ in
                confirmation()
            }

            let manager = createManager()
            manager.togglePinning(for: .autofill)
        }
    }

}
