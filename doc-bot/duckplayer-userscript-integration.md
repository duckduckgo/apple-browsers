---
alwaysApply: false
title: "DuckPlayer UserScript Integration Guide"
description: "Detailed integration patterns for DuckPlayerUserScriptYouTube and DuckPlayerUserScriptPlayer, including communication protocols, event handling, and synchronization patterns"
keywords: ["DuckPlayer", "UserScript", "JavaScript bridge", "WebKit messaging", "YouTube integration", "video player communication", "event queuing", "state synchronization"]
---

# DuckPlayer UserScript Integration Guide

## Overview

DuckPlayer uses two primary UserScript components to bridge native iOS functionality with web content:
- `DuckPlayerUserScriptYouTube`: Manages communication with YouTube.com pages
- `DuckPlayerUserScriptPlayer`: Handles communication within the DuckPlayer web view

## Architecture Overview

### UserScript Communication Flow

```swift
// Communication flow:
// Web Content -> UserScript -> Native Handler -> ViewModel/Presenter
// Native UI -> Publisher -> UserScript -> Web Content

// ✅ CORRECT - Bidirectional communication pattern
final class DuckPlayerUserScriptYouTube: NSObject, Subfeature {
    // Incoming: Web -> Native
    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case "onCurrentTimeStamp": return onCurrentTimeStamp
        case "onYoutubeError": return onYoutubeError
        default: return nil
        }
    }
    
    // Outgoing: Native -> Web
    private func pushToWebView(method: String, params: [String: String]) {
        broker?.push(method: method, params: params, for: self, into: webView)
    }
}
```

## DuckPlayerUserScriptYouTube Integration

### Component Responsibilities

**Primary Role**: Bridge between YouTube.com pages and native DuckPlayer controls

**Key Responsibilities**:
- Manages media control events (play/pause)
- Handles audio muting state
- Tracks video timestamp updates
- Responds to URL changes
- Manages script readiness state with event queuing
- Provides initial setup configuration

### Event Queuing System

The UserScript implements an event queuing system to handle events before scripts are ready:

```swift
// ✅ CORRECT - Event queuing implementation
private enum QueuedEvent {
    case mediaControl(pause: Bool)
    case muteAudio(mute: Bool)
    case urlChanged(pageType: String)
}

private var otherEventsQueue: [QueuedEvent] = []
private var areScriptsReady = false

private func handleEvent(_ event: QueuedEvent) {
    switch event {
    case .urlChanged:
        // URL changes are always processed immediately
        processEvent(event)
    default:
        if areScriptsReady {
            processEvent(event)
        } else {
            // Queue events until scripts are ready
            otherEventsQueue.append(event)
        }
    }
}

// Process queued events when scripts become ready
func onDuckPlayerScriptsReady(params: Any, original: WKScriptMessage) -> Encodable? {
    areScriptsReady = true
    while !otherEventsQueue.isEmpty {
        let event = otherEventsQueue.removeFirst()
        processEvent(event)
    }
    return nil
}
```

### Publisher Integration Pattern

```swift
// ✅ CORRECT - Reactive publisher pattern
private func setupSubscriptions() {
    duckPlayer?.mediaControlPublisher
        .sink { [weak self] pause in
            self?.handleMediaControl(pause: pause)
        }
        .store(in: &cancellables)
    
    duckPlayer?.muteAudioPublisher
        .sink { [weak self] mute in
            self?.handleMuteAudio(mute: mute)
        }
        .store(in: &cancellables)
    
    duckPlayer?.urlChangedPublisher
        .sink { [weak self] url in
            self?.onUrlChanged(url: url)
        }
        .store(in: &cancellables)
}
```

### Message Origin Security

```swift
// ✅ CORRECT - Strict origin validation
let messageOriginPolicy: MessageOriginPolicy = .only(rules: [
    .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.duckduckgo),
    .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtube),
    .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeMobile),
    .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeWWW),
    .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookie),
    .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookieWWW)
])
```

### Page Type Detection

```swift
// ✅ CORRECT - URL-based page type detection
func onUrlChanged(url: URL) {
    areScriptsReady = false
    
    // Determine page type for proper script behavior
    let pageType = DuckPlayerUserScript.getPageType(url: url)
    let shouldClearEvents = pageType != DuckPlayerUserScript.PageType.YOUTUBE
    
    if shouldClearEvents {
        // Clear queued events when navigating away from YouTube
        otherEventsQueue.removeAll()
    }
    
    // Always store the latest URL change event
    handleEvent(.urlChanged(pageType: pageType))
}
```

## DuckPlayerUserScriptPlayer Integration

### Component Responsibilities

**Primary Role**: Handle communication within the DuckPlayer web view

**Key Responsibilities**:
- Provides initial setup configuration
- Updates video timestamps to the view model
- Handles YouTube error states
- Manages locale and page type information

### ViewModel Communication

```swift
// ✅ CORRECT - Direct view model updates
@MainActor
private func onCurrentTimeStamp(params: Any, original: WKScriptMessage) -> Encodable? {
    guard let dict = params as? [String: Any],
          let timeString = dict["timestamp"] as? String,
          let timeInterval = Double(timeString) else {
        return [:] as [String: String]
    }
    
    // Update view model directly
    viewModel?.updateTimeStamp(timeStamp: timeInterval)
    return [:] as [String: String]
}
```

### Initial Setup Pattern

Both UserScripts implement initial setup handlers to configure the web environment:

```swift
// ✅ CORRECT - Initial setup with environment data
@MainActor
private func initialSetup(params: Any, original: WKScriptMessage) -> Encodable? {
    struct InitialSetupResult: Encodable {
        let locale: String
        let playbackPaused: Bool
        let pageType: String
    }
    
    let result = InitialSetupResult(
        locale: Locale.current.languageCode ?? "en",
        playbackPaused: false,
        pageType: DuckPlayerUserScript.getPageType(url: webView?.url)
    )
    return result
}
```

## Common Integration Patterns

### Memory Management

```swift
// ✅ CORRECT - Proper cleanup and weak references
final class DuckPlayerUserScriptYouTube: NSObject, Subfeature {
    private weak var duckPlayer: DuckPlayerControlling?
    private weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()
    
    deinit {
        // Clean up subscriptions
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}
```

### Error Handling

```swift
// ✅ CORRECT - Graceful error handling
@MainActor
private func onYoutubeError(params: Any, original: WKScriptMessage) -> Encodable? {
    // Log error for debugging
    if let errorData = params as? [String: Any] {
        os_log(.error, "YouTube error: %{public}@", errorData.description)
    }
    
    // Return empty response to acknowledge receipt
    return [:] as [String: String]
}
```

### Constants and Type Safety

```swift
// ✅ CORRECT - Centralized constants
struct DuckPlayerUserScript {
    enum Handlers {
        static let onCurrentTimeStamp = "onCurrentTimeStamp"
        static let onYoutubeError = "onYoutubeError"
        static let initialSetup = "initialSetup"
        static let onDuckPlayerScriptsReady = "onDuckPlayerScriptsReady"
    }
    
    enum FEEvents {
        static let onMediaControl = "onMediaControl"
        static let onMuteAudio = "onMuteAudio"
        static let onUrlChanged = "onUrlChanged"
    }
    
    enum Constants {
        static let featureName = "duckPlayer"
        static let timestamp = "timestamp"
        static let pause = "pause"
        static let mute = "mute"
        static let pageType = "pageType"
        static let locale = "locale"
        static let localeDefault = "en"
    }
}
```

## Testing UserScript Components

### Mock Testing Pattern

```swift
// ✅ CORRECT - Testing with mocks
final class DuckPlayerUserScriptYouTubeTests: XCTestCase {
    private var sut: DuckPlayerUserScriptYouTube!
    private var mockDuckPlayer: MockDuckPlayerControlling!
    private var mockBroker: MockUserScriptMessageBroker!
    
    override func setUp() {
        super.setUp()
        mockDuckPlayer = MockDuckPlayerControlling()
        mockBroker = MockUserScriptMessageBroker()
        
        sut = DuckPlayerUserScriptYouTube(duckPlayer: mockDuckPlayer)
        sut.with(broker: mockBroker)
    }
    
    func testMediaControlEvent() {
        // Given
        let expectation = expectation(description: "Media control sent")
        mockBroker.pushExpectation = expectation
        
        // When
        mockDuckPlayer.mediaControlPublisher.send(true)
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mockBroker.lastMethod, "onMediaControl")
        XCTAssertEqual(mockBroker.lastParams["pause"], "true")
    }
}
```

### Event Queue Testing

```swift
// ✅ CORRECT - Testing event queuing
func testEventsQueuedBeforeScriptsReady() {
    // Given scripts are not ready
    
    // When events are sent
    mockDuckPlayer.mediaControlPublisher.send(true)
    mockDuckPlayer.muteAudioPublisher.send(true)
    
    // Then no events are pushed to web view
    XCTAssertNil(mockBroker.lastMethod)
    
    // When scripts become ready
    _ = sut.onDuckPlayerScriptsReady(params: [:], original: mockScriptMessage)
    
    // Then queued events are processed
    XCTAssertEqual(mockBroker.pushedMethods, ["onMediaControl", "onMuteAudio"])
}
```

## Integration Best Practices

### 1. Always Use Weak References

```swift
// ✅ CORRECT
private weak var duckPlayer: DuckPlayerControlling?
private weak var webView: WKWebView?

// ❌ INCORRECT - Avoid retain cycles
private var duckPlayer: DuckPlayerControlling?
private var webView: WKWebView?
```

### 2. Handle Script Readiness

```swift
// ✅ CORRECT - Check script readiness before sending events
if areScriptsReady {
    processEvent(event)
} else {
    otherEventsQueue.append(event)
}

// ❌ INCORRECT - Don't send events before scripts are ready
pushToWebView(method: "onMediaControl", params: params)
```

### 3. Use Type-Safe Parameters

```swift
// ✅ CORRECT - Type-safe parameter handling
struct TimestampUpdate: Codable {
    let timestamp: TimeInterval
}

func handleTimestamp(_ data: TimestampUpdate) {
    presenter.updateTimestamp(data.timestamp)
}

// ❌ INCORRECT - Avoid untyped dictionaries
func handleMessage(_ data: [String: Any]) {
    if let timestamp = data["timestamp"] as? Double {
        // Error-prone string-based access
    }
}
```

### 4. Implement Proper Cleanup

```swift
// ✅ CORRECT - Clean up resources
deinit {
    cancellables.forEach { $0.cancel() }
    cancellables.removeAll()
    otherEventsQueue.removeAll()
}
```

### 5. Follow Message Origin Policy

```swift
// ✅ CORRECT - Validate message origins
let messageOriginPolicy: MessageOriginPolicy = .only(rules: [
    .exact(hostname: "youtube.com"),
    .exact(hostname: "www.youtube.com")
])

// ❌ INCORRECT - Don't use overly permissive policies
let messageOriginPolicy: MessageOriginPolicy = .all
```

## Common Integration Issues

### Issue: Events Lost During Navigation

```swift
// ✅ SOLUTION - Clear state on navigation
func onUrlChanged(url: URL) {
    areScriptsReady = false
    
    if !isYouTubeURL(url) {
        // Clear events when leaving YouTube
        otherEventsQueue.removeAll()
    }
}
```

### Issue: Memory Leaks from Strong References

```swift
// ✅ SOLUTION - Use weak self in closures
duckPlayer?.mediaControlPublisher
    .sink { [weak self] pause in
        self?.handleMediaControl(pause: pause)
    }
    .store(in: &cancellables)
```

### Issue: Race Conditions with Script Loading

```swift
// ✅ SOLUTION - Queue events until ready
private func handleEvent(_ event: QueuedEvent) {
    guard areScriptsReady else {
        otherEventsQueue.append(event)
        return
    }
    processEvent(event)
}
```

This comprehensive guide ensures proper implementation of DuckPlayer UserScript components following established patterns for security, performance, and maintainability.