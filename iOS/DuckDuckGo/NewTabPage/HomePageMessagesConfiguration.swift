//
//  HomePageMessagesConfiguration.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation

struct HomeMessagePresentationContext: Hashable {
    let messageID: String
    let acquisitionIdentity: PromoQueueAcquisitionIdentity
}

@MainActor
protocol HomePageMessagesConfiguration {
    var homeMessages: [HomeMessage] { get }
    var mode: PromoCoordinationMode { get }
    var contentDidChangePublisher: AnyPublisher<Void, Never> { get }

    func refresh(openedAfterIdle: Bool)
    func prepareForNTP(openedAfterIdle: Bool)
    func handleAppBackgrounded()
    func handleAppForegrounded()
    func presentationContext(for homeMessage: HomeMessage) -> HomeMessagePresentationContext?
    
    func dismissHomeMessage(_ homeMessage: HomeMessage) async
    func dismissHomeMessage(_ homeMessage: HomeMessage, presentationContext: HomeMessagePresentationContext?) async
    func didAppear(_ homeMessage: HomeMessage)
    func didAppear(_ homeMessage: HomeMessage, presentationContext: HomeMessagePresentationContext?)
}

extension HomePageMessagesConfiguration {
    var mode: PromoCoordinationMode {
        .legacy
    }

    var contentDidChangePublisher: AnyPublisher<Void, Never> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    func refresh() {
        refresh(openedAfterIdle: false)
    }

    func prepareForNTP(openedAfterIdle: Bool) {
        refresh(openedAfterIdle: openedAfterIdle)
    }

    func handleAppBackgrounded() {}

    func handleAppForegrounded() {}

    func presentationContext(for homeMessage: HomeMessage) -> HomeMessagePresentationContext? {
        nil
    }

    func dismissHomeMessage(_ homeMessage: HomeMessage, presentationContext: HomeMessagePresentationContext?) async {
        await dismissHomeMessage(homeMessage)
    }

    func didAppear(_ homeMessage: HomeMessage, presentationContext: HomeMessagePresentationContext?) {
        didAppear(homeMessage)
    }
}
