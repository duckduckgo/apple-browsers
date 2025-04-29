import XCTest
import WebKit
import Common
import DuckPlayer
import Combine
import BrowserServicesKit
import UserScript

@testable import DuckDuckGo

final class DuckPlayerNativeUserScriptTests: XCTestCase {
    
    private var sut: DuckPlayerNativeUserScript!
    private var mockDuckPlayer: MockDuckPlayer!
    private var mockBroker: UserScriptMessageBroker!
    private var mockWebView: MockWebView!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        let mockSettings = MockDuckPlayerSettings(
            appSettings: AppSettingsMock(),
            privacyConfigManager: PrivacyConfigurationManagerMock(),
            internalUserDecider: MockDuckPlayerInternalUserDecider()
        )
        let mockFeatureFlagger = MockDuckPlayerFeatureFlagger()
        mockDuckPlayer = MockDuckPlayer(settings: mockSettings, featureFlagger: mockFeatureFlagger)
        mockBroker = UserScriptMessageBroker(context: "testContext")
        mockWebView = MockWebView()
        cancellables = Set<AnyCancellable>()
        
        sut = DuckPlayerNativeUserScript(duckPlayer: mockDuckPlayer)
        sut.with(broker: mockBroker)
        sut.webView = mockWebView
    }
    
    override func tearDown() {
        sut = nil
        mockDuckPlayer = nil
        mockBroker = nil
        mockWebView = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - URL Change Tests
    
    func testWhenURLChangesToYouTubeWatchPage_IsFeatureReadyIsFalse() {
        // Given
        sut.isFeatureReady = false
        mockWebView.navigate(to: URL(string: "https://www.youtube.com/watch?v=test")!)
        
        // When
        sut.onUrlChanged()
        
        // Then
        XCTAssertFalse(sut.isFeatureReady)
    }
    
    func testWhenURLChangesToNonYouTubePage_IsFeatureReadyIsFalse() {
        // Given
        sut.isFeatureReady = false
        mockWebView.navigate(to: URL(string: "https://duckduckgo.com")!)
        
        // When
        sut.onUrlChanged()
        
        // Then
        XCTAssertFalse(sut.isFeatureReady)
    }
    
    func testWhenURLChangesToYouTubeNonWatchPage_IsFeatureReadyIsFalse() {
        // Given
        sut.isFeatureReady = false
        mockWebView.navigate(to: URL(string: "https://www.youtube.com/feed")!)
        
        // When
        sut.onUrlChanged()
        
        // Then
        XCTAssertFalse(sut.isFeatureReady)
    }
    
    // MARK: - Event Queueing Tests
    
    func testWhenFeatureNotReady_IsFeatureReadyRemainsUnchanged() {
        // Given
        sut.isFeatureReady = false
        
        // When
        mockDuckPlayer.mediaControlPublisher.send(true)
        mockDuckPlayer.serpNotificationPublisher.send(true)
        mockDuckPlayer.muteAudioPublisher.send(true)
        
        // Then
        XCTAssertFalse(sut.isFeatureReady)
    }
    
    @MainActor func testWhenFeatureBecomesReady_IsFeatureReadyBecomesTrue() {
        // Given
        sut.isFeatureReady = false
        mockDuckPlayer.mediaControlPublisher.send(true)
        mockDuckPlayer.serpNotificationPublisher.send(true)
        mockDuckPlayer.muteAudioPublisher.send(true)
        
        // When
        _ = sut.onDuckPlayerReady(params: [:], original: WKScriptMessage())
        
        // Then
        XCTAssertTrue(sut.isFeatureReady)
    }
    
    func testWhenFeatureIsReady_IsFeatureReadyRemainsTrue() {
        // Given
        sut.isFeatureReady = true
        
        // When
        mockDuckPlayer.mediaControlPublisher.send(true)
        
        // Then
        XCTAssertTrue(sut.isFeatureReady)
    }
    
    // MARK: - URL Change Event Tests
    
    @MainActor func testWhenURLChangesAndFeatureBecomesReady_IsFeatureReadyBecomesTrue() {
        // Given
        sut.isFeatureReady = false
        mockWebView.navigate(to: URL(string: "https://www.youtube.com/watch?v=test")!)
        sut.onUrlChanged()
        
        // When
        _ = sut.onDuckPlayerReady(params: [:], original: WKScriptMessage())
        
        // Then
        XCTAssertTrue(sut.isFeatureReady)
    }
    
    func testWhenFeatureIsReadyAndURLChanges_IsFeatureReadyRemainsTrue() {
        // Given
        sut.isFeatureReady = true
        mockWebView.navigate(to: URL(string: "https://www.youtube.com/watch?v=test")!)
        
        // When
        sut.onUrlChanged()
        
        // Then
        XCTAssertTrue(sut.isFeatureReady)
    }
    
    @MainActor func testWhenURLChangesMultipleTimes_IsFeatureReadyRemainsTrue() {
        // Given
        sut.isFeatureReady = false
        mockWebView.navigate(to: URL(string: "https://www.youtube.com/watch?v=test1")!)
        
        // First URL change (not ready)
        sut.onUrlChanged()
        
        // Now feature becomes ready
        _ = sut.onDuckPlayerReady(params: [:], original: WKScriptMessage())
        XCTAssertTrue(sut.isFeatureReady)
        
        // When - Second URL change (while ready)
        mockWebView.navigate(to: URL(string: "https://www.youtube.com/watch?v=test2")!)
        sut.onUrlChanged()
        
        // Then
        XCTAssertTrue(sut.isFeatureReady) // Should still be ready
    }
    
    // MARK: - Event Handling Tests
    
    @MainActor func testOnlyLatestUrlChangedEventIsStoredAndSentAfterFeatureReady() {
        // Given
        let brokerWrapper = UserScriptMessageBrokerWrapper(broker: mockBroker)
        sut.broker = brokerWrapper.broker
        sut.webView = mockWebView
        
        // Simulate multiple URL changes before feature is ready
        mockWebView.navigate(to: URL(string: "https://www.youtube.com/watch?v=first")!)
        sut.onUrlChanged()
        mockWebView.navigate(to: URL(string: "https://www.youtube.com/watch?v=second")!)
        sut.onUrlChanged()
        mockWebView.navigate(to: URL(string: "https://www.youtube.com/watch?v=third")!)
        sut.onUrlChanged()
        
        // When feature becomes ready
        _ = sut.onDuckPlayerFeatureReady(params: [:], original: WKScriptMessage())
        
        // Then: Only the latest urlChanged event should be sent
        XCTAssertTrue(sut.isFeatureReady)
        // The pending URL change event should be cleared after being sent
        XCTAssertNil(sut.pendingUrlChangeEvent)
    }

    @MainActor func testOtherEventsAreQueuedAndSentAfterScriptsReady() {
        // Given
        let brokerWrapper = UserScriptMessageBrokerWrapper(broker: mockBroker)
        sut.broker = brokerWrapper.broker
        sut.webView = mockWebView
        
        // Simulate other events before scripts are ready
        mockDuckPlayer.mediaControlPublisher.send(true)
        mockDuckPlayer.serpNotificationPublisher.send(true)
        mockDuckPlayer.muteAudioPublisher.send(true)
        
        // When scripts become ready
        _ = sut.onDuckPlayerScriptsReady(params: [:], original: WKScriptMessage())
        
        // Then: All events should be sent and queue cleared
        XCTAssertTrue(sut.areScriptsReady)
        XCTAssertTrue(sut.otherEventsQueue.isEmpty)
    }

    @MainActor func testEventsAreClearedAfterReload() {
        // Given
        let brokerWrapper = UserScriptMessageBrokerWrapper(broker: mockBroker)
        sut.broker = brokerWrapper.broker
        sut.webView = mockWebView
        
        // Simulate events before reload
        mockWebView.navigate(to: URL(string: "https://www.youtube.com/watch?v=first")!)
        sut.onUrlChanged()
        mockDuckPlayer.mediaControlPublisher.send(true)
        
        // Simulate reload to non-YouTube page (should clear events)
        mockWebView.navigate(to: URL(string: "https://duckduckgo.com")!)
        sut.onUrlChanged()
        
        // Then: Both pending URL change and other events should be cleared
        XCTAssertNil(sut.pendingUrlChangeEvent)
        XCTAssertTrue(sut.otherEventsQueue.isEmpty)
    }
}

// MARK: - Helper Classes

/// A wrapper to monitor calls to the UserScriptMessageBroker
class UserScriptMessageBrokerWrapper {
    let broker: UserScriptMessageBroker
    var pushedMethods: [(method: String, params: [String: String])] = []
    private var originalPushMethod: Method?
    
    init(broker: UserScriptMessageBroker) {
        self.broker = broker
    }
    
    // In a real implementation, we would hook the push method to capture calls
    // For test purposes, we're simulating this behavior
    func mockPushCaptured(method: String, params: [String: String], for subfeature: Subfeature, into webView: WKWebView) {
        pushedMethods.append((method: method, params: params))
    }
}

