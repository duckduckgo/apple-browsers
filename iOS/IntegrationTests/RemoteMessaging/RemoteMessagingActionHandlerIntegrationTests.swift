//
//  RemoteMessagingActionHandlerIntegrationTests.swift
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
import Foundation
@testable import DuckDuckGo

@Suite("RMF - Remote Action Handling - Integration Tests")
struct RemoteMessagingActionHandlerIntegrationTests {

    @Test(
        "Check Navigation Target Asks Delegate To Perform Segue",
        arguments: [
            (.appearance, \MockMessageNavigationDelegate.didCallSegueToSettingsAppearance),
            (.sync, \MockMessageNavigationDelegate.didCallSegueToSettingsSync),
            (.settings, \MockMessageNavigationDelegate.didCallSegueToSettings),
            (.duckAISettings, \MockMessageNavigationDelegate.didCallSegueToAIChatSettings),
            (.feedback, \MockMessageNavigationDelegate.didCallSegueToFeedback),
        ] as [(NavigationTarget, KeyPath<MockMessageNavigationDelegate, Bool>)]

    )
    func navigationActionHandlesDifferentTargets(navigationTarget: NavigationTarget, keyPath: KeyPath<MockMessageNavigationDelegate, Bool>) async throws {
        // GIVEN
        let mockMessageNavigationDelegate = MockMessageNavigationDelegate()
        let mockPresenter = MockRemoteMessagingPresenter()
        let sut = RemoteMessagingActionHandler()
        sut.messageNavigator = DefaultMessageNavigator(delegate: mockMessageNavigationDelegate)
        #expect(!mockMessageNavigationDelegate[keyPath: keyPath])
        // WHEN
        await sut.handleAction(.navigation(value: navigationTarget), context: .init(presenter: mockPresenter, presentationStyle: .dismissModalsAndPresentFromRoot))

        // THEN
        #expect(mockMessageNavigationDelegate[keyPath: keyPath])
    }

    @Test(
        "Check Navigation Passes Presentation Style To Delegate",
        arguments:
            [.sync, .settings, .duckAISettings, .feedback, .importPasswords] as [NavigationTarget],
            [.dismissModalsAndPresentFromRoot, .withinCurrentContext] as [PresentationContext.Style]
    )
    func navigationActionPassesPresentationStyleToDelegate(navigationTarget: NavigationTarget, presentationStyle: PresentationContext.Style) async throws {
        // GIVEN
        let mockMessageNavigationDelegate = MockMessageNavigationDelegate()
        let mockPresenter = MockRemoteMessagingPresenter()
        let sut = RemoteMessagingActionHandler()
        sut.messageNavigator = DefaultMessageNavigator(delegate: mockMessageNavigationDelegate)

        // WHEN
        await sut.handleAction(.navigation(value: navigationTarget), context: .init(presenter: mockPresenter, presentationStyle: presentationStyle))

        // THEN
        #expect(mockMessageNavigationDelegate.capturedPresentationStyle == presentationStyle)
    }

}
