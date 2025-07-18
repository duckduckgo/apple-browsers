//
//  UIInteractionManagerTests.swift
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

import Foundation
import Testing
@testable import DuckDuckGo

final class MockAuthenticationService: AuthenticationServiceProtocol {

    var authenticateCalled = false
    var authenticationCallback: (() async -> Void)?

    func authenticate() async {
        authenticateCalled = true
        await authenticationCallback?()
    }

}

final class MockAutoClearService: AutoClearServiceProtocol {

    var isClearingEnabled: Bool = true
    var autoClearTask: Task<Void, Never>?

    var waitForDataClearedCalled = false
    var clearDataCallback: (() async -> Void)?

    func waitForDataCleared() async {
        waitForDataClearedCalled = true
        await clearDataCallback?()
    }

}

final class MockLaunchActionHandler: LaunchActionHandling {

    var handleLaunchActionCalled = false
    var lastHandledLaunchAction: LaunchAction?

    func handleLaunchAction(_ action: LaunchAction) {
        handleLaunchActionCalled = true
        lastHandledLaunchAction = action
    }

}

@MainActor
final class UIInteractionManagerTests {

    let mockAuthService = MockAuthenticationService()
    let mockAutoClearService = MockAutoClearService()
    let mockLaunchActionHandler = MockLaunchActionHandler()
    lazy var uiInteractionManager = UIInteractionManager(
        authenticationService: mockAuthService,
        autoClearService: mockAutoClearService,
        launchActionHandler: mockLaunchActionHandler
    )

    @Test("Start method calls onWebViewReadyForInteractions and opens URL")
    func startCallsOnWebViewReadyForInteractionsAndOpensURL() async {
        await withCheckedContinuation { continuation in
            uiInteractionManager.start(
                launchAction: .openURL(URL("www.duckduckgo.com")!),
                onWebViewReadyForInteractions: {
                    #expect(self.mockAutoClearService.waitForDataClearedCalled)
                    #expect(self.mockLaunchActionHandler.handleLaunchActionCalled)
                    continuation.resume()
                },
                onAppReadyForInteractions: { }
            )
        }
    }

    @Test("Start method calls onWebViewReadyForInteractions and does not show keyboard unless authentication happened")
    func startCallsOnWebViewReadyForInteractionsAndDoesNotShowKeyboard() async {
        await withCheckedContinuation { continuation in
            uiInteractionManager.start(
                launchAction: .showKeyboard(nil),
                onWebViewReadyForInteractions: {
                    #expect(self.mockAutoClearService.waitForDataClearedCalled)
                    #expect(!self.mockLaunchActionHandler.handleLaunchActionCalled)
                    continuation.resume()
                },
                onAppReadyForInteractions: { }
            )
        }
    }

    @Test("Start method calls onAppReadyForInteractions")
    func startCallsOnAppReadyForInteractions() async {
        await withCheckedContinuation { continuation in
            uiInteractionManager.start(
                launchAction: .showKeyboard(nil),
                onWebViewReadyForInteractions: {
                    #expect(!self.mockLaunchActionHandler.handleLaunchActionCalled)
                },
                onAppReadyForInteractions: {
                    #expect(self.mockAutoClearService.waitForDataClearedCalled)
                    #expect(self.mockAuthService.authenticateCalled)
                    #expect(self.mockLaunchActionHandler.handleLaunchActionCalled)
                    continuation.resume()
                }
            )
        }
    }

}
