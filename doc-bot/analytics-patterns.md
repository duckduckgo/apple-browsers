---
title: "Analytics and Pixel Patterns"
description: "Pixel analytics and event tracking patterns for DuckDuckGo browser with privacy-safe tracking and structured events"
keywords: ["analytics", "pixels", "event tracking", "PixelEvent", "PixelParameters", "performance metrics", "error tracking", "privacy"]
alwaysApply: false
---

# Analytics and Pixel Patterns

## Structured Pixel Events
Use the existing Pixel.fire pattern with structured event definitions:

```swift
// ✅ CORRECT - Use existing Pixel.fire with proper parameters
extension PixelEvent {
    static let featureUsed = "feature_used"
    static let performanceMetric = "performance_metric"
    static let errorOccurred = "error_occurred"
    static let userAction = "user_action"
}

// Usage examples from codebase
Pixel.fire(pixel: .webKitTerminationDidReloadCurrentTab)

Pixel.fire(pixel: .cachedTabPreviewsExceedsTabCount, withAdditionalParameters: [
    PixelParameters.tabPreviewCountDelta: "\(storedPreviews - totalTabs)"
])

Pixel.fire(pixel: .autofillLoginsSavePromptDisplayed, withAdditionalParameters: [
    PixelParameters.autofillPromptTrigger: "manual"
])
```

## Pixel Parameters
Use the established PixelParameters constants:

```swift
// ✅ CORRECT - Use existing PixelParameters
extension PixelParameters {
    static let featureName = "fn"
    static let errorType = "et"
    static let performanceValue = "pv"
    static let userActionSource = "uas"
}

// Usage
Pixel.fire(pixel: .newFeatureUsed, withAdditionalParameters: [
    PixelParameters.featureName: "voice_search",
    PixelParameters.userActionSource: "keyboard_shortcut"
])
```

## Performance Metrics
Track performance metrics consistently:

```swift
// ✅ CORRECT - Performance tracking pattern
final class PerformanceTracker {
    static func trackPageLoad(duration: TimeInterval, url: URL) {
        let parameters = [
            PixelParameters.duration: String(format: "%.3f", duration),
            PixelParameters.domain: url.host ?? "unknown"
        ]
        
        Pixel.fire(pixel: .pageLoadTime, withAdditionalParameters: parameters)
    }
    
    static func trackMemoryUsage(bytes: Int, context: String) {
        let parameters = [
            PixelParameters.memoryUsage: "\(bytes)",
            PixelParameters.context: context
        ]
        
        Pixel.fire(pixel: .memoryUsage, withAdditionalParameters: parameters)
    }
}
```

## Error Tracking
Track errors with context:

```swift
// ✅ CORRECT - Error tracking
extension Pixel {
    static func fireError(_ error: Error, context: String = "") {
        let parameters = [
            PixelParameters.errorType: String(describing: type(of: error)),
            PixelParameters.context: context
        ]
        
        Pixel.fire(pixel: .errorOccurred, withAdditionalParameters: parameters)
    }
}

// Usage
do {
    try await networkService.fetchData()
} catch {
    Pixel.fireError(error, context: "data_fetch")
    throw error
}
```

## Feature Usage Tracking
Track feature adoption and usage:

```swift
// ✅ CORRECT - Feature usage tracking
final class FeatureTracker {
    static func trackFeatureUsage(_ feature: String, source: String = "") {
        let parameters = [
            PixelParameters.featureName: feature,
            PixelParameters.userActionSource: source
        ]
        
        Pixel.fire(pixel: .featureUsed, withAdditionalParameters: parameters)
    }
    
    static func trackFeatureEnabled(_ feature: String, enabled: Bool) {
        let parameters = [
            PixelParameters.featureName: feature,
            PixelParameters.enabled: enabled ? "true" : "false"
        ]
        
        Pixel.fire(pixel: .featureToggled, withAdditionalParameters: parameters)
    }
}
```

## Privacy-Safe Analytics
Ensure all analytics respect privacy:

```swift
// ✅ CORRECT - Privacy-safe analytics
final class PrivacyAnalytics {
    static func trackWithPrivacy(event: String, value: String) {
        // Hash sensitive values
        let hashedValue = value.sha256Hash
        
        let parameters = [
            PixelParameters.hashedValue: hashedValue
        ]
        
        Pixel.fire(pixel: event, withAdditionalParameters: parameters)
    }
    
    static func trackAggregateMetric(metric: String, count: Int) {
        // Only send aggregate data, never individual events
        let parameters = [
            PixelParameters.metric: metric,
            PixelParameters.count: "\(count)"
        ]
        
        Pixel.fire(pixel: .aggregateMetric, withAdditionalParameters: parameters)
    }
}
```

See `feature-flags.md` for A/B test analytics and `privacy-security.md` for privacy requirements.