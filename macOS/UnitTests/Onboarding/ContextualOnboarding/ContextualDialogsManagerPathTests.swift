//
//  ContextualDialogsManagerPathTests.swift
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

/// How the manager starts a path chosen at the junction.
@MainActor
struct ContextualDialogsManagerPathTests {

    let stateStorage = MockContextualDialogStateStoring()
    let searchPathStorage = MockBlockedTrackerStoring()
    let store = InMemoryThrowingKeyValueStore()
    let uiLocker = CapturingUILocker()
    let manager: ContextualDialogsManager

    init() {
        manager = .withSearchPath(trackerMessageProvider: MockTrackerMessageProvider(),
                                  subscriptionUpsellExperiment: SpyOnboardingSubscriptionUpsellEnrolling(),
                                  stateStorage: stateStorage,
                                  searchPathStorage: searchPathStorage,
                                  settings: store.throwingKeyedStoring(),
                                  uiLocker: uiLocker)
        manager.state = .notStarted
    }

    @available(iOS 16, macOS 13, *)
    @Test("Starting the search path saves it and skips Try a search", .timeLimit(.minutes(1)))
    func startSearchPath() async throws {
        manager.startPath(.search)

        #expect(try store.object(forKey: "contextual-onboarding_path-kind") as? String == "search")
        let newTab = await Tab(content: .newtab)
        #expect(manager.dialogTypeForTab(newTab) == .tryASite)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The search path never locks the UI", .timeLimit(.minutes(1)))
    func searchPathDoesNotLock() {
        #expect(manager.uiLock == UserInteractionLock.none)

        manager.startPath(.search)
        manager.state = .ongoing
        manager.fireButtonUsed()
        manager.state = .onboardingCompleted

        #expect(manager.uiLock == UserInteractionLock.none)
        #expect(uiLocker.calls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The Duck.ai path locks all but Fire once, until Fire is used", .timeLimit(.minutes(1)))
    func duckAIPathLocksUntilFire() {
        manager.startPath(.duckAI)
        manager.state = .ongoing

        #expect(manager.uiLock == .locked(except: [.fire]))
        #expect(uiLocker.calls == [.locked(except: [.fire])])

        manager.fireButtonUsed()

        #expect(manager.uiLock == UserInteractionLock.none)
        #expect(uiLocker.calls == [.locked(except: [.fire]), UserInteractionLock.none])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ending or restarting onboarding unlocks the UI", .timeLimit(.minutes(1)),
          arguments: [ContextualOnboardingState.onboardingCompleted, .notStarted])
    func endingOnboardingUnlocks(newState: ContextualOnboardingState) {
        manager.startPath(.duckAI)

        manager.state = newState

        #expect(manager.uiLock == UserInteractionLock.none)
        #expect(uiLocker.calls == [.locked(except: [.fire]), UserInteractionLock.none])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Starting the Duck.ai path saves it and asks for no search dialogs", .timeLimit(.minutes(1)))
    func startDuckAIPath() async throws {
        manager.startPath(.duckAI)

        #expect(try store.object(forKey: "contextual-onboarding_path-kind") as? String == "duckAI")
        let newTab = await Tab(content: .newtab)
        #expect(manager.dialogTypeForTab(newTab) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Restarting onboarding forgets the chosen path", .timeLimit(.minutes(1)))
    func restartClearsThePath() throws {
        manager.startPath(.search)
        manager.state = .ongoing

        manager.state = .notStarted

        #expect(try store.object(forKey: "contextual-onboarding_path-kind") == nil)
        #expect(stateStorage.contextualDialogsSeen.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Restarting onboarding clears the state the path saves itself", .timeLimit(.minutes(1)))
    func restartResetsThePath() {
        manager.startPath(.search)
        searchPathStorage.blockedTrackerSeen = true

        manager.state = .notStarted

        #expect(!searchPathStorage.blockedTrackerSeen)
    }
}

final class CapturingUILocker: ContextualOnboardingUILocking {
    private(set) var calls: [UserInteractionLock] = []

    func setUILock(_ lock: UserInteractionLock) {
        calls.append(lock)
    }
}
