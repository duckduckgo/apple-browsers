//
//  OnboardingPersonalizationAdBlockingTests.swift
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

import Testing
import Foundation
import Persistence
import PersistenceTestingUtils
import WebExtensionsTestSupport
@testable import DuckDuckGo

@Suite("Onboarding Personalization – YouTube Ad Blocking adapter")
struct OnboardingPersonalizationAdBlockingTests {

    private func makeAdapter(
        store: InMemoryKeyValueStore = InMemoryKeyValueStore(),
        defaultYouTubeAdBlockingEnabled: Bool = false,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> OnboardingYouTubeAdBlockingAdapter {
        OnboardingYouTubeAdBlockingAdapter(
            keyValueStore: store,
            adBlockingAvailability: MockAdBlockingAvailability(defaultYouTubeAdBlockingEnabled: defaultYouTubeAdBlockingEnabled),
            notificationCenter: notificationCenter
        )
    }

    private func storage(_ store: InMemoryKeyValueStore) -> any ThrowingKeyedStoring<YouTubeAdBlockingKeys> {
        store.throwingKeyedStoring()
    }

    // MARK: - Mapping logic

    @Test("Falls back to the default Ad Blocking setting when storage is empty", arguments: [true, false])
    func fallsBackToRolloutDefault(defaultYouTubeAdBlockingEnabled: Bool) {
        // GIVEN
        let sut = makeAdapter(defaultYouTubeAdBlockingEnabled: defaultYouTubeAdBlockingEnabled)

        // WHEN
        let result = sut.isYouTubeAdBlockingEnabled

        // THEN
        #expect(result == defaultYouTubeAdBlockingEnabled)
    }

    @Test("A stored value takes precedence over the default Ad Blocking setting")
    func storedValueWinsOverDefault() throws {
        // GIVEN
        let store = InMemoryKeyValueStore()
        try storage(store).set(false, for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled)
        let sut = makeAdapter(store: store, defaultYouTubeAdBlockingEnabled: true)

        // WHEN
        let result = sut.isYouTubeAdBlockingEnabled

        // THEN
        #expect(!result)
    }

    @available(iOS 16.0, *)
    @Test("Posts the change notification when the value changes", .timeLimit(.minutes(1)))
    func postsNotificationOnChange() async {
        // GIVEN
        let notificationCenter = NotificationCenter()
        let sut = makeAdapter(defaultYouTubeAdBlockingEnabled: false, notificationCenter: notificationCenter)

        // WHEN
        await confirmation("change notification posted") { posted in
            let token = notificationCenter.addObserver(
                forName: YouTubeAdBlockingStorageKeys.youTubeAdBlockingEnabledDidChangeNotification,
                object: nil,
                queue: nil
            ) { _ in posted() }
            defer { notificationCenter.removeObserver(token) }

            // THEN
            sut.isYouTubeAdBlockingEnabled = true // false (default) -> true, a real change
        }
    }

    @available(iOS 16.0, *)
    @Test("Setting the value it already has is a no-op: no write, no notification", .timeLimit(.minutes(1)))
    func noOpWhenValueUnchanged() async throws {
        // GIVEN
        let store = InMemoryKeyValueStore()
        let notificationCenter = NotificationCenter()
        // Ad Blocking default true + empty storage => effective value is already true.
        let sut = makeAdapter(store: store, defaultYouTubeAdBlockingEnabled: true, notificationCenter: notificationCenter)

        // WHEN
        await confirmation("no notification", expectedCount: 0) { posted in
            let token = notificationCenter.addObserver(
                forName: YouTubeAdBlockingStorageKeys.youTubeAdBlockingEnabledDidChangeNotification,
                object: nil,
                queue: nil
            ) { _ in posted() }
            defer { notificationCenter.removeObserver(token) }

            sut.isYouTubeAdBlockingEnabled = true // equals the effective value => guard skips
        }

        // THEN - No explicit choice was recorded, so it still resolves via the default (key remains absent).
        #expect(try storage(store).value(for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled) == nil)
    }

    // MARK: - Persistence round-trip

    @Test("Setting persists under the real storage key", arguments: [true, false])
    func persistsUnderRealKey(value: Bool) throws {
        // GIVEN
        let store = InMemoryKeyValueStore()
        let sut = makeAdapter(store: store, defaultYouTubeAdBlockingEnabled: !value)

        // WHEN
        sut.isYouTubeAdBlockingEnabled = value

        // THEN
        #expect(try storage(store).value(for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled) == value)
        #expect(sut.isYouTubeAdBlockingEnabled == value)
    }

    @Test("A fresh adapter over the same store reads the persisted value")
    func persistsAcrossInstances() {
        // GIVEN
        let store = InMemoryKeyValueStore()
        let sut = makeAdapter(store: store, defaultYouTubeAdBlockingEnabled: false)
        sut.isYouTubeAdBlockingEnabled = true

        // WHEN
        let fresh = makeAdapter(store: store, defaultYouTubeAdBlockingEnabled: false)

        // THEN
        #expect(fresh.isYouTubeAdBlockingEnabled == true)
    }
}
