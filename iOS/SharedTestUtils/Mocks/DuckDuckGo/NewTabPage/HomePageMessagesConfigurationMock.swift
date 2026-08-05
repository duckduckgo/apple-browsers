//
//  HomePageMessagesConfigurationMock.swift
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

import Core
import RemoteMessaging
import XCTest

@testable import DuckDuckGo

class HomePageMessagesConfigurationMock: HomePageMessagesConfiguration {
    var homeMessages: [HomeMessage]

    init(homeMessages: [HomeMessage]) {
        self.homeMessages = homeMessages
    }

    private(set) var lastAppearedHomeMessage: HomeMessage?
    private(set) var appearanceCallCount = 0
    func didAppear(_ homeMessage: HomeMessage) {
        appearanceCallCount += 1
        lastAppearedHomeMessage = homeMessage
    }

    private(set) var lastDismissedHomeMessage: HomeMessage?
    func dismissHomeMessage(_ homeMessage: HomeMessage) {
        lastDismissedHomeMessage = homeMessage
    }

    private(set) var didRefresh: Bool = false
    private(set) var refreshCallCount = 0
    private(set) var lastRefreshOpenedAfterIdle: Bool?
    func refresh(openedAfterIdle: Bool) {
        didRefresh = true
        refreshCallCount += 1
        lastRefreshOpenedAfterIdle = openedAfterIdle
    }
}
