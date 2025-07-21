---
title: "DuckPlayer Architecture & Implementation Guide"
description: "Comprehensive guide for DuckPlayer Native UI architecture including presenter patterns, UserScript integration, view management, and variant configuration"
keywords: ["DuckPlayer", "native UI", "video player", "presenter pattern", "UserScript", "SwiftUI", "YouTube", "video playback", "analytics"]
alwaysApply: false
---

# DuckPlayer Implementation Guide

## Overview

DuckPlayer provides video playback within the app, separate from the web view-based player. The architecture separates concerns into distinct components using a presenter pattern, native UI views, and JavaScript integration for seamless video playback experiences.

## Architecture Components

### Core Architecture Pattern

DuckPlayer follows a presenter-driven architecture with clear separation of concerns:

```swift
// ✅ CORRECT - Presenter coordinates between components
final class DuckPlayerNativeUIPresenter {
    private let navigationHandler: NativeDuckPlayerNavigationHandler
    private let state: DuckPlayerState
    private let pixelFiring: DuckPlayerPixelFiring
    
    func presentPlayer(for videoID: String) {
        // Coordinates pill presentation, player setup, and analytics
        updateState(videoID: videoID)
        configurePillType()
        firePixels()
    }
}

// ❌ INCORRECT - Don't manage all responsibilities in one view
struct DuckPlayerView: View {
    @State private var videoID: String = ""
    @State private var isPresented = false
    // Don't handle navigation, state, and analytics directly in views
}
```

### State Management Pattern

Use `DuckPlayerState` for centralized video state management:

```swift
// ✅ CORRECT - Centralized state management
final class DuckPlayerState {
    var videoID: String?
    var hasBeenShown: Bool = false
    var timestamp: TimeInterval?
    
    func reset() {
        videoID = nil
        hasBeenShown = false
        timestamp = nil
    }
}

// ❌ INCORRECT - Scattered state across components
struct DuckPlayerView: View {
    @State private var videoID: String = ""
    @State private var timestamp: TimeInterval = 0
    // Don't duplicate state management
}
```

## Component Responsibilities

### DuckPlayerNativeUIPresenter

**Role**: Primary coordinator and state manager for the Native UI

**Key Responsibilities**:
- Manages presentation lifecycle of player UI components
- Coordinates between pill types (welcome, entry, re-entry)
- Handles user interactions and navigation events
- Manages constraint updates and visibility state
- Integrates with app navigation and browser features
- Handles orientation changes and UI adaptations
- Manages pixel firing for analytics tracking
- Controls toast notifications and dismiss count tracking

```swift
// ✅ CORRECT - Presenter pattern implementation
final class DuckPlayerNativeUIPresenter {
    private weak var containerView: DuckPlayerContainer?
    private let navigationHandler: NativeDuckPlayerNavigationHandler
    private let state: DuckPlayerState
    private let pixelFiring: DuckPlayerPixelFiring
    
    func presentWelcomePill() {
        // Configure welcome pill for first-time users
        configureContainerForPill(.welcome)
        fireWelcomePillPixel()
    }
    
    func presentEntryPill(for videoID: String) {
        // Configure entry pill for returning users
        state.videoID = videoID
        configureContainerForPill(.entry)
        fireEntryPillPixel()
    }
    
    func presentReEntryPill(for videoID: String) {
        // Configure re-entry pill for previously watched videos
        state.videoID = videoID
        configureContainerForPill(.reEntry)
        fireReEntryPillPixel()
    }
}
```

### NativeDuckPlayerNavigationHandler

**Role**: Manages video playback navigation and browser integration

```swift
// ✅ CORRECT - Navigation handler pattern
final class NativeDuckPlayerNavigationHandler {
    private let webView: WKWebView
    private let presenter: DuckPlayerNativeUIPresenter
    
    func handleYouTubeURL(_ url: URL) -> Bool {
        guard shouldHandleNatively(url) else { return false }
        
        let videoID = extractVideoID(from: url)
        presenter.presentPlayer(for: videoID)
        return true
    }
    
    private func shouldHandleNatively(_ url: URL) -> Bool {
        // Check if URL should be handled by native player
        return isYouTubeURL(url) && isNativeUIEnabled()
    }
}

// ❌ INCORRECT - Don't handle navigation directly in views
struct DuckPlayerView: View {
    func handleURL(_ url: URL) {
        // Don't put navigation logic in views
    }
}
```

## View Architecture

### Pill Management System

DuckPlayer uses a three-tier pill system based on user interaction history:

```swift
// ✅ CORRECT - Pill type management
enum DuckPlayerPillType {
    case welcome    // First-time users (priming modal not yet presented)
    case entry      // Returning users viewing new videos
    case reEntry    // Users returning to previously watched videos
}

final class DuckPlayerContainer: UIView {
    private var currentPillType: DuckPlayerPillType?
    
    func configurePill(_ type: DuckPlayerPillType, for videoID: String) {
        switch type {
        case .welcome:
            presentWelcomePill()
        case .entry:
            presentEntryPill(videoID: videoID)
        case .reEntry:
            presentReEntryPill(videoID: videoID)
        }
    }
}
```

### SwiftUI View Components

Follow reactive patterns for view models:

```swift
// ✅ CORRECT - Reactive view model pattern
final class DuckPlayerWelcomePillViewModel: ObservableObject {
    @Published var isAnimating = false
    @Published var isPresented = false
    
    private let pixelFiring: DuckPlayerPixelFiring
    private let onDismiss: () -> Void
    
    init(pixelFiring: DuckPlayerPixelFiring, onDismiss: @escaping () -> Void) {
        self.pixelFiring = pixelFiring
        self.onDismiss = onDismiss
    }
    
    func startAnimation() {
        isAnimating = true
        pixelFiring.fireWelcomePillShownPixel()
    }
    
    func handleUserTap() {
        pixelFiring.fireWelcomePillTappedPixel()
        onDismiss()
    }
}

// ❌ INCORRECT - Don't handle business logic directly in views
struct DuckPlayerWelcomePillView: View {
    @State private var isAnimating = false
    
    var body: some View {
        // Don't put pixel firing and business logic here
        Button("Watch in DuckPlayer") {
            // Business logic should be in view model
            Analytics.shared.firePixel(.welcomePillTapped)
        }
    }
}
```

## UserScript Integration

### JavaScript Bridge Pattern

Use UserScript components for native-web communication:

```swift
// ✅ CORRECT - UserScript integration pattern
final class DuckPlayerUserScriptYouTube: NSObject, UserScript {
    private let name = "DuckPlayerUserScriptYouTube"
    private let source = DuckPlayerUserScriptSource.youtube
    
    func messageReceived(_ message: Any) {
        guard let dict = message as? [String: Any],
              let messageType = dict["type"] as? String else { return }
        
        switch messageType {
        case "timestampUpdate":
            handleTimestampUpdate(dict)
        case "playerStateChange":
            handlePlayerStateChange(dict)
        case "error":
            handleError(dict)
        default:
            break
        }
    }
    
    private func handleTimestampUpdate(_ data: [String: Any]) {
        guard let timestamp = data["timestamp"] as? TimeInterval else { return }
        presenter.updateVideoTimestamp(timestamp)
    }
}

// ❌ INCORRECT - Don't handle JavaScript communication directly in views
struct DuckPlayerWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        // Don't add message handlers directly here
        return webView
    }
}
```

### Event Queuing System

Implement event queuing for script readiness:

```swift
// ✅ CORRECT - Event queuing pattern
final class DuckPlayerUserScript {
    private var eventQueue: [UserScriptEvent] = []
    private var isScriptReady = false
    
    func queueEvent(_ event: UserScriptEvent) {
        if isScriptReady {
            processEvent(event)
        } else {
            eventQueue.append(event)
        }
    }
    
    func onScriptReady() {
        isScriptReady = true
        eventQueue.forEach { processEvent($0) }
        eventQueue.removeAll()
    }
}
```

## Analytics Integration

### Pixel Firing Protocol

Use protocol-based pixel firing with debouncing:

```swift
// ✅ CORRECT - Protocol-based pixel firing
protocol DuckPlayerPixelFiring {
    func fireWelcomePillShownPixel()
    func fireWelcomePillTappedPixel()
    func fireEntryPillShownPixel()
    func fireVideoPlaybackStartedPixel()
    func fireDailyPixel(_ pixel: DuckPlayerDailyPixel)
}

final class DuckPlayerPixelHandler: DuckPlayerPixelFiring {
    private let pixelKit: PixelKit
    private let debouncer: PixelDebouncer
    
    func fireWelcomePillShownPixel() {
        debouncer.debounce {
            pixelKit.fire(.duckPlayerWelcomePillShown)
        }
    }
}

// ❌ INCORRECT - Don't fire pixels directly from views
struct DuckPlayerView: View {
    var body: some View {
        Button("Play") {
            // Don't fire pixels directly
            PixelKit.shared.fire(.duckPlayerPlayTapped)
        }
    }
}
```

### DuckPlayer Native Pixels

DuckPlayer Native fires various pixels to track user interactions and system events:

#### Pill Interaction Pixels
```swift
// Welcome Pill (first-time users)
.duckPlayerNativeWelcomePillShown      // When welcome pill is displayed
.duckPlayerNativeWelcomePillTapped     // When user taps welcome pill
.duckPlayerNativeWelcomePillDismissed  // When welcome pill is dismissed

// Entry Pill (returning users, new videos)
.duckPlayerNativeEntryPillShown        // When entry pill is displayed
.duckPlayerNativeEntryPillTapped       // When user taps entry pill
.duckPlayerNativeEntryPillDismissed    // When entry pill is dismissed

// Re-entry Pill (previously watched videos)
.duckPlayerNativeReEntryPillShown      // When re-entry pill is displayed
.duckPlayerNativeReEntryPillTapped     // When user taps re-entry pill
.duckPlayerNativeReEntryPillDismissed  // When re-entry pill is dismissed
```

#### Video Playback Pixels
```swift
// Playback events
.duckPlayerNativeVideoPlaybackStarted  // When video starts playing
.duckPlayerNativeVideoPlaybackPaused   // When video is paused
.duckPlayerNativeVideoPlaybackResumed  // When video is resumed
.duckPlayerNativeVideoPlaybackCompleted // When video finishes

// Daily unique playback tracking
.duckPlayerNativeDailyVideoPlayed      // Fired once per day when any video is played
```

#### YouTube Error Pixels

DuckPlayer Native tracks YouTube-specific errors with both volume (impression) and daily-unique pixels:

```swift
// Sign-in Required Errors
.duckPlayerNativeYouTubeSignInErrorImpression      // Every occurrence
.duckPlayerNativeYouTubeSignInErrorDaily           // Once per day

// Age-Restricted Content Errors
.duckPlayerNativeYouTubeAgeRestrictedErrorImpression // Every occurrence
.duckPlayerNativeYouTubeAgeRestrictedErrorDaily       // Once per day

// No-Embed Errors (embedding disabled)
.duckPlayerNativeYouTubeNoEmbedErrorImpression     // Every occurrence
.duckPlayerNativeYouTubeNoEmbedErrorDaily          // Once per day

// Unknown/Generic Errors
.duckPlayerNativeYouTubeUnknownErrorImpression     // Every occurrence
.duckPlayerNativeYouTubeUnknownErrorDaily          // Once per day
```

#### Error Handling Implementation

YouTube errors are handled in the UserScript layer:

```swift
// In DuckPlayerUserScriptPlayer.swift
@MainActor
private func onYoutubeError(params: Any, original: WKScriptMessage) -> Encodable? {
    let (volumePixel, dailyPixel) = getPixelsForNativeYouTubeErrorParams(params)
    DailyPixel.fire(pixel: dailyPixel)
    Pixel.fire(pixel: volumePixel)
    return [:] as [String: String]
}

private func getPixelsForNativeYouTubeErrorParams(_ params: Any) -> (Pixel.Event, Pixel.Event) {
    if let paramsDict = params as? [String: Any],
       let errorParam = paramsDict["error"] as? String {
        switch errorParam {
        case "sign-in-required":
            return (.duckPlayerNativeYouTubeSignInErrorImpression, .duckPlayerNativeYouTubeSignInErrorDaily)
        case "age-restricted":
            return (.duckPlayerNativeYouTubeAgeRestrictedErrorImpression, .duckPlayerNativeYouTubeAgeRestrictedErrorDaily)
        case "no-embed":
            return (.duckPlayerNativeYouTubeNoEmbedErrorImpression, .duckPlayerNativeYouTubeNoEmbedErrorDaily)
        default:
            return (.duckPlayerNativeYouTubeUnknownErrorImpression, .duckPlayerNativeYouTubeUnknownErrorDaily)
        }
    }
    return (.duckPlayerNativeYouTubeUnknownErrorImpression, .duckPlayerNativeYouTubeUnknownErrorDaily)
}
```

### Analytics Best Practices

```swift
// ✅ CORRECT - Centralized analytics tracking
final class DuckPlayerAnalytics {
    private let pixelFiring: DuckPlayerPixelFiring
    
    func trackPillPresentation(_ type: DuckPlayerPillType) {
        switch type {
        case .welcome:
            pixelFiring.fireWelcomePillShownPixel()
        case .entry:
            pixelFiring.fireEntryPillShownPixel()
        case .reEntry:
            pixelFiring.fireReEntryPillShownPixel()
        }
    }
    
    func trackVideoPlayback(duration: TimeInterval) {
        let parameters = ["duration": String(duration)]
        pixelFiring.fireVideoPlaybackPixel(parameters: parameters)
    }
    
    func trackYouTubeError(_ error: DuckPlayerError) {
        // Errors are tracked in UserScript layer
        // This method exists for future expansion
    }
}
```

### Pixel Naming Convention

All DuckPlayer Native pixels follow this naming pattern:
- **Volume pixels**: `duckplayer_native_{event}_impression_ios_{formfactor}`
- **Daily pixels**: `duckplayer_native_{event}_daily-unique_ios_{formfactor}`

The formfactor (phone/tablet) is automatically appended by the pixel infrastructure.

## Toast Notification System

### Toast Implementation Pattern

```swift
// ✅ CORRECT - Toast notification system
final class DuckPlayerToastManager {
    private weak var containerView: UIView?
    
    func showToast(_ message: String, position: ToastPosition = .top) {
        let toastView = DuckPlayerToastView(message: message)
        
        containerView?.addSubview(toastView)
        toastView.show(at: position) { [weak self] in
            self?.hideToast(toastView)
        }
    }
    
    private func hideToast(_ toastView: DuckPlayerToastView) {
        toastView.hide { 
            toastView.removeFromSuperview()
        }
    }
}

struct DuckPlayerToastView: View {
    let message: String
    @State private var isVisible = false
    
    var body: some View {
        Text(message)
            .padding()
            .background(Color(designSystemColor: .surface))
            .cornerRadius(8)
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 0.3), value: isVisible)
            .onAppear {
                isVisible = true
            }
    }
}
```

## Variant Management

### Variant Configuration Pattern

```swift
// ✅ CORRECT - Variant configuration system
enum DuckPlayerVariant: String, CaseIterable {
    case classic = "Web"
    case nativeOptIn = "Opt-in"
    case nativeOptOut = "Opt-out"
    
    var configuration: DuckPlayerConfiguration {
        switch self {
        case .classic:
            return DuckPlayerConfiguration(
                nativeUIEnabled: false,
                playerMode: .alwaysAsk,
                newTabBehavior: true,
                serpIntegration: false
            )
        case .nativeOptIn:
            return DuckPlayerConfiguration(
                nativeUIEnabled: true,
                playerMode: .askUserPreference,
                autoplayEnabled: true,
                serpIntegration: true,
                primingModalEnabled: true
            )
        case .nativeOptOut:
            return DuckPlayerConfiguration(
                nativeUIEnabled: true,
                playerMode: .automatic,
                autoplayEnabled: true,
                serpIntegration: true,
                primingModalEnabled: false
            )
        }
    }
}

// ❌ INCORRECT - Don't hardcode variant configurations
struct DuckPlayerSettings {
    var isNativeEnabled: Bool {
        // Don't hardcode variant logic
        return UserDefaults.standard.bool(forKey: "native_enabled")
    }
}
```

### Runtime Variant Switching

```swift
// ✅ CORRECT - Runtime variant management
final class DuckPlayerVariantManager {
    private let appSettings: AppSettings
    
    var currentVariant: DuckPlayerVariant {
        get {
            let rawValue = appSettings.duckPlayerVariant
            return DuckPlayerVariant(rawValue: rawValue) ?? .classic
        }
        set {
            appSettings.duckPlayerVariant = newValue.rawValue
            applyVariantConfiguration(newValue.configuration)
        }
    }
    
    private func applyVariantConfiguration(_ config: DuckPlayerConfiguration) {
        appSettings.duckPlayerNativeUIEnabled = config.nativeUIEnabled
        appSettings.duckPlayerSerpIntegration = config.serpIntegration
        appSettings.duckPlayerAutoplayEnabled = config.autoplayEnabled
        
        // Notify components of configuration change
        NotificationCenter.default.post(name: .duckPlayerVariantChanged, object: config)
    }
}
```

## Performance Optimization

### Lazy Loading Pattern

```swift
// ✅ CORRECT - Lazy loading for performance
final class DuckPlayerNativeUIPresenter {
    private lazy var welcomePillViewModel = DuckPlayerWelcomePillViewModel(
        pixelFiring: pixelFiring,
        onDismiss: { [weak self] in self?.dismissWelcomePill() }
    )
    
    private lazy var entryPillViewModel = DuckPlayerEntryPillViewModel(
        pixelFiring: pixelFiring,
        onPlay: { [weak self] in self?.startVideoPlayback() }
    )
    
    func presentWelcomePill() {
        // Only create view model when needed
        containerView?.configurePill(.welcome, viewModel: welcomePillViewModel)
    }
}

// ❌ INCORRECT - Don't create all view models upfront
final class DuckPlayerNativeUIPresenter {
    private let welcomePillViewModel: DuckPlayerWelcomePillViewModel
    private let entryPillViewModel: DuckPlayerEntryPillViewModel
    private let reEntryPillViewModel: DuckPlayerMiniPillViewModel
    
    init() {
        // Don't create all view models immediately
        welcomePillViewModel = DuckPlayerWelcomePillViewModel(...)
        entryPillViewModel = DuckPlayerEntryPillViewModel(...)
        reEntryPillViewModel = DuckPlayerMiniPillViewModel(...)
    }
}
```

## Testing Patterns

### Presenter Testing

```swift
// ✅ CORRECT - Testing presenter components
final class DuckPlayerNativeUIPresenterTests: XCTestCase {
    private var sut: DuckPlayerNativeUIPresenter!
    private var mockNavigationHandler: MockNativeDuckPlayerNavigationHandler!
    private var mockPixelFiring: MockDuckPlayerPixelFiring!
    private var mockState: DuckPlayerState!
    
    override func setUp() {
        super.setUp()
        mockNavigationHandler = MockNativeDuckPlayerNavigationHandler()
        mockPixelFiring = MockDuckPlayerPixelFiring()
        mockState = DuckPlayerState()
        
        sut = DuckPlayerNativeUIPresenter(
            navigationHandler: mockNavigationHandler,
            pixelFiring: mockPixelFiring,
            state: mockState
        )
    }
    
    func testPresentWelcomePill() {
        // When
        sut.presentWelcomePill()
        
        // Then
        XCTAssertTrue(mockPixelFiring.fireWelcomePillShownPixelCalled)
        XCTAssertEqual(sut.currentPillType, .welcome)
    }
}
```

### UserScript Testing

```swift
// ✅ CORRECT - Testing UserScript components
final class DuckPlayerUserScriptTests: XCTestCase {
    private var sut: DuckPlayerUserScriptYouTube!
    private var mockPresenter: MockDuckPlayerPresenter!
    
    func testTimestampUpdateMessage() {
        // Given
        let message = ["type": "timestampUpdate", "timestamp": 120.5]
        
        // When
        sut.messageReceived(message)
        
        // Then
        XCTAssertEqual(mockPresenter.lastTimestampUpdate, 120.5)
    }
}
```

## Common Patterns

### Error Handling

```swift
// ✅ CORRECT - Comprehensive error handling
enum DuckPlayerError: Error {
    case videoNotFound
    case networkError
    case playbackError(underlying: Error)
    case invalidConfiguration
}

final class DuckPlayerErrorHandler {
    private let pixelFiring: DuckPlayerPixelFiring
    
    func handleError(_ error: DuckPlayerError) {
        switch error {
        case .videoNotFound:
            pixelFiring.fireErrorPixel(.videoNotFound)
            showErrorToast("Video not available")
        case .networkError:
            pixelFiring.fireErrorPixel(.networkError)
            showErrorToast("Network connection required")
        case .playbackError(let underlying):
            pixelFiring.fireErrorPixel(.playbackError, parameters: ["error": underlying.localizedDescription])
            showErrorToast("Playback error occurred")
        case .invalidConfiguration:
            pixelFiring.fireErrorPixel(.invalidConfiguration)
            // Handle configuration errors silently
        }
    }
}
```

### Memory Management

```swift
// ✅ CORRECT - Proper memory management
final class DuckPlayerNativeUIPresenter {
    private weak var containerView: DuckPlayerContainer?
    private var cancellables = Set<AnyCancellable>()
    
    deinit {
        cancellables.removeAll()
        cleanupResources()
    }
    
    private func cleanupResources() {
        // Clean up any retained resources
        containerView?.removeFromSuperview()
        state.reset()
    }
}
```

## Migration Guidelines

### Integrating DuckPlayer

When adding DuckPlayer to new areas:

1. **Use the presenter pattern** - Don't put business logic in views
2. **Follow the pill system** - Implement appropriate pill types for user journey
3. **Integrate analytics** - Use the pixel firing protocol for tracking
4. **Handle variants** - Support all three DuckPlayer variants
5. **Test thoroughly** - Write tests for presenter, UserScript, and view components

### Common Integration Mistakes

```swift
// ❌ INCORRECT - Don't bypass the presenter
struct MyFeatureView: View {
    @State private var showDuckPlayer = false
    
    var body: some View {
        Button("Play Video") {
            // Don't create DuckPlayer components directly
            showDuckPlayer = true
        }
    }
}

// ✅ CORRECT - Use the presenter pattern
struct MyFeatureView: View {
    private let duckPlayerPresenter: DuckPlayerNativeUIPresenter
    
    var body: some View {
        Button("Play Video") {
            duckPlayerPresenter.presentPlayer(for: videoID)
        }
    }
}
```

This guide provides the foundation for implementing and maintaining DuckPlayer components following established patterns and best practices in the DuckDuckGo browser codebase. 