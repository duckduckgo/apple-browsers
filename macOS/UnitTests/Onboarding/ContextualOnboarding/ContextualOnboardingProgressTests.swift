//
//  ContextualOnboardingProgressTests.swift
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

@_spi(Testing) import Persistence
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct ContextualOnboardingProgressTests {

    let stateStorage = MockContextualDialogStateStoring()
    let store = InMemoryThrowingKeyValueStore()
    let progress: ContextualOnboardingProgress

    init() {
        progress = ContextualOnboardingProgress(storage: stateStorage, settings: store.throwingKeyedStoring())
    }

    @available(iOS 16, macOS 13, *)
    @Test("Marking a dialog seen is reflected by hasSeen", .timeLimit(.minutes(1)))
    func markSeenThenHasSeen() {
        progress.markSeen(.tryASearch)

        #expect(progress.hasSeen(.tryASearch))
        #expect(!progress.hasSeen(.highFive))
        #expect(stateStorage.contextualDialogsSeen == ["tryASearch"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("The path kind is saved by its raw value and read back", .timeLimit(.minutes(1)))
    func pathKindRoundTrip() throws {
        #expect(progress.pathKind == nil)

        progress.pathKind = .search

        #expect(progress.pathKind == .search)
        #expect(try store.object(forKey: "contextual-onboarding_path-kind") as? String == "search")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fire button use is saved", .timeLimit(.minutes(1)))
    func fireButtonUsedIsSaved() {
        #expect(!progress.fireButtonUsedOnce)

        progress.fireButtonUsedOnce = true

        #expect(stateStorage.fireButtonUsedOnce)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reset clears seen dialogs, Fire use and the path", .timeLimit(.minutes(1)))
    func resetClearsEverything() throws {
        progress.markSeen(.tryASearch)
        progress.fireButtonUsedOnce = true
        progress.pathKind = .search

        progress.reset()

        #expect(stateStorage.contextualDialogsSeen.isEmpty)
        #expect(!stateStorage.fireButtonUsedOnce)
        #expect(progress.pathKind == nil)
        #expect(try store.object(forKey: "contextual-onboarding_path-kind") == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An unknown saved state reads as completed, and a new state is saved by its raw value", .timeLimit(.minutes(1)))
    func stateReadsAndWrites() {
        stateStorage.stateString = ""
        #expect(progress.state == .onboardingCompleted)

        progress.state = .ongoing

        #expect(stateStorage.stateString == "ongoing")
        #expect(progress.state == .ongoing)
    }
}
