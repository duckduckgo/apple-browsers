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

}
