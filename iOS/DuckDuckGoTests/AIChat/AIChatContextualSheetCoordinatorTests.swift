//
//  AIChatContextualSheetCoordinatorTests.swift
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

import XCTest
import AIChat
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import Combine
import WebKit
@testable import DuckDuckGo

final class AIChatContextualSheetCoordinatorTests: XCTestCase {

    // MARK: - Mocks

    private final class MockPageContextHandler: AIChatPageContextHandling {
        var triggerContextCollectionCallCount = 0
        var lastTriggerContextCollectionTrigger: PageContextExtractionTrigger?
        var triggerContextCollectionReturnValue = true
        var clearCallCount = 0
        var clearAttachedContextCallCount = 0
        var resubscribeCallCount = 0
        var onTriggerContextCollection: (() -> Void)?

        private let contextSubject = CurrentValueSubject<AIChatPageContext?, Never>(nil)
        var contextPublisher: AnyPublisher<AIChatPageContext?, Never> {
            contextSubject.eraseToAnyPublisher()
        }

        func sendContext(_ context: AIChatPageContext?) {
            contextSubject.send(context)
        }

        var isCurrentPageAttachableReturnValue = true
        var reportAttachabilityMeasurementCallCount = 0
        var lastReportAttachabilityMeasurementTrigger: PageContextExtractionTrigger?

        func triggerContextCollection(trigger: PageContextExtractionTrigger) -> Bool {
            triggerContextCollectionCallCount += 1
            lastTriggerContextCollectionTrigger = trigger
            onTriggerContextCollection?()
            return triggerContextCollectionReturnValue
        }

        func isCurrentPageAttachable() -> Bool {
            isCurrentPageAttachableReturnValue
        }

        func reportAttachabilityMeasurement(trigger: PageContextExtractionTrigger) {
            reportAttachabilityMeasurementCallCount += 1
            lastReportAttachabilityMeasurementTrigger = trigger
        }

        func clear() {
            clearCallCount += 1
            contextSubject.send(nil)
        }

        func resubscribe() {
            resubscribeCallCount += 1
        }

        func clearAttachedContext() {
            clearAttachedContextCallCount += 1
            contextSubject.send(nil)
        }
    }

    private final class MockDelegate: AIChatContextualSheetCoordinatorDelegate {
        var didRequestToLoadURLs: [URL] = []
        var didRequestExpandURLs: [URL] = []
        var openSettingsCallCount = 0
        var openSyncSettingsCallCount = 0

        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestToLoad url: URL) {
            didRequestToLoadURLs.append(url)
        }

        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestExpandWithURL url: URL) {
            didRequestExpandURLs.append(url)
        }

        var viewAllChatsCallCount = 0

        func aiChatContextualSheetCoordinatorDidRequestViewAllChats(_ coordinator: AIChatContextualSheetCoordinator) {
            viewAllChatsCallCount += 1
        }

        func aiChatContextualSheetCoordinatorDidRequestOpenSettings(_ coordinator: AIChatContextualSheetCoordinator) {
            openSettingsCallCount += 1
        }

        func aiChatContextualSheetCoordinatorDidRequestOpenSyncSettings(_ coordinator: AIChatContextualSheetCoordinator) {
            openSyncSettingsCallCount += 1
        }

        var contextualChatURLUpdates: [URL?] = []

        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didUpdateContextualChatURL url: URL?) {
            contextualChatURLUpdates.append(url)
        }

        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestOpenDownloadWithFileName fileName: String) {
        }

        var deletedChatIDs: [String] = []

        func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestDeleteChatWithID chatID: String) {
            deletedChatIDs.append(chatID)
        }

        var newVoiceChatCallCount = 0

        func aiChatContextualSheetCoordinatorDidRequestNewVoiceChat(_ coordinator: AIChatContextualSheetCoordinator) {
            newVoiceChatCallCount += 1
        }
    }

    private final class MockPresentingViewController: UIViewController {
        var presentedVC: UIViewController?
        var presentAnimated: Bool?
        var presentCallCount = 0

        override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
            presentedVC = viewControllerToPresent
            presentAnimated = flag
            presentCallCount += 1
            completion?()
        }
    }

    // MARK: - Properties

    private var sut: AIChatContextualSheetCoordinator!
    private var mockDelegate: MockDelegate!
    private var mockPresentingVC: MockPresentingViewController!
    private var mockSettings: MockAIChatSettingsProvider!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockUnifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider!
    private var mockPageContextHandler: MockPageContextHandler!
    private var contentBlockingSubject: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>!
    private var originatingTabURLSubject: CurrentValueSubject<URL?, Never>!
    private var didFinishTabURLSubject: CurrentValueSubject<URL?, Never>!
    private var cancellables: Set<AnyCancellable>!

    // MARK: - Setup

    @MainActor
    override func setUp() {
        super.setUp()
        mockSettings = MockAIChatSettingsProvider()
        mockFeatureFlagger = MockFeatureFlagger()
        mockUnifiedToggleInputFeature = MockUnifiedToggleInputFeatureProvider()
        mockPageContextHandler = MockPageContextHandler()
        contentBlockingSubject = PassthroughSubject<ContentBlockingUpdating.NewContent, Never>()
        originatingTabURLSubject = CurrentValueSubject<URL?, Never>(nil)
        didFinishTabURLSubject = CurrentValueSubject<URL?, Never>(nil)
        sut = AIChatContextualSheetCoordinator(
            voiceSearchHelper: MockVoiceSearchHelper(),
            aiChatSettings: mockSettings,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: contentBlockingSubject.eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: mockFeatureFlagger,
            unifiedToggleInputFeature: mockUnifiedToggleInputFeature,
            pageContextHandler: mockPageContextHandler,
            tabURLPublishers: AIChatTabURLPublishers(
                originating: originatingTabURLSubject.eraseToAnyPublisher(),
                didFinish: didFinishTabURLSubject.eraseToAnyPublisher()
            )
        )
        mockDelegate = MockDelegate()
        mockPresentingVC = MockPresentingViewController()
        sut.delegate = mockDelegate
        cancellables = []
    }

    @MainActor
    override func tearDown() {
        sut = nil
        mockDelegate = nil
        mockPresentingVC = nil
        mockSettings = nil
        mockFeatureFlagger = nil
        mockUnifiedToggleInputFeature = nil
        mockPageContextHandler = nil
        contentBlockingSubject = nil
        originatingTabURLSubject = nil
        didFinishTabURLSubject = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - presentSheet Tests

    @MainActor
    func testPresentSheetCreatesNewSheetWhenNoneExists() async {
        // Given
        XCTAssertNil(sut.sheetViewController)

        // When
        await sut.presentSheet(from: mockPresentingVC)

        // Then
        XCTAssertNotNil(sut.sheetViewController)
        XCTAssertTrue(mockPresentingVC.presentedVC is AIChatContextualSheetViewController)
        XCTAssertEqual(mockPresentingVC.presentAnimated, true)
    }

    @MainActor
    func testPresentSheetReusesExistingSheet() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        let firstSheet = sut.sheetViewController

        // When
        await sut.presentSheet(from: mockPresentingVC)
        let secondSheet = sut.sheetViewController

        // Then
        XCTAssertTrue(firstSheet === secondSheet)
    }

    @MainActor
    func testPresentSheetSetsItselfAsSheetDelegate() async {
        // When
        await sut.presentSheet(from: mockPresentingVC)

        // Then
        XCTAssertNotNil(sut.sheetViewController?.delegate)
    }

    @MainActor
    func testPresentSheetMeasuresAttachabilityWhenNoCollectionTriggered() async {
        // Auto-attach off + suggested prompts off (defaults) → no collection → attachability still measured.
        await sut.presentSheet(from: mockPresentingVC)

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)
        XCTAssertEqual(mockPageContextHandler.reportAttachabilityMeasurementCallCount, 1)
        XCTAssertEqual(mockPageContextHandler.lastReportAttachabilityMeasurementTrigger, .navigation)
    }

    @MainActor
    func testURLChangeRefreshesQuickActionsForAttachability() async {
        // Covers back/forward navigation: the URL-change (originating) signal must refresh affordances,
        // not just `didFinish` (which cached back-navigations may not fire).
        await sut.presentSheet(from: mockPresentingVC)
        XCTAssertEqual(sut.sessionState.viewState.quickActions, [.askAboutPage])

        mockPageContextHandler.isCurrentPageAttachableReturnValue = false
        originatingTabURLSubject.send(URL(string: "https://example.com/image.png"))
        XCTAssertEqual(sut.sessionState.viewState.quickActions, [])

        mockPageContextHandler.isCurrentPageAttachableReturnValue = true
        originatingTabURLSubject.send(URL(string: "https://duckduckgo.com/?q=cats"))
        XCTAssertEqual(sut.sessionState.viewState.quickActions, [.askAboutPage])
    }
    
    // MARK: - clearActiveChat Tests

    @MainActor
    func testClearActiveChatRemovesSheet() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        XCTAssertNotNil(sut.sheetViewController)

        // When
        sut.clearActiveChat()

        // Then
        XCTAssertNil(sut.sheetViewController)
    }

    @MainActor
    func testClearActiveChatThenPresentCreatesNewSheet() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        let firstSheet = sut.sheetViewController
        sut.clearActiveChat()

        // When
        await sut.presentSheet(from: mockPresentingVC)
        let secondSheet = sut.sheetViewController

        // Then
        XCTAssertFalse(firstSheet === secondSheet)
    }

    @MainActor
    func testPresentExistingSheetTriggersContextCollectionWhenAutoAttachEnabled() async {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = false
        await sut.presentSheet(from: mockPresentingVC)
        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)

        // When
        mockSettings.isAutomaticContextAttachmentEnabled = true
        await sut.presentSheet(from: mockPresentingVC)

        // Then
        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
    }

    @MainActor
    func testPresentExistingSheetDoesNotCollectSameAttachedURLAfterSubmit() async {
        let pageURL = URL(string: "https://example.com/page-a")!
        originatingTabURLSubject.send(pageURL)
        mockSettings.isAutomaticContextAttachmentEnabled = true

        await sut.presentSheet(from: mockPresentingVC)
        sut.sessionState.updateContext(makeTestContext(title: "Page A", url: pageURL.absoluteString))
        sut.sessionState.beginChatForUTISubmission()
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        sut.aiChatContextualSheetViewControllerDidDismiss(sut.sheetViewController!)
        await sut.presentSheet(from: mockPresentingVC)

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)
    }

    @MainActor
    func testNotifyPageChangedStillCollectsSameURLAfterSubmit() async {
        let pageURL = URL(string: "https://example.com/page-a")!
        originatingTabURLSubject.send(pageURL)
        mockSettings.isAutomaticContextAttachmentEnabled = true

        await sut.presentSheet(from: mockPresentingVC)
        sut.sessionState.updateContext(makeTestContext(title: "Page A", url: pageURL.absoluteString))
        sut.sessionState.beginChatForUTISubmission()
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        sut.aiChatContextualSheetViewControllerDidDismiss(sut.sheetViewController!)
        await sut.notifyPageChanged()

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
    }

    // MARK: - Delegate Forwarding Tests

    @MainActor
    func testDelegateReceivesLoadURLRequest() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        let testURL = URL(string: "https://example.com")!

        // When
        sut.aiChatContextualSheetViewController(sut.sheetViewController!, didRequestToLoad: testURL)

        // Then
        XCTAssertEqual(mockDelegate.didRequestToLoadURLs, [testURL])
    }

    @MainActor
    func testDelegateReceivesExpandRequestWithURL() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        let expandURL = URL(string: "https://duck.ai/chat/abc123")!

        // When
        sut.aiChatContextualSheetViewController(sut.sheetViewController!, didRequestExpandWithURL: expandURL)

        // Then
        XCTAssertEqual(mockDelegate.didRequestExpandURLs, [expandURL])
    }

    @MainActor
    func testExpandRequestRetainsActiveChat() async {
        // Given
        await sut.presentSheet(from: mockPresentingVC)
        XCTAssertNotNil(sut.sheetViewController)
        let expandURL = URL(string: "https://duck.ai/chat/abc123")!

        // When
        sut.aiChatContextualSheetViewController(sut.sheetViewController!, didRequestExpandWithURL: expandURL)

        // Then
        XCTAssertNotNil(sut.sheetViewController)
    }

    // MARK: - Page Context Handling Tests

    @MainActor
    func testNotifyPageChangedTriggersCollectionWhenAutoAttachEnabled() async {
        mockSettings.isAutomaticContextAttachmentEnabled = true
        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        await sut.notifyPageChanged()

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
    }

    @MainActor
    func testDidFinishURLPublisherTriggersCollectionWhenAutoAttachEnabled() async {
        mockSettings.isAutomaticContextAttachmentEnabled = true
        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        didFinishTabURLSubject.send(URL(string: "https://example.com/page-b")!)
        await Task.yield()

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
    }

    @MainActor
    func testDidFinishURLPublisherInitialReplayDoesNotDuplicateCollectionWhenSheetOpens() async {
        sut = nil
        mockPageContextHandler = MockPageContextHandler()
        originatingTabURLSubject = CurrentValueSubject<URL?, Never>(URL(string: "https://example.com/page-a")!)
        didFinishTabURLSubject = CurrentValueSubject<URL?, Never>(URL(string: "https://example.com/page-a")!)
        sut = AIChatContextualSheetCoordinator(
            voiceSearchHelper: MockVoiceSearchHelper(),
            aiChatSettings: mockSettings,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: contentBlockingSubject.eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: mockFeatureFlagger,
            unifiedToggleInputFeature: mockUnifiedToggleInputFeature,
            pageContextHandler: mockPageContextHandler,
            tabURLPublishers: AIChatTabURLPublishers(
                originating: originatingTabURLSubject.eraseToAnyPublisher(),
                didFinish: didFinishTabURLSubject.eraseToAnyPublisher()
            )
        )
        mockSettings.isAutomaticContextAttachmentEnabled = true

        await sut.presentSheet(from: mockPresentingVC)
        await Task.yield()

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
    }

    @MainActor
    func testNotifyPageChangedTriggersCollectionAfterUserRemoveWhenAutoAttachEnabled() async {
        mockSettings.isAutomaticContextAttachmentEnabled = true
        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.sendContext(makeTestContext())
        await waitForAttachedChip()
        sut.aiChatContextualSheetViewControllerDidRequestRemoveChip(sut.sheetViewController!)
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        await sut.notifyPageChanged()

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
    }

    @MainActor
    func testNotifyPageChangedDoesNotTriggerCollectionWhenAutoAttachDisabled() async {
        mockSettings.isAutomaticContextAttachmentEnabled = false
        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        await sut.notifyPageChanged()

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)
    }

    @MainActor
    func testNotifyPageChangedDoesNotTriggerCollectionWithoutActiveSheet() async {
        mockSettings.isAutomaticContextAttachmentEnabled = true

        await sut.notifyPageChanged()

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)
    }

    @MainActor
    func testRemoveChipRequestClearsHandler() async {
        mockSettings.isAutomaticContextAttachmentEnabled = true
        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.sendContext(makeTestContext())

        sut.aiChatContextualSheetViewControllerDidRequestRemoveChip(sut.sheetViewController!)

        XCTAssertEqual(sut.sessionState.chipState, .placeholder)
        XCTAssertEqual(mockPageContextHandler.clearCallCount, 1)
    }

    // MARK: - Session Timer Tests

    // MARK: - Multiple Page Contexts Tests

    @MainActor
    func testNotifyPageChangedSendsNavigationSignalWhenAutoCollectOffAndMultipleContextsEnabled() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.multiplePageContexts]
        mockSettings.isAutomaticContextAttachmentEnabled = false
        await sut.presentSheet(from: mockPresentingVC)

        // Start a chat so hasActiveChat is true
        sut.sessionState.handlePromptSubmission("Hello")
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        var receivedNullPush = false
        sut.sessionState.effects
            .sink { effect in
                if case .deliverPageContext(let data, let targets) = effect, data == nil, targets == .frontendBridge {
                    receivedNullPush = true
                }
            }
            .store(in: &cancellables)

        // When
        await sut.notifyPageChanged()

        // Then - null signal sent to FE, no context collection triggered
        XCTAssertTrue(receivedNullPush)
        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)
    }

    @MainActor
    func testNotifyPageChangedDoesNotSendNavigationSignalWhenMultipleContextsDisabled() async {
        // Given - flag OFF (default)
        mockSettings.isAutomaticContextAttachmentEnabled = false
        await sut.presentSheet(from: mockPresentingVC)

        sut.sessionState.handlePromptSubmission("Hello")

        var receivedPush = false
        sut.sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    receivedPush = true
                }
            }
            .store(in: &cancellables)

        // When
        await sut.notifyPageChanged()

        // Then - no signal sent (backward compatible)
        XCTAssertFalse(receivedPush)
    }

    @MainActor
    func testNotifyPageChangedDoesNotPushContextWhenSheetDismissedButRetained() async {
        // Given - sheet presented, chat started, then dismissed
        mockFeatureFlagger.enabledFeatureFlags = [.multiplePageContexts]
        mockSettings.isAutomaticContextAttachmentEnabled = true
        await sut.presentSheet(from: mockPresentingVC)
        sut.sessionState.handlePromptSubmission("Hello")
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        // Simulate dismiss (stopObservingContextUpdates + session timer)
        sut.aiChatContextualSheetViewControllerDidDismiss(sut.sheetViewController!)

        // Sheet is retained but not visible
        XCTAssertTrue(sut.hasActiveSheet)
        XCTAssertFalse(sut.isSheetPresented)

        var receivedPush = false
        sut.sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    receivedPush = true
                }
            }
            .store(in: &cancellables)

        // When
        await sut.notifyPageChanged()

        // Then
        XCTAssertFalse(receivedPush)
    }

    @MainActor
    func testNotifyPageChangedDoesNotSendNullSignalWhenSheetDismissedButRetained() async {
        // Given - auto-collect OFF, multi-context ON, chat started, then dismissed
        mockFeatureFlagger.enabledFeatureFlags = [.multiplePageContexts]
        mockSettings.isAutomaticContextAttachmentEnabled = false
        await sut.presentSheet(from: mockPresentingVC)
        sut.sessionState.handlePromptSubmission("Hello")

        // Simulate dismiss
        sut.aiChatContextualSheetViewControllerDidDismiss(sut.sheetViewController!)
        XCTAssertTrue(sut.hasActiveSheet)
        XCTAssertFalse(sut.isSheetPresented)

        var receivedPush = false
        sut.sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    receivedPush = true
                }
            }
            .store(in: &cancellables)

        // When - navigate while sheet is dismissed
        await sut.notifyPageChanged()

        // Then - no null signal sent (sheet not visible)
        XCTAssertFalse(receivedPush)
    }

    @MainActor
    func testImmediateUTINotifyPageChangedSendsAttachAffordanceWhenSheetDismissedButRetained() async {
        // Given - immediate UTI keeps a persistent host while the sheet is dismissed
        mockUnifiedToggleInputFeature.isAvailable = true
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatContextualUnifiedToggleInput, .multiplePageContexts]
        mockSettings.isAutomaticContextAttachmentEnabled = false
        await sut.presentSheet(from: mockPresentingVC)
        sut.sessionState.beginChatForUTISubmission()

        sut.aiChatContextualSheetViewControllerDidDismiss(sut.sheetViewController!)
        XCTAssertTrue(sut.hasActiveSheet)
        XCTAssertFalse(sut.isSheetPresented)

        var receivedTargets: PageContextDeliveryTargets?
        sut.sessionState.effects
            .sink { effect in
                if case .deliverPageContext(let context, let targets) = effect, context == nil {
                    receivedTargets = targets
                }
            }
            .store(in: &cancellables)

        // When - navigate while the immediate UTI sheet is dismissed
        await sut.notifyPageChanged()

        // Then - remember that the next sheet presentation should offer manual attach
        XCTAssertTrue(receivedTargets?.contains(.utiAttachAffordance) == true)
        XCTAssertTrue(receivedTargets?.contains(.utiChip) == false)
    }

    @MainActor
    func testImmediateUTINavigationUsesNotifyPageChangedPath() async {
        mockUnifiedToggleInputFeature.isAvailable = true
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatContextualUnifiedToggleInput]
        sut.sessionState.updateUnifiedToggleInputActive(true)
        mockSettings.isAutomaticContextAttachmentEnabled = true

        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        originatingTabURLSubject.send(URL(string: "https://example.com/did-commit"))
        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)

        await sut.notifyPageChanged()
        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
    }

    @MainActor
    func testImmediateUTIDoesNotAutoCollectBeforeNavigationAfterPreSubmitOptOut() async {
        mockUnifiedToggleInputFeature.isAvailable = true
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatContextualUnifiedToggleInput]
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let pageURL = URL(string: "https://example.com")!

        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.sendContext(makeTestContext(url: pageURL.absoluteString))
        await waitForAttachedChip()
        sut.sessionState.downgradeToPlaceholder()
        mockPageContextHandler.clearCallCount = 0
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)
        XCTAssertEqual(mockPageContextHandler.clearCallCount, 0)
    }

    @MainActor
    func testImmediateUTIAutoCollectsOnNavigationAfterPreSubmitOptOut() async {
        mockUnifiedToggleInputFeature.isAvailable = true
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatContextualUnifiedToggleInput]
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let pageURL = URL(string: "https://example.com")!

        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.sendContext(makeTestContext(url: pageURL.absoluteString))
        await waitForAttachedChip()
        sut.sessionState.downgradeToPlaceholder()
        mockPageContextHandler.clearCallCount = 0
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        await sut.notifyPageChanged()
        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
        XCTAssertEqual(mockPageContextHandler.clearCallCount, 0)
    }

    @MainActor
    func testImmediateUTIAutoCollectsOnReloadAfterPreSubmitOptOut() async {
        mockUnifiedToggleInputFeature.isAvailable = true
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatContextualUnifiedToggleInput]
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let pageURL = URL(string: "https://example.com")!

        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.sendContext(makeTestContext(url: pageURL.absoluteString))
        sut.sessionState.downgradeToPlaceholder()
        mockPageContextHandler.clearCallCount = 0
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        await sut.notifyPageChanged()
        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
        XCTAssertEqual(mockPageContextHandler.clearCallCount, 0)
    }

    @MainActor
    func testNotifyPageChangedAutoCollectsWhenImmediateUTISheetIsDismissed() async {
        mockUnifiedToggleInputFeature.isAvailable = true
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatContextualUnifiedToggleInput, .multiplePageContexts]
        mockSettings.isAutomaticContextAttachmentEnabled = true

        await sut.presentSheet(from: mockPresentingVC)
        sut.sessionState.beginChatForUTISubmission()
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        sut.aiChatContextualSheetViewControllerDidDismiss(sut.sheetViewController!)
        XCTAssertTrue(sut.hasActiveSheet)
        XCTAssertFalse(sut.isSheetPresented)

        await sut.notifyPageChanged()
        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
    }

    @MainActor
    func testBaseUTIAvailableWithoutContextualFlagUsesLegacyNavigationPath() async {
        mockUnifiedToggleInputFeature.isAvailable = true
        mockFeatureFlagger.enabledFeatureFlags = []
        mockSettings.isAutomaticContextAttachmentEnabled = true
        await sut.presentSheet(from: mockPresentingVC)
        mockPageContextHandler.triggerContextCollectionCallCount = 0

        originatingTabURLSubject.send(URL(string: "https://example.com/finished"))
        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 0)

        await sut.notifyPageChanged()
        XCTAssertEqual(mockPageContextHandler.triggerContextCollectionCallCount, 1)
    }

    @MainActor
    func testBaseUTIAvailableWithoutContextualFlagStillEnablesUTIChipDelivery() async {
        mockUnifiedToggleInputFeature.isAvailable = true
        mockFeatureFlagger.enabledFeatureFlags = []

        await sut.presentSheet(from: mockPresentingVC)

        XCTAssertTrue(sut.sessionState.shouldDeliverToUTIChip(makeTestContext().contextData))
    }

    // MARK: - Double Present Guard Tests

    @MainActor
    func testPresentSheetSkipsPresentationWhenSheetIsAlreadyPresented() async {
        // Given
        let window = UIWindow()
        let rootVC = UIViewController()
        window.rootViewController = rootVC
        window.makeKeyAndVisible()

        await sut.presentSheet(from: rootVC)
        let sheetVC = sut.sheetViewController!
        XCTAssertNotNil(sheetVC.presentingViewController)

        // When
        let secondPresenter = MockPresentingViewController()
        await sut.presentSheet(from: secondPresenter)

        // Then
        XCTAssertEqual(secondPresenter.presentCallCount, 0)
    }

    // MARK: - presentsFullScreen Tests

    @MainActor
    func testPresentSheetUsesMediumAndLargeDetentsByDefault() async {
        let window = UIWindow()
        let rootVC = UIViewController()
        window.rootViewController = rootVC
        window.makeKeyAndVisible()

        await sut.presentSheet(from: rootVC)

        let sheet = sut.sheetViewController!.sheetPresentationController!
        XCTAssertEqual(sheet.detents.count, 2)
        XCTAssertEqual(sheet.selectedDetentIdentifier, .medium)
        XCTAssertEqual(sheet.largestUndimmedDetentIdentifier, .medium)
        XCTAssertTrue(sheet.prefersGrabberVisible)
    }

    @MainActor
    func testPresentSheetUsesLargeDetentOnlyWhenPresentsFullScreenIsTrue() async {
        let fullScreenSUT = AIChatContextualSheetCoordinator(
            voiceSearchHelper: MockVoiceSearchHelper(),
            aiChatSettings: mockSettings,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: contentBlockingSubject.eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: mockFeatureFlagger,
            unifiedToggleInputFeature: mockUnifiedToggleInputFeature,
            pageContextHandler: mockPageContextHandler,
            tabURLPublishers: AIChatTabURLPublishers(
                originating: originatingTabURLSubject.eraseToAnyPublisher(),
                didFinish: didFinishTabURLSubject.eraseToAnyPublisher()
            ),
            presentsFullScreen: true
        )
        let window = UIWindow()
        let rootVC = UIViewController()
        window.rootViewController = rootVC
        window.makeKeyAndVisible()

        await fullScreenSUT.presentSheet(from: rootVC)

        let sheet = fullScreenSUT.sheetViewController!.sheetPresentationController!
        XCTAssertEqual(sheet.detents.count, 1)
        XCTAssertEqual(sheet.selectedDetentIdentifier, .large)
        XCTAssertEqual(sheet.largestUndimmedDetentIdentifier, .large)
        XCTAssertFalse(sheet.prefersGrabberVisible)
    }

    // MARK: - hideExpandButton Tests

    @MainActor
    func testHideExpandButtonHidesExpandButtonOnSheetViewController() async {
        await sut.presentSheet(from: mockPresentingVC)
        let sheetVC = sut.sheetViewController!

        XCTAssertFalse(sheetVC.isExpandButtonHidden)

        sheetVC.hideExpandButton()

        XCTAssertTrue(sheetVC.isExpandButtonHidden)
    }

    // MARK: - originatingURLPublisher Tests

    @MainActor
    func test_originatingURLPublisher_emitsTabURL() throws {
        var received: [URL?] = []
        sut.originatingURLPublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        originatingTabURLSubject.send(URL(string: "https://example.com")!)

        XCTAssertEqual(received.last??.absoluteString, "https://example.com")
    }

    @MainActor
    func test_originatingURLPublisher_emitsNilOnClear() throws {
        let url = URL(string: "https://example.com")!
        originatingTabURLSubject.send(url)

        var received: [URL?] = []
        sut.originatingURLPublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        originatingTabURLSubject.send(nil)

        XCTAssertEqual(received, [url, nil])
    }

    // MARK: - Helpers

    private func makeTestContext(title: String = "Test Page", url: String = "https://example.com") -> AIChatPageContext {
        let contextData = AIChatPageContextData(
            title: title,
            favicon: [],
            url: url,
            content: "Test content",
            truncated: false,
            fullContentLength: 12
        )
        return AIChatPageContext(contextData: contextData, favicon: nil)
    }

    @MainActor
    private func waitForAttachedChip(file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<5 {
            if case .attached = sut.sessionState.chipState {
                return
            }
            await Task.yield()
        }

        XCTFail("Expected attached chip state", file: file, line: line)
    }

}
