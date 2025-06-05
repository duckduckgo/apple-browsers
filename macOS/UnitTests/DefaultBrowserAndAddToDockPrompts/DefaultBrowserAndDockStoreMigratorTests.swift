//
//  DefaultBrowserAndDockStoreMigratorTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser

struct DefaultBrowserAndDockStoreMigratorTests {
    private var oldStoreMock: MockDefaultBrowserAndDockPromptRepository!
    private var newStoreMock: MockDefaultBrowserAndDockPromptStore!
    private var sut: DefaultBrowserAndDockPromptStoreMigrator!
    private var timeTraveller: TimeTraveller!
    private static let now = Date(timeIntervalSince1970: 1747872000)

    init() {
        oldStoreMock = MockDefaultBrowserAndDockPromptRepository()
        newStoreMock = MockDefaultBrowserAndDockPromptStore()
        timeTraveller = TimeTraveller(date: Self.now)
        sut = DefaultBrowserAndDockPromptStoreMigrator(oldStore: oldStoreMock, newStore: newStoreMock, dateProvider: timeTraveller.getDate)
    }

    @Test("Check Migration Happens When User Has Seen Generic Prompt But Not Popover")
    func whenUserHasSeenPromptAndNotSeenPopoverThenSavePopoverShownDate() {
        // GIVEN
        oldStoreMock.setPromptShown(true)
        #expect(newStoreMock.popoverShownDate == nil)

        // WHEN
        sut.migrateIfNeeded()

        // THEN
        #expect(newStoreMock.popoverShownDate == Self.now.timeIntervalSince1970)
        #expect(!oldStoreMock.didShowPrompt())
    }

    @Test("Check Migration Does Not Happen When User Has Seen Prompt And Seen Popover")
    func whenUserHasSeenPromptAndSeenPopoverThenDoNotChangePopoverShownDateOrResetPromptShown() {
        // Arrange
        oldStoreMock.setPromptShown(true)
        newStoreMock.popoverShownDate = Self.now.timeIntervalSince1970
        timeTraveller.advanceBy(.days(1))

        // WHEN
        sut.migrateIfNeeded()

        // THEN
        #expect(newStoreMock.popoverShownDate == Self.now.timeIntervalSince1970)
        #expect(oldStoreMock.didShowPrompt())
    }

    @Test("Check Migration Does Not Happen When User Has Not Seen Prompt")
    func whenUserHasNotSeenPromptThenDoNotChangePopoverShownDateOrResetPromptShown() {
        // Given
        oldStoreMock.setPromptShown(false)

        // When
        sut.migrateIfNeeded()

        // Then
        #expect(newStoreMock.popoverShownDate == nil)
        #expect(!oldStoreMock.didShowPrompt())
    }

    @Test("Check Multiple Migration Calls Do Not Overwrite Previous Value")
    func whenCalledMultipleTimesThenSetPopoverShownDateOnce() {
        // GIVEN
        oldStoreMock.setPromptShown(true)

        // WHEN
        sut.migrateIfNeeded()
        let popoverShownDate = newStoreMock.popoverShownDate
        // Update date and execute migration again
        timeTraveller.advanceBy(.days(2))
        sut.migrateIfNeeded()

        // THEN
        #expect(newStoreMock.popoverShownDate == popoverShownDate)
        #expect(!oldStoreMock.didShowPrompt())
    }
}
