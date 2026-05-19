//
//  HomePageConfigurationTests.swift
//  DuckDuckGo
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
import RemoteMessaging
import RemoteMessagingTestsUtils
@testable import DuckDuckGo

struct HomePageConfigurationTests {

    @Test("Check Home Page Configuration Fetches Remote Messages With NewTabPage Surface")
    func checkFetchRemoteMessagesWithTheRightSurface() async throws {
        // GIVEN
        let storeMock = MockRemoteMessagingStore()

        // WHEN
        let sut = HomePageConfiguration(variantManager: nil, remoteMessagingStore: storeMock, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })

        // THEN
        #expect(storeMock.fetchScheduledRemoteMessageCalls == 1)
        #expect(storeMock.capturedSurfaces == .newTabPage)

        // GIVEN
        storeMock.fetchScheduledRemoteMessageCalls = 0
        storeMock.capturedSurfaces = nil

        // WHEN
        sut.refresh()

        // THEN
        #expect(storeMock.fetchScheduledRemoteMessageCalls == 1)
        #expect(storeMock.capturedSurfaces == .newTabPage)
    }

    @available(iOS 16, *)
    @Test("When refreshed after idle and an idle message exists, triggerFilter is .specific(.afterIdle)", .timeLimit(.minutes(1)))
    func refreshAfterIdleWithIdleMessageAvailable() {
        // GIVEN
        let storeMock = MockRemoteMessagingStore()
        storeMock.scheduledRemoteMessage = RemoteMessageModel(
            id: "idle-msg", surfaces: .newTabPage, content: nil, matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        let sut = HomePageConfiguration(variantManager: nil, remoteMessagingStore: storeMock, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        storeMock.capturedTriggerFilter = nil

        // WHEN
        sut.refresh(openedAfterIdle: true)

        // THEN
        #expect(storeMock.capturedTriggerFilter == .specific(.afterIdle))
    }

    @available(iOS 16, *)
    @Test("When refreshed after idle and no idle message exists, falls back to .noTrigger", .timeLimit(.minutes(1)))
    func refreshAfterIdleFallsBackToNoTrigger() {
        // GIVEN
        let storeMock = MockRemoteMessagingStore()
        let sut = HomePageConfiguration(variantManager: nil, remoteMessagingStore: storeMock, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        storeMock.capturedTriggerFilter = nil

        // WHEN
        sut.refresh(openedAfterIdle: true)

        // THEN — no idle message found, so it falls back to .noTrigger
        #expect(storeMock.capturedTriggerFilter == .noTrigger)
    }

    @available(iOS 16, *)
    @Test("When refreshed with openedAfterIdle false, triggerFilter is .noTrigger", .timeLimit(.minutes(1)))
    func refreshWithOpenedAfterIdleFalsePassesNoTrigger() {
        // GIVEN
        let storeMock = MockRemoteMessagingStore()
        let sut = HomePageConfiguration(variantManager: nil, remoteMessagingStore: storeMock, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        storeMock.capturedTriggerFilter = nil

        // WHEN
        sut.refresh(openedAfterIdle: false)

        // THEN
        #expect(storeMock.capturedTriggerFilter == .noTrigger)
    }

    @available(iOS 16, *)
    @Test("When refreshed without parameter, triggerFilter is .noTrigger (backward compat)", .timeLimit(.minutes(1)))
    func refreshWithoutParameterPassesNoTrigger() {
        // GIVEN
        let storeMock = MockRemoteMessagingStore()
        let sut = HomePageConfiguration(variantManager: nil, remoteMessagingStore: storeMock, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        storeMock.capturedTriggerFilter = nil

        // WHEN
        sut.refresh()

        // THEN
        #expect(storeMock.capturedTriggerFilter == .noTrigger)
    }

}
