/*
import XCTest
import WebKit
import Common
import DuckPlayer
import Combine
import BrowserServicesKit

@testable import DuckDuckGo

final class DuckPlayerNativeUserScriptTests: XCTestCase {
    
    private var sut: DuckPlayerNativeUserScript!
    private var mockDuckPlayer: MockDuckPlayer!
    private var mockBroker: MockUserScriptMessageBroker!
    private var mockWebView: MockWebView!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        let mockSettings = MockDuckPlayerSettings(appSettings: MockAppSettings(), privacyConfigManager: MockPrivacyConfigurationManager(), internalUserDecider: MockDuckPlayerInternalUserDecider())
        let mockFeatureFlagger = MockDuckPlayerFeatureFlagger()
        mockDuckPlayer = MockDuckPlayer(settings: mockSettings, featureFlagger: mockFeatureFlagger)
        mockBroker = MockUserScriptMessageBroker()
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
    
    func testWhenURLChangesToYouTubeWatchPage_QueueIsPreserved() {
        // Given
        mockWebView.setCurrentURL(URL(string: "https://www.youtube.com/watch?v=test")!)
        
        // When
        sut.onUrlChanged()
        
        // Then
        XCTAssertFalse(sut.isFeatureReady)
        XCTAssertTrue(mockBroker.pushedMethods.isEmpty)
    }
    
    func testWhenURLChangesToNonYouTubePage_QueueIsCleared() {
        // Given
        mockWebView.setCurrentURL(URL(string: "https://duckduckgo.com")!)
        
        // When
        sut.onUrlChanged()
        
        // Then
        XCTAssertFalse(sut.isFeatureReady)
        XCTAssertTrue(mockBroker.pushedMethods.isEmpty)
    }
    
    func testWhenURLChangesToYouTubeNonWatchPage_QueueIsCleared() {
        // Given
        mockWebView.setCurrentURL(URL(string: "https://www.youtube.com/feed")!)
        
        // When
        sut.onUrlChanged()
        
        // Then
        XCTAssertFalse(sut.isFeatureReady)
        XCTAssertTrue(mockBroker.pushedMethods.isEmpty)
    }
    
    // MARK: - Event Queueing Tests
    
    func testWhenFeatureNotReady_EventsAreQueued() {
        // Given
        sut.isFeatureReady = false
        
        // When
        mockDuckPlayer.mediaControlPublisher.send(true)
        mockDuckPlayer.serpNotificationPublisher.send(true)
        mockDuckPlayer.muteAudioPublisher.send(true)
        
        // Then
        XCTAssertTrue(mockBroker.pushedMethods.isEmpty)
    }
    
    @MainActor func testWhenFeatureBecomesReady_QueuedEventsAreProcessed() {
        // Given
        sut.isFeatureReady = false
        mockDuckPlayer.mediaControlPublisher.send(true)
        mockDuckPlayer.serpNotificationPublisher.send(true)
        mockDuckPlayer.muteAudioPublisher.send(true)
        
        // When
        sut.onDuckPlayerReady(params: [:], original: WKScriptMessage())
        
        // Then
        XCTAssertTrue(sut.isFeatureReady)
        XCTAssertEqual(mockBroker.pushedMethods.count, 3)
        XCTAssertEqual(mockBroker.pushedMethods[0].method, "onMediaControl")
        XCTAssertEqual(mockBroker.pushedMethods[1].method, "onSerpNotify")
        XCTAssertEqual(mockBroker.pushedMethods[2].method, "onMuteAudio")
    }
    
    func testWhenFeatureIsReady_EventsAreProcessedImmediately() {
        // Given
        sut.isFeatureReady = true
        
        // When
        mockDuckPlayer.mediaControlPublisher.send(true)
        
        // Then
        XCTAssertEqual(mockBroker.pushedMethods.count, 1)
        XCTAssertEqual(mockBroker.pushedMethods[0].method, "onMediaControl")
    }
    
    // MARK: - URL Change Event Tests
    
    @MainActor func testWhenURLChangesAndFeatureBecomesReady_URLChangeEventIsProcessed() {
        // Given
        mockWebView.setCurrentURL(URL(string: "https://www.youtube.com/watch?v=test")!)
        sut.onUrlChanged()
        
        // When
        sut.onDuckPlayerReady(params: [:], original: WKScriptMessage())
        
        // Then
        XCTAssertTrue(sut.isFeatureReady)
        XCTAssertEqual(mockBroker.pushedMethods.count, 1)
        XCTAssertEqual(mockBroker.pushedMethods[0].method, "onUrlChanged")
    }
}

// MARK: - Mock Classes

private class MockUserScriptMessageBroker: UserScriptMessageBroker {
    var pushedMethods: [(method: String, params: [String: String])] = []
    
    func push(method: String, params: [String: String], for subfeature: Subfeature, into webView: WKWebView) {
        pushedMethods.append((method: method, params: params))
    }
    
    // Add required protocol methods
    func add(_ subfeature: Subfeature) {}
    func remove(_ subfeature: Subfeature) {}
    func push(method: String, params: [String: Any], for subfeature: Subfeature, into webView: WKWebView) {}
    func push(method: String, params: [String: Any], for subfeature: Subfeature, into webView: WKWebView, completion: @escaping (Any?) -> Void) {}
}

private class MockWebView: WKWebView {
    var url: URL?
    
    override var url: URL? {
        get { url }
        set { url = newValue }
    }
    
    func setCurrentURL(_ url: URL) {
        self.url = url
    }
}
*/
