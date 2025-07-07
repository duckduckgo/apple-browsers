//
//  AIChatViewControllerManagerTests.swift
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
import Foundation
import Combine
import BrowserServicesKit
import Subscription
@testable import DuckDuckGo
import UIKit

struct AIChatViewControllerManagerTests {
    
    // MARK: - Helper Methods
    private var delegate = MockAIChatViewControllerManagerDelegate()
    private func createManager() -> AIChatViewControllerManager {
        let manager = AIChatViewControllerManager(
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            downloadsDirectoryHandler: MockDownloadsDirectoryHandler(),
            userAgentManager: MockUserAgentManager(privacyConfig: MockPrivacyConfiguration()),
            experimentalAIChatManager: ExperimentalAIChatManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatSettings: MockAIChatSettingsProvider()
        )

        manager.delegate = delegate
        return manager
    }
    
    @MainActor
    private func createMockViewController() -> MockUIViewController {
        return MockUIViewController()
    }
    
    private func waitForTaskProcessing() async {
        // Allow time for processing on main queue
        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    @Test("When no notification triggers view controller not updated")
    @MainActor
    func testOpeningAIChatTwiceReusesTheSameViewController() async throws {
        let manager = createManager()
        let mockViewController = createMockViewController()

        // First, establish an AI chat session
        manager.openAIChat(on: mockViewController)
        await waitForTaskProcessing()
        let firstViewController = manager.chatViewController

        // Open AI chat again - should use the same view controller
        manager.openAIChat(on: mockViewController)
        await waitForTaskProcessing()

        // Verify the session invalidation was triggered by account sign in
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController === firstViewController)
    }

    @Test("Account sign in notification triggers session invalidation")
    @MainActor
    func testAccountSignInTriggersSessionInvalidation() async throws {
        let manager = createManager()
        let mockViewController = createMockViewController()
        
        // First, establish an AI chat session
        manager.openAIChat(on: mockViewController)
        await waitForTaskProcessing()

        let firstViewController = manager.chatViewController
        // Simulate user signing in to their account
        NotificationCenter.default.post(
            name: .accountDidSignIn,
            object: nil,
            userInfo: nil
        )
        await waitForTaskProcessing()

        // Open AI chat again - session should be invalidated due to account sign in
        manager.openAIChat(on: mockViewController)
        await waitForTaskProcessing()

        // Verify the session invalidation was triggered by account sign in
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController !== firstViewController)
    }

    @Test("Account sign out notification triggers session invalidation")
    @MainActor
    func testAccountSignOutTriggersSessionInvalidation() async throws {
        let manager = createManager()
        let mockViewController = createMockViewController()

        // First, establish an AI chat session
        manager.openAIChat(on: mockViewController)
        await waitForTaskProcessing()

        let firstViewController = manager.chatViewController
        // Simulate user signing in to their account
        NotificationCenter.default.post(
            name: .accountDidSignOut,
            object: nil,
            userInfo: nil
        )
        await waitForTaskProcessing()

        // Open AI chat again - session should be invalidated due to account sign in
        manager.openAIChat(on: mockViewController)
        await waitForTaskProcessing()

        // Verify the session invalidation was triggered by account sign in
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController !== firstViewController)
    }

    @Test("Subscription Did Change notification triggers session invalidation")
    @MainActor
    func testSubscriptionDidChangeTriggersSessionInvalidation() async throws {
        let manager = createManager()
        let mockViewController = createMockViewController()

        // First, establish an AI chat session
        manager.openAIChat(on: mockViewController)
        await waitForTaskProcessing()

        let firstViewController = manager.chatViewController
        // Simulate user signing in to their account
        NotificationCenter.default.post(
            name: .subscriptionDidChange,
            object: nil,
            userInfo: nil
        )
        await waitForTaskProcessing()

        // Open AI chat again - session should be invalidated due to account sign in
        manager.openAIChat(on: mockViewController)
        await waitForTaskProcessing()

        // Verify the session invalidation was triggered by account sign in
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController !== firstViewController)
    }

}

// MARK: - Mock UIViewController for Testing

private class MockUIViewController: UIViewController {
    var presentedViewControllerForTest: UIViewController?
    var presentCallCount = 0

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentedViewControllerForTest = viewControllerToPresent
        presentCallCount += 1
        completion?()
    }
}

private final class MockDownloadsDirectoryHandler: DownloadsDirectoryHandling {
    var downloadsDirectoryFiles: [URL] = []

    func downloadsDirectoryExists() -> Bool {
        return false
    }

    func createDownloadsDirectory() {
    }

    var downloadsDirectory: URL = URL(string: "/tmp/downloads")!
    func createDownloadsDirectoryIfNeeded() {}
}

private final class MockAIChatViewControllerManagerDelegate: AIChatViewControllerManagerDelegate {
    var loadedURL: URL?
    var downloadFileName: String?
    var didReceiveOpenSettingsRequest: Bool = false
    var submittedQuery: String?

    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didRequestToLoad url: URL) {
        loadedURL = url
    }

    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didRequestOpenDownloadWithFileName fileName: String) {
        downloadFileName = fileName
    }

    func aiChatViewControllerManagerDidReceiveOpenSettingsRequest(_ manager: AIChatViewControllerManager) {
        didReceiveOpenSettingsRequest = true
    }

    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didSubmitQuery query: String) {
        submittedQuery = query
    }
}
