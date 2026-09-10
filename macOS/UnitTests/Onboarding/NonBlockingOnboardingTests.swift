//
//  NonBlockingOnboardingTests.swift
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

import FeatureFlags_macOS
import PrivacyConfig
@_spi(Testing) import Persistence
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class NonBlockingOnboardingTests: XCTestCase {

    func testNonBlockingDependsOnTheFeatureFlag() {
        let flags = MockFeatureFlagger()
        let onboarding = NonBlockingOnboarding(featureFlagger: flags)
        XCTAssertFalse(onboarding.isNonBlocking)

        flags.enabledFeatureFlags = [.onboardingAsync]
        XCTAssertTrue(onboarding.isNonBlocking)
    }

    @MainActor
    func testContextualInitializationSurvivesResumeAndPreservesProgressAndDismissal() {
        let store = MockKeyValueFileStore()
        let flags = MockFeatureFlagger()
        flags.enabledFeatureFlags = [.onboardingAsync]
        let onboarding = NonBlockingOnboarding(featureFlagger: flags)
        let updater = MockContextualOnboardingState()
        onboarding.initializeContextualOnboarding(updater, persistor: NonBlockingOnboardingPersistor(keyValueStore: store))
        XCTAssertEqual(updater.state, .notStarted)

        for state in [ContextualOnboardingState.ongoing, .onboardingCompleted] {
            updater.state = state
            onboarding.initializeContextualOnboarding(updater, persistor: NonBlockingOnboardingPersistor(keyValueStore: store))
            XCTAssertEqual(updater.state, state)
        }
    }

    func testOutcomeIsDurableAndCannotChangeAfterSkip() {
        let store = MockKeyValueFileStore()
        let persistor = NonBlockingOnboardingPersistor(keyValueStore: store)
        XCTAssertTrue(persistor.record(.skipped))

        let restored = NonBlockingOnboardingPersistor(keyValueStore: store)
        XCTAssertEqual(restored.outcome, .skipped)
        XCTAssertFalse(restored.record(.completed))
        XCTAssertEqual(restored.outcome, .skipped)
    }

    func testFailedOutcomeWriteDoesNotReportSuccessOrNotifyObservers() {
        let store = MockKeyValueFileStore()
        store.shouldThrowOnSet = true
        let persistor = NonBlockingOnboardingPersistor(keyValueStore: store)
        let observer = NotificationCenter.default.addObserver(forName: NonBlockingOnboardingPersistor.outcomeDidChange,
                                                              object: nil, queue: nil) { _ in
            XCTFail("A failed write must not announce a stored outcome change")
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertFalse(persistor.record(.skipped))
        XCTAssertNil(persistor.outcome)
    }

    func testExplicitResetAllowsANewOnboardingSession() {
        let persistor = NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        persistor.contextualInitialized = true
        persistor.record(.skipped)

        persistor.reset()

        XCTAssertFalse(persistor.contextualInitialized)
        XCTAssertNil(persistor.outcome)
        XCTAssertTrue(persistor.record(.completed))
    }

}
