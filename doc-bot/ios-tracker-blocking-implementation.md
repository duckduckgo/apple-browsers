---
alwaysApply: false
title: "iOS Tracker Blocking Implementation Guide"
description: "Comprehensive guide to tracker blocking implementation on iOS using Content Blocker Rules and JavaScript injection techniques with Tracker Radar data"
keywords: ["iOS", "tracker blocking", "content blocker", "WebKit", "JavaScript injection", "privacy", "ContentBlockerRulesManager", "UserScript", "Tracker Radar", "surrogates", "WKWebView"]
---

# iOS Tracker Blocking Implementation Guide

## Overview

This document provides a comprehensive overview of how content blocking has been implemented on iOS to protect user privacy and block tracking attempts. Our implementation uses a dual-approach strategy that combines the efficiency of WebKit's native content blocking with the flexibility of JavaScript-based protection.

**Implementation Strategy:**
- **Primary Layer**: Content Blocker Rules (WebKit native, compiled to bytecode)
- **Secondary Layer**: JavaScript injection with Tracker Radar data (gap coverage + surrogates)

## Content Blocker Rules

### Architecture Overview

Content Blocker Rules form the primary layer of our tracker blocking implementation. These rules are converted from our Tracker Radar dataset into Apple's Content Blocker Rules format and compiled by WebKit into efficient bytecode for optimal performance.

**Key Characteristics:**
- ✅ **High Performance**: Rules are compiled to bytecode by WebKit
- ✅ **Low Memory Footprint**: Optimized for mobile devices
- ✅ **Battery Efficient**: Minimal CPU overhead
- ❌ **Limited Flexibility**: Cannot support complex logic or surrogates
- ❌ **No Runtime Modification**: Rules are static once compiled

### Implementation Details

#### ContentBlockerRulesManager

The `ContentBlockerRulesManager` is responsible for converting Tracker Radar data into Apple's Content Blocker format and managing the rule compilation process.

```swift
import WebKit
import BrowserServicesKit

final class ContentBlockerRulesManager {
    private let trackerDataManager: TrackerDataManager
    private let compilationQueue = DispatchQueue(label: "content-blocker-compilation", qos: .utility)
    
    init(trackerDataManager: TrackerDataManager) {
        self.trackerDataManager = trackerDataManager
    }
    
    /// Converts Tracker Radar data to Content Blocker Rules format
    func generateContentBlockerRules() async throws -> [WKContentRuleList] {
        return try await withCheckedThrowingContinuation { continuation in
            compilationQueue.async {
                do {
                    let trackerData = self.trackerDataManager.embeddedTrackerData
                    let rules = self.convertToContentBlockerFormat(trackerData)
                    let ruleList = try self.compileRules(rules)
                    continuation.resume(returning: [ruleList])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Converts TrackerData to Apple's Content Blocker Rules JSON format
    private func convertToContentBlockerFormat(_ trackerData: TrackerData) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        
        for (domain, tracker) in trackerData.trackers {
            for rule in tracker.rules ?? [] {
                let contentBlockerRule: [String: Any] = [
                    "trigger": [
                        "url-filter": rule.rule,
                        "resource-type": rule.resourceTypes,
                        "if-domain": rule.whitelist?.compactMap { "*\($0)" }
                    ].compactMapValues { $0 },
                    "action": [
                        "type": "block"
                    ]
                ]
                rules.append(contentBlockerRule)
            }
        }
        
        return rules
    }
    
    /// Compiles rules using WebKit's WKContentRuleListStore
    private func compileRules(_ rules: [[String: Any]]) throws -> WKContentRuleList {
        let jsonData = try JSONSerialization.data(withJSONObject: rules)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "DuckDuckGoContentBlocker",
                encodedContentRuleList: jsonString
            ) { ruleList, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let ruleList = ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: ContentBlockerError.compilationFailed)
                }
            }
        }
    }
}

enum ContentBlockerError: Error {
    case compilationFailed
    case invalidRuleFormat
    case trackerDataUnavailable
}
```

#### Integration with WKWebView

Content Blocker Rules are applied to WKWebView through the `WKUserContentController`:

```swift
extension BrowserWebView {
    func applyContentBlockerRules() async {
        do {
            let ruleLists = try await contentBlockerManager.generateContentBlockerRules()
            
            await MainActor.run {
                for ruleList in ruleLists {
                    webView.configuration.userContentController.add(ruleList)
                }
                Logger.privacy.info("Applied \(ruleLists.count) content blocker rule lists")
            }
        } catch {
            Logger.privacy.error("Failed to apply content blocker rules: \(error)")
            // Fallback to JavaScript-only blocking
            await applyJavaScriptBlockingOnly()
        }
    }
}
```

### ContentBlockerRulesUserScript

To understand which resources were blocked by Content Blocker Rules, we inject JavaScript that monitors network requests and infers blocking behavior:

```swift
final class ContentBlockerRulesUserScript {
    static let source = """
    (function() {
        'use strict';
        
        const blockedResources = new Set();
        const allowedResources = new Set();
        
        // Monitor XMLHttpRequest
        const originalXHROpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url, async, user, password) {
            const startTime = Date.now();
            
            this.addEventListener('loadend', function() {
                const duration = Date.now() - startTime;
                
                if (this.status === 0 && duration < 10) {
                    // Likely blocked by content blocker
                    blockedResources.add(url);
                    reportBlockedResource(url, 'xhr');
                } else {
                    allowedResources.add(url);
                }
            });
            
            return originalXHROpen.call(this, method, url, async, user, password);
        };
        
        // Monitor Fetch API
        const originalFetch = window.fetch;
        window.fetch = function(input, init) {
            const url = typeof input === 'string' ? input : input.url;
            const startTime = Date.now();
            
            return originalFetch.call(this, input, init)
                .then(response => {
                    allowedResources.add(url);
                    return response;
                })
                .catch(error => {
                    const duration = Date.now() - startTime;
                    if (duration < 10) {
                        blockedResources.add(url);
                        reportBlockedResource(url, 'fetch');
                    }
                    throw error;
                });
        };
        
        // Monitor image loading
        const originalImageSrc = Object.getOwnPropertyDescriptor(Image.prototype, 'src');
        Object.defineProperty(Image.prototype, 'src', {
            set: function(value) {
                const img = this;
                
                img.addEventListener('error', function() {
                    if (img.naturalWidth === 0 && img.naturalHeight === 0) {
                        blockedResources.add(value);
                        reportBlockedResource(value, 'image');
                    }
                });
                
                img.addEventListener('load', function() {
                    allowedResources.add(value);
                });
                
                return originalImageSrc.set.call(this, value);
            },
            get: originalImageSrc.get
        });
        
        function reportBlockedResource(url, type) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contentBlocker) {
                window.webkit.messageHandlers.contentBlocker.postMessage({
                    type: 'blocked',
                    url: url,
                    resourceType: type,
                    timestamp: Date.now()
                });
            }
        }
        
        // Report statistics periodically
        setInterval(function() {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contentBlocker) {
                window.webkit.messageHandlers.contentBlocker.postMessage({
                    type: 'statistics',
                    blocked: blockedResources.size,
                    allowed: allowedResources.size,
                    timestamp: Date.now()
                });
            }
        }, 5000);
    })();
    """
}
```

## JavaScript Injection with Tracker Radar

### Purpose and Advantages

While Content Blocker Rules provide excellent performance, they have limitations that JavaScript injection can address:

**JavaScript Injection Advantages:**
- ✅ **Surrogate Support**: Can inject replacement scripts to prevent page breakage
- ✅ **Runtime Logic**: Complex blocking decisions based on page context
- ✅ **Gap Coverage**: Handles edge cases missed by static rules
- ✅ **Real-time Updates**: Can adapt to new tracking techniques
- ❌ **Performance Overhead**: Higher CPU and memory usage
- ❌ **Battery Impact**: More intensive than native blocking

### ContentBlockerUserScript Implementation

The `ContentBlockerUserScript` implements the full Tracker Radar blocking algorithm in JavaScript:

```swift
final class ContentBlockerUserScript {
    private let trackerDataManager: TrackerDataManager
    private let surrogateManager: SurrogateManager
    
    init(trackerDataManager: TrackerDataManager, surrogateManager: SurrogateManager) {
        self.trackerDataManager = trackerDataManager
        self.surrogateManager = surrogateManager
    }
    
    var source: String {
        return generateTrackerBlockingScript()
    }
    
    private func generateTrackerBlockingScript() -> String {
        let trackerData = trackerDataManager.embeddedTrackerData
        let surrogates = surrogateManager.allSurrogates
        
        return """
        (function() {
            'use strict';
            
            // Embedded tracker data
            const TRACKER_DATA = \(trackerData.jsonString);
            const SURROGATES = \(surrogates.jsonString);
            
            class TrackerBlocker {
                constructor() {
                    this.blockedCount = 0;
                    this.allowedCount = 0;
                    this.setupInterception();
                }
                
                setupInterception() {
                    this.interceptXMLHttpRequest();
                    this.interceptFetch();
                    this.interceptScriptLoading();
                    this.interceptImageLoading();
                    this.setupMutationObserver();
                }
                
                shouldBlockResource(url, type, initiator) {
                    try {
                        const urlObj = new URL(url, window.location.href);
                        const domain = urlObj.hostname;
                        
                        // Check if domain is in tracker list
                        const tracker = TRACKER_DATA.trackers[domain];
                        if (!tracker) return false;
                        
                        // Apply tracker rules
                        if (tracker.rules) {
                            for (const rule of tracker.rules) {
                                if (this.matchesRule(url, rule, type)) {
                                    // Check for whitelist exceptions
                                    if (rule.whitelist && this.matchesWhitelist(window.location.hostname, rule.whitelist)) {
                                        return false;
                                    }
                                    return true;
                                }
                            }
                        }
                        
                        return false;
                    } catch (error) {
                        console.warn('Error checking tracker status:', error);
                        return false;
                    }
                }
                
                matchesRule(url, rule, resourceType) {
                    // Simple regex matching for rule.rule
                    try {
                        const regex = new RegExp(rule.rule, 'i');
                        if (!regex.test(url)) return false;
                        
                        // Check resource type restrictions
                        if (rule.resourceTypes && rule.resourceTypes.length > 0) {
                            return rule.resourceTypes.includes(resourceType);
                        }
                        
                        return true;
                    } catch (error) {
                        return false;
                    }
                }
                
                matchesWhitelist(hostname, whitelist) {
                    return whitelist.some(domain => {
                        if (domain.startsWith('*.')) {
                            const suffix = domain.substring(2);
                            return hostname === suffix || hostname.endsWith('.' + suffix);
                        }
                        return hostname === domain;
                    });
                }
                
                getSurrogate(url) {
                    for (const surrogate of SURROGATES) {
                        if (surrogate.matches.some(pattern => {
                            try {
                                const regex = new RegExp(pattern, 'i');
                                return regex.test(url);
                            } catch {
                                return false;
                            }
                        })) {
                            return surrogate.replacement;
                        }
                    }
                    return null;
                }
                
                interceptXMLHttpRequest() {
                    const originalOpen = XMLHttpRequest.prototype.open;
                    const self = this;
                    
                    XMLHttpRequest.prototype.open = function(method, url, async, user, password) {
                        if (self.shouldBlockResource(url, 'xmlhttprequest', 'script')) {
                            self.blockedCount++;
                            self.reportBlocked(url, 'xhr');
                            
                            // Simulate blocked request
                            setTimeout(() => {
                                const event = new Event('error');
                                this.dispatchEvent(event);
                            }, 0);
                            return;
                        }
                        
                        self.allowedCount++;
                        return originalOpen.call(this, method, url, async, user, password);
                    };
                }
                
                interceptFetch() {
                    const originalFetch = window.fetch;
                    const self = this;
                    
                    window.fetch = function(input, init) {
                        const url = typeof input === 'string' ? input : input.url;
                        
                        if (self.shouldBlockResource(url, 'xmlhttprequest', 'script')) {
                            self.blockedCount++;
                            self.reportBlocked(url, 'fetch');
                            return Promise.reject(new TypeError('Failed to fetch'));
                        }
                        
                        self.allowedCount++;
                        return originalFetch.call(this, input, init);
                    };
                }
                
                interceptScriptLoading() {
                    const self = this;
                    const originalCreateElement = document.createElement;
                    
                    document.createElement = function(tagName) {
                        const element = originalCreateElement.call(this, tagName);
                        
                        if (tagName.toLowerCase() === 'script') {
                            const originalSrcSetter = Object.getOwnPropertyDescriptor(HTMLScriptElement.prototype, 'src').set;
                            
                            Object.defineProperty(element, 'src', {
                                set: function(value) {
                                    if (self.shouldBlockResource(value, 'script', 'document')) {
                                        self.blockedCount++;
                                        self.reportBlocked(value, 'script');
                                        
                                        // Check for surrogate
                                        const surrogate = self.getSurrogate(value);
                                        if (surrogate) {
                                            self.injectSurrogate(surrogate);
                                        }
                                        return;
                                    }
                                    
                                    self.allowedCount++;
                                    return originalSrcSetter.call(this, value);
                                },
                                get: function() {
                                    return this.getAttribute('src');
                                }
                            });
                        }
                        
                        return element;
                    };
                }
                
                interceptImageLoading() {
                    const self = this;
                    const originalImageSrc = Object.getOwnPropertyDescriptor(Image.prototype, 'src');
                    
                    Object.defineProperty(Image.prototype, 'src', {
                        set: function(value) {
                            if (self.shouldBlockResource(value, 'image', 'document')) {
                                self.blockedCount++;
                                self.reportBlocked(value, 'image');
                                return;
                            }
                            
                            self.allowedCount++;
                            return originalImageSrc.set.call(this, value);
                        },
                        get: originalImageSrc.get
                    });
                }
                
                setupMutationObserver() {
                    const self = this;
                    const observer = new MutationObserver(function(mutations) {
                        mutations.forEach(function(mutation) {
                            mutation.addedNodes.forEach(function(node) {
                                if (node.nodeType === Node.ELEMENT_NODE) {
                                    self.processNewElement(node);
                                }
                            });
                        });
                    });
                    
                    observer.observe(document.body || document.documentElement, {
                        childList: true,
                        subtree: true
                    });
                }
                
                processNewElement(element) {
                    // Check scripts
                    if (element.tagName === 'SCRIPT' && element.src) {
                        if (this.shouldBlockResource(element.src, 'script', 'document')) {
                            this.blockedCount++;
                            this.reportBlocked(element.src, 'script');
                            element.remove();
                            
                            // Inject surrogate if available
                            const surrogate = this.getSurrogate(element.src);
                            if (surrogate) {
                                this.injectSurrogate(surrogate);
                            }
                        }
                    }
                    
                    // Check images (tracking pixels)
                    if (element.tagName === 'IMG' && element.src) {
                        if (this.shouldBlockResource(element.src, 'image', 'document')) {
                            this.blockedCount++;
                            this.reportBlocked(element.src, 'image');
                            element.remove();
                        }
                    }
                    
                    // Check iframes
                    if (element.tagName === 'IFRAME' && element.src) {
                        if (this.shouldBlockResource(element.src, 'subdocument', 'document')) {
                            this.blockedCount++;
                            this.reportBlocked(element.src, 'iframe');
                            element.remove();
                        }
                    }
                }
                
                injectSurrogate(surrogateCode) {
                    try {
                        const script = document.createElement('script');
                        script.textContent = surrogateCode;
                        script.setAttribute('data-surrogate', 'true');
                        (document.head || document.documentElement).appendChild(script);
                    } catch (error) {
                        console.warn('Failed to inject surrogate:', error);
                    }
                }
                
                reportBlocked(url, type) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.trackerBlocked) {
                        window.webkit.messageHandlers.trackerBlocked.postMessage({
                            url: url,
                            type: type,
                            timestamp: Date.now()
                        });
                    }
                }
                
                getStatistics() {
                    return {
                        blocked: this.blockedCount,
                        allowed: this.allowedCount
                    };
                }
            }
            
            // Initialize tracker blocker
            window.duckduckgoTracker = new TrackerBlocker();
            
            // Report statistics periodically
            setInterval(function() {
                const stats = window.duckduckgoTracker.getStatistics();
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.trackerStats) {
                    window.webkit.messageHandlers.trackerStats.postMessage(stats);
                }
            }, 10000);
            
        })();
        """
    }
}
```

### Surrogate Support

One of the key advantages of JavaScript injection is the ability to provide surrogate scripts that replace blocked trackers to prevent page breakage:

```swift
final class SurrogateManager {
    private let surrogates: [Surrogate]
    
    struct Surrogate: Codable {
        let name: String
        let matches: [String]  // Regex patterns
        let replacement: String  // JavaScript code
    }
    
    var allSurrogates: [Surrogate] {
        return surrogates
    }
    
    init() {
        // Load surrogates from embedded data
        self.surrogates = loadEmbeddedSurrogates()
    }
    
    private func loadEmbeddedSurrogates() -> [Surrogate] {
        // Common surrogates for popular tracking libraries
        return [
            Surrogate(
                name: "Google Tag Manager",
                matches: ["googletagmanager\\.com/gtm\\.js"],
                replacement: """
                window.dataLayer = window.dataLayer || [];
                function gtag(){dataLayer.push(arguments);}
                gtag('js', new Date());
                gtag('config', 'GA_MEASUREMENT_ID', { 'send_page_view': false });
                """
            ),
            Surrogate(
                name: "Google Analytics",
                matches: ["google-analytics\\.com/analytics\\.js", "googletagmanager\\.com/gtag/js"],
                replacement: """
                window.ga = window.ga || function() {
                    (ga.q = ga.q || []).push(arguments);
                };
                ga.l = +new Date;
                ga('create', 'UA-XXXXXXXX-X', 'auto');
                ga('send', 'pageview');
                """
            ),
            Surrogate(
                name: "Facebook Pixel",
                matches: ["connect\\.facebook\\.net/.*?/fbevents\\.js"],
                replacement: """
                window.fbq = function() {};
                window.fbq.push = function() {};
                window.fbq.loaded = true;
                window.fbq.version = '2.0';
                window.fbq.queue = [];
                """
            )
        ]
    }
}
```

## Hybrid Integration Strategy

### Layered Protection Approach

The most effective tracker blocking combines both techniques:

1. **Content Blocker Rules** handle the majority of tracking requests efficiently
2. **JavaScript Injection** provides gap coverage and surrogate support
3. **Message Handlers** coordinate between both layers

```swift
extension BrowserViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "trackerBlocked":
            handleTrackerBlocked(message.body)
        case "trackerStats":
            handleTrackerStatistics(message.body)
        case "contentBlocker":
            handleContentBlockerMessage(message.body)
        default:
            break
        }
    }
    
    private func handleTrackerBlocked(_ messageBody: Any) {
        guard let data = messageBody as? [String: Any],
              let url = data["url"] as? String,
              let type = data["type"] as? String else { return }
        
        // Update privacy dashboard
        privacyDashboard.recordBlockedTracker(url: url, type: type)
        
        // Update UI indicators
        updateTrackerCountIndicator()
        
        Logger.privacy.debug("Blocked tracker: \(url) (\(type))")
    }
    
    private func handleTrackerStatistics(_ messageBody: Any) {
        guard let stats = messageBody as? [String: Any],
              let blocked = stats["blocked"] as? Int,
              let allowed = stats["allowed"] as? Int else { return }
        
        privacyDashboard.updateStatistics(blocked: blocked, allowed: allowed)
    }
}
```

### Configuration and Initialization

The complete setup combines both blocking techniques:

```swift
extension BrowserWebView {
    func setupTrackerBlocking() async {
        let configuration = webView.configuration
        let userContentController = configuration.userContentController
        
        // 1. Apply Content Blocker Rules
        await applyContentBlockerRules()
        
        // 2. Add JavaScript-based blocking
        let contentBlockerScript = WKUserScript(
            source: ContentBlockerUserScript(
                trackerDataManager: trackerDataManager,
                surrogateManager: surrogateManager
            ).source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(contentBlockerScript)
        
        // 3. Add inference script for Content Blocker Rules
        let inferenceScript = WKUserScript(
            source: ContentBlockerRulesUserScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(inferenceScript)
        
        // 4. Register message handlers
        userContentController.add(self, name: "trackerBlocked")
        userContentController.add(self, name: "trackerStats")
        userContentController.add(self, name: "contentBlocker")
        
        Logger.privacy.info("Tracker blocking initialized with hybrid approach")
    }
}
```

## Why Not Content Blocking Extension?

**Content Blocking Extensions** would apply to every WKWebView in iOS system-wide, but we chose our approach for specific reasons:

### UX Control
- **Manual Activation Required**: Content Blocking Extensions require users to manually enable them in Settings
- **Limited User Guidance**: Difficult to provide contextual help for activation
- **Our Approach**: Complete control over blocking state and user experience

### Surrogate Support
- **Extensions Cannot Inject**: Content Blocking Extensions can only block, not replace with surrogates
- **Page Breakage Risk**: Many sites depend on tracking scripts for functionality
- **Our Approach**: Intelligent replacement prevents site breakage

### Dynamic Configuration
- **Static Rules Only**: Extensions cannot modify behavior based on user preferences
- **No A/B Testing**: Cannot experiment with different blocking strategies
- **Our Approach**: Runtime configuration and experimentation capability

## Performance Considerations

### Memory Usage
```swift
class TrackerBlockingPerformanceMonitor {
    private var lastMemoryWarning: Date?
    
    func optimizeForMemoryPressure() {
        // Reduce JavaScript blocker complexity under memory pressure
        if let lastWarning = lastMemoryWarning,
           Date().timeIntervalSince(lastWarning) < 60 {
            // Rely more heavily on Content Blocker Rules
            disableComplexJavaScriptBlocking()
        }
    }
    
    func handleMemoryWarning() {
        lastMemoryWarning = Date()
        
        // Clear caches
        trackerDataManager.clearCache()
        surrogateManager.clearCache()
        
        // Temporarily disable non-essential blocking
        temporarilyReduceBlockingComplexity()
    }
}
```

### Battery Impact Monitoring
```swift
extension BrowserViewController {
    func monitorBlockingPerformance() {
        // Monitor JavaScript execution time
        let startTime = CFAbsoluteTimeGetCurrent()
        
        webView.evaluateJavaScript("window.duckduckgoTracker.getStatistics()") { result, error in
            let executionTime = CFAbsoluteTimeGetCurrent() - startTime
            
            if executionTime > 0.1 {  // 100ms threshold
                Logger.privacy.warning("Tracker blocking JS execution time: \(executionTime)s")
                // Consider optimizing or reducing complexity
            }
        }
    }
}
```

## Testing and Debugging

### Unit Testing Content Blocker Rules
```swift
class ContentBlockerRulesTests: XCTestCase {
    func testTrackerDataConversion() async throws {
        let mockTrackerData = TrackerData.mock
        let rulesManager = ContentBlockerRulesManager(trackerDataManager: MockTrackerDataManager(data: mockTrackerData))
        
        let rules = try await rulesManager.generateContentBlockerRules()
        
        XCTAssertFalse(rules.isEmpty)
        XCTAssertEqual(rules.count, 1)
    }
    
    func testRuleCompilation() async throws {
        let simpleRule = [
            [
                "trigger": [
                    "url-filter": ".*tracker\\.com.*"
                ],
                "action": [
                    "type": "block"
                ]
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: simpleRule)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let ruleList = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "test",
                encodedContentRuleList: jsonString
            ) { ruleList, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let ruleList = ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: ContentBlockerError.compilationFailed)
                }
            }
        }
        
        XCTAssertNotNil(ruleList)
    }
}
```

### UI Testing with Tracker Blocking
```swift
class TrackerBlockingUITests: XCTestCase {
    func testTrackerCounterUpdates() {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to a page with known trackers
        app.textFields["urlField"].tap()
        app.textFields["urlField"].typeText("https://example.com/page-with-trackers")
        app.buttons["Go"].tap()
        
        // Wait for page load and blocking to take effect
        sleep(3)
        
        // Check that tracker counter updated
        let trackerCounter = app.staticTexts["trackerCount"]
        XCTAssertTrue(trackerCounter.exists)
        
        let counterText = trackerCounter.label
        XCTAssertTrue(counterText.contains("blocked"))
    }
}
```

## Maintenance and Updates

### Tracker Radar Updates
```swift
class TrackerDataUpdateManager {
    func checkForUpdates() async {
        let latestVersion = try await fetchLatestTrackerDataVersion()
        let currentVersion = trackerDataManager.currentVersion
        
        if latestVersion > currentVersion {
            await downloadAndApplyUpdate(version: latestVersion)
        }
    }
    
    private func downloadAndApplyUpdate(version: String) async {
        do {
            let newTrackerData = try await downloadTrackerData(version: version)
            
            // Validate data integrity
            guard validateTrackerData(newTrackerData) else {
                throw TrackerDataError.invalidData
            }
            
            // Apply update
            trackerDataManager.updateData(newTrackerData)
            
            // Regenerate Content Blocker Rules
            await regenerateContentBlockerRules()
            
            Logger.privacy.info("Updated tracker data to version \(version)")
        } catch {
            Logger.privacy.error("Failed to update tracker data: \(error)")
        }
    }
}
```

## Conclusion

The iOS tracker blocking implementation provides comprehensive protection through a sophisticated dual-layer approach:

- **Content Blocker Rules** deliver high-performance blocking for the majority of tracking attempts
- **JavaScript injection** ensures complete coverage and enables advanced features like surrogates
- **Hybrid coordination** maximizes both performance and protection effectiveness

This architecture gives us complete control over the user experience while maintaining the privacy protection that DuckDuckGo users expect, without the limitations of system-wide Content Blocking Extensions.

**Key Benefits:**
- ✅ **Performance**: WebKit-optimized native blocking for most requests
- ✅ **Completeness**: JavaScript layer catches edge cases and provides surrogates
- ✅ **Control**: Full UX control without requiring manual user configuration
- ✅ **Flexibility**: Runtime configuration and A/B testing capabilities
- ✅ **Maintenance**: Easy updates and improvements to blocking logic

This implementation forms the foundation of DuckDuckGo's iOS privacy protection, ensuring users browse with confidence knowing their privacy is protected by industry-leading tracker blocking technology. 