//
//  DuckAiVoiceChatShieldScopeTests.swift
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

import FeatureFlags
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DuckAiVoiceChatShieldScopeTests: XCTestCase {

    private var flagger: MockFeatureFlagger!
    private let duckAiHost = URL.duckAi.host!

    override func setUp() {
        super.setUp()
        flagger = MockFeatureFlagger()
    }

    override func tearDown() {
        flagger = nil
        super.tearDown()
    }

    private func isOnlyMicInPlay(
        domain: String = "duck.ai",
        used: Permissions = Permissions(),
        persisted: [PermissionType] = [],
        aiChatHost: String? = "duck.ai"
    ) -> Bool {
        DuckAiVoiceChatShieldScope.isOnlyMicInPlay(
            domain: domain,
            usedPermissions: used,
            persistedPermissionTypes: persisted,
            featureFlagger: flagger,
            aiChatHost: aiChatHost
        )
    }

    // MARK: - Flag gates the predicate

    func testWhenFlagOffThenReturnsFalseEvenOnDuckAiWithOnlyMic() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = false
        var used = Permissions()
        used[.microphone] = .active

        XCTAssertFalse(isOnlyMicInPlay(used: used))
    }

    func testWhenFlagAbsentFromStubThenReturnsFalse() {
        // MockFeatureFlagger returns `false` for unknown keys; this guards the contract.
        XCTAssertFalse(isOnlyMicInPlay())
    }

    // MARK: - Domain scoping

    func testWhenDomainIsNotAiChatHostThenReturnsFalse() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true

        XCTAssertFalse(isOnlyMicInPlay(domain: "example.com"))
        XCTAssertFalse(isOnlyMicInPlay(domain: "duckduckgo.com"))
    }

    func testWhenAIChatHostIsNilThenReturnsFalse() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true

        XCTAssertFalse(isOnlyMicInPlay(aiChatHost: nil))
    }

    // MARK: - Positive cases (only mic, or nothing)

    func testWhenFlagOnAndDuckAiAndNoPermissionsThenReturnsTrue() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true

        XCTAssertTrue(isOnlyMicInPlay())
    }

    func testWhenFlagOnAndDuckAiAndOnlyMicUsedThenReturnsTrue() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        var used = Permissions()
        used[.microphone] = .active

        XCTAssertTrue(isOnlyMicInPlay(used: used))
    }

    func testWhenFlagOnAndDuckAiAndOnlyMicPersistedThenReturnsTrue() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true

        XCTAssertTrue(isOnlyMicInPlay(persisted: [.microphone]))
    }

    func testWhenFlagOnAndDuckAiAndMicUsedAndPersistedThenReturnsTrue() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        var used = Permissions()
        used[.microphone] = .active

        XCTAssertTrue(isOnlyMicInPlay(used: used, persisted: [.microphone]))
    }

    // MARK: - Non-mic permissions block the short-circuit

    func testWhenNonMicPermissionUsedThenReturnsFalse() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        var used = Permissions()
        used[.notification] = .active

        XCTAssertFalse(isOnlyMicInPlay(used: used))
    }

    func testWhenNonMicPermissionPersistedThenReturnsFalse() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true

        XCTAssertFalse(isOnlyMicInPlay(persisted: [.notification]))
    }

    /// Guards the click-routing regression: with OS mic denied AND another permission in
    /// play, the predicate must return `false` so the shield-click reaches the Permission
    /// Center instead of being short-circuited to the OS-disabled mic popover.
    func testWhenMicPlusNonMicInPlayThenReturnsFalse() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        var used = Permissions()
        used[.microphone] = .active
        used[.notification] = .active

        XCTAssertFalse(isOnlyMicInPlay(used: used, persisted: [.microphone, .notification]))
    }

    func testWhenAnyExternalSchemePersistedThenReturnsFalse() {
        flagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true

        XCTAssertFalse(isOnlyMicInPlay(persisted: [.externalScheme(scheme: "zoom")]))
    }
}
