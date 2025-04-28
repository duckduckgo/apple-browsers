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

