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
import BrowserServicesKitTestsUtils
import Subscription
@testable import DuckDuckGo
import UIKit

struct AIChatViewControllerManagerTests {
    
    // MARK: - Helper Methods
    private var delegate = MockAIChatViewControllerManagerDelegate()
    private func createManager(
        downloadsDirectoryHandler: MockDownloadsDirectoryHandler = MockDownloadsDirectoryHandler()) -> AIChatViewControllerManager {
        let manager = AIChatViewControllerManager(
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>().eraseToAnyPublisher(),
            downloadsDirectoryHandler: downloadsDirectoryHandler,
            userAgentManager: MockUserAgentManager(privacyConfig: MockPrivacyConfiguration()),
            experimentalAIChatManager: ExperimentalAIChatManager(),
            featureFlagger: MockFeatureFlagger(),
            featureDiscovery: MockFeatureDiscovery(),
            aiChatSettings: MockAIChatSettingsProvider(),
            productSurfaceTelemetry: MockProductSurfaceTelemetry()
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

    @Test("Account sign out notification triggers session invalidation", .disabled("Flaky test - https://app.asana.com/1/137249556945/project/414709148257752/task/1210784601649460?focus=true"))
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

    // MARK: - Container Presentation Tests

    @Test("Opening in container adds as child view controller")
    @MainActor
    func testOpeningInContainerAddsAsChildViewController() async throws {
        // Given
        let manager = createManager()
        let mockParentViewController = createMockViewController()
        let mockContainerView = MockContainerView()

        // When
        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()

        // Then
        #expect(manager.chatViewController != nil)
        #expect(mockParentViewController.addedChildCount == 1)
    }

    @Test("Opening in container adds view as subview to container")
    @MainActor
    func testOpeningInContainerAddsViewAsSubview() async throws {
        // Given
        let manager = createManager()
        let mockParentViewController = createMockViewController()
        let mockContainerView = MockContainerView()

        // When
        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()

        // Then
        #expect(manager.chatViewController != nil)
        #expect(mockContainerView.subviews.count == 1)
    }

    @Test("Opening in container applies layout constraints")
    @MainActor
    func testOpeningInContainerApplesLayoutConstraints() async throws {
        // Given
        let manager = createManager()
        let mockParentViewController = createMockViewController()
        let mockContainerView = MockContainerView()

        // When
        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()

        // Then
        guard let chatVC = manager.chatViewController else {
            Issue.record("Chat view controller not created")
            return
        }

        #expect(chatVC.view.translatesAutoresizingMaskIntoConstraints == false)
        #expect(chatVC.view.superview === mockContainerView)
    }

    @Test("Container completion callback is called")
    @MainActor
    func testContainerCompletionCallbackIsCalled() async throws {
        // Given
        let manager = createManager()
        let mockParentViewController = createMockViewController()
        let mockContainerView = MockContainerView()
        var completionCalled = false

        // When
        manager.openAIChatInContainer(
            in: mockContainerView,
            parentViewController: mockParentViewController
        ) {
            completionCalled = true
        }
        await waitForTaskProcessing()

        // Then
        #expect(completionCalled)
    }

    @Test("Opening in container twice reuses same view controller")
    @MainActor
    func testOpeningInContainerTwiceReusesTheSameViewController() async throws {
        // Given
        let manager = createManager()
        let mockParentViewController = createMockViewController()
        let mockContainerView = MockContainerView()

        // When
        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()
        let firstViewController = manager.chatViewController

        // When (again)
        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()

        // Then
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController === firstViewController)
    }

    // MARK: - Container Session Invalidation Tests

    @Test("Account sign in notification triggers session invalidation in container")
    @MainActor
    func testAccountSignInTriggersSessionInvalidationInContainer() async throws {
        // Given
        let manager = createManager()
        let mockParentViewController = createMockViewController()
        let mockContainerView = MockContainerView()

        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()
        let firstViewController = manager.chatViewController

        // When
        NotificationCenter.default.post(
            name: .accountDidSignIn,
            object: nil,
            userInfo: nil
        )
        await waitForTaskProcessing()

        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()

        // Then
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController !== firstViewController)
    }

    @Test("Subscription change triggers session invalidation in container")
    @MainActor
    func testSubscriptionChangeTriggersSessionInvalidationInContainer() async throws {
        // Given
        let manager = createManager()
        let mockParentViewController = createMockViewController()
        let mockContainerView = MockContainerView()

        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()
        let firstViewController = manager.chatViewController

        // When
        NotificationCenter.default.post(
            name: .subscriptionDidChange,
            object: nil,
            userInfo: nil
        )
        await waitForTaskProcessing()

        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()

        // Then
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController !== firstViewController)
    }

    // MARK: - Query/Payload Cleanup Tests

    @Test("Query triggers session cleanup in modal mode")
    @MainActor
    func testQueryTriggersSessionCleanupInModalMode() async throws {
        // Given
        let manager = createManager()
        let mockViewController = createMockViewController()

        manager.openAIChat(on: mockViewController)
        await waitForTaskProcessing()
        let firstViewController = manager.chatViewController

        // When
        manager.openAIChat("test query", on: mockViewController)
        await waitForTaskProcessing()

        // Then
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController !== firstViewController)
    }

    @Test("Query triggers session cleanup in container mode")
    @MainActor
    func testQueryTriggersSessionCleanupInContainerMode() async throws {
        // Given
        let manager = createManager()
        let mockParentViewController = createMockViewController()
        let mockContainerView = MockContainerView()

        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()
        let firstViewController = manager.chatViewController

        // When
        manager.openAIChatInContainer("test query", in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()

        // Then
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController !== firstViewController)
    }

    @Test("Payload triggers session cleanup in modal mode")
    @MainActor
    func testPayloadTriggersSessionCleanupInModalMode() async throws {
        // Given
        let manager = createManager()
        let mockViewController = createMockViewController()

        manager.openAIChat(on: mockViewController)
        await waitForTaskProcessing()
        let firstViewController = manager.chatViewController

        // When
        manager.openAIChat(payload: ["key": "value"], on: mockViewController)
        await waitForTaskProcessing()

        // Then
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController !== firstViewController)
    }

    @Test("Payload triggers session cleanup in container mode")
    @MainActor
    func testPayloadTriggersSessionCleanupInContainerMode() async throws {
        // Given
        let manager = createManager()
        let mockParentViewController = createMockViewController()
        let mockContainerView = MockContainerView()

        manager.openAIChatInContainer(in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()
        let firstViewController = manager.chatViewController

        // When
        manager.openAIChatInContainer(payload: ["key": "value"], in: mockContainerView, parentViewController: mockParentViewController)
        await waitForTaskProcessing()

        // Then
        #expect(manager.chatViewController != nil)
        #expect(firstViewController != nil)
        #expect(manager.chatViewController !== firstViewController)
    }

    @Test("Presenting AI Chat view controller does not create downloads directory")
    @MainActor
    func testPresentAIChatViewController_DoesNotCreateDownloadsDirectory() async throws {
        // Given
        let mockDownloadsHandler = MockDownloadsDirectoryHandler()
        let manager = createManager(downloadsDirectoryHandler: mockDownloadsHandler)
        let mockViewController = createMockViewController()
        
        // When
        manager.openAIChat(on: mockViewController)

        // Then
        #expect(mockDownloadsHandler.createDownloadsDirectoryIfNeededCallCount == 0,
                      "Downloads directory should not be created when presenting AI Chat")
    }
    
    @Test("AI Chat will start download creates downloads directory")
    @MainActor
    func testAIChatViewControllerWillStartDownload_CreatesDownloadsDirectory() async throws {
        // Given
        let mockDownloadsHandler = MockDownloadsDirectoryHandler()
        let manager = createManager(downloadsDirectoryHandler: mockDownloadsHandler)
        let mockViewController = createMockViewController()
                
        // When
        manager.openAIChat(on: mockViewController)
        manager.aiChatViewControllerWillStartDownload()

        // Then
        #expect(mockDownloadsHandler.createDownloadsDirectoryIfNeededCallCount == 1,
                      "Downloads directory should be created when download starts")
    }
}

// MARK: - Mock UIViewController for Testing

private class MockUIViewController: UIViewController {
    var presentedViewControllerForTest: UIViewController?
    var presentCallCount = 0
    var addedChildCount = 0

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentedViewControllerForTest = viewControllerToPresent
        presentCallCount += 1
        completion?()
    }

    override func addChild(_ childViewController: UIViewController) {
        super.addChild(childViewController)
        addedChildCount += 1
    }
}

private class MockContainerView: UIView {
    // Simple mock view for testing container embedding
}

private final class MockDownloadsDirectoryHandler: DownloadsDirectoryHandling {
    
    var createDownloadsDirectoryIfNeededCallCount: Int = 0

    var downloadsDirectoryFiles: [URL] = []
    var downloadsDirectory: URL = URL(string: "/tmp/downloads")!

    func downloadsDirectoryExists() -> Bool {
        return false
    }

    func createDownloadsDirectory() {}

    func createDownloadsDirectoryIfNeeded() {
        createDownloadsDirectoryIfNeededCallCount += 1
    }
    
    func deleteDownloadsDirectoryIfEmpty() {}
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
