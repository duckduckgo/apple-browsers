---
title: "Subscription Architecture & Implementation"
description: "Comprehensive guide for subscription feature implementation across iOS, macOS, and BrowserServicesKit including purchase flows, platform differences, and feature integration"
keywords: ["subscription", "premium features", "VPN", "PIR", "ITR", "App Store", "Stripe", "purchase flow", "entitlements", "authentication"]
alwaysApply: false
---

# Subscription Architecture & Implementation

## Overview
DuckDuckGo's subscription system provides access to premium features including VPN (Network Protection), Personal Information Removal (PIR), Identity Theft Restoration (ITR), and AI Chat. The system supports multiple purchase platforms and cross-platform activation.

## Core Architecture

### Shared Foundation: BrowserServicesKit
All subscription logic is centralized in `BrowserServicesKit/Sources/Subscription/`:

```swift
// ✅ CORRECT - Use BrowserServicesKit for core subscription logic
import BrowserServicesKit

final class SubscriptionViewModel: ObservableObject {
    private let subscriptionManager: SubscriptionManager
    
    init(subscriptionManager: SubscriptionManager = SubscriptionManager.shared) {
        self.subscriptionManager = subscriptionManager
    }
}

// ❌ INCORRECT - Don't duplicate subscription logic in platform code
final class SubscriptionViewModel: ObservableObject {
    func checkSubscriptionStatus() {
        // Don't reimplement subscription logic
    }
}
```

### Platform-Specific Purchase Methods

#### iOS
- **Purchase Method**: App Store only (StoreKit)
- **Geographic Coverage**: Global
- **Cross-Platform**: Can activate Stripe subscriptions from other platforms

#### macOS App Store Build
- **Purchase Method**: App Store only (StoreKit)
- **Geographic Coverage**: Global
- **Cross-Platform**: Can activate Stripe subscriptions

#### macOS Direct Download Build
- **US Users**: Stripe web purchases
- **Non-US Users**: Redirected to iOS App Store
- **Cross-Platform**: Primary platform for Stripe purchases

### Version Management
ALWAYS use V2 implementations for new code:

```swift
// ✅ CORRECT - Use V2 implementations
let subscriptionManager = SubscriptionManagerV2()
let purchaseManager = StorePurchaseManagerV2()
let purchaseFlow = AppStorePurchaseFlowV2()

// ❌ INCORRECT - Don't use V1 implementations
let subscriptionManager = SubscriptionManager() // Legacy
let purchaseFlow = AppStorePurchaseFlow() // Legacy
```

## Premium Features Implementation

### Feature Entitlements
```swift
// ✅ CORRECT - Check entitlements through SubscriptionManager
final class FeatureViewModel: ObservableObject {
    private let subscriptionManager: SubscriptionManager
    
    var isFeatureEnabled: Bool {
        subscriptionManager.hasEntitlement(for: .networkProtection)
    }
    
    var availableFeatures: [SubscriptionFeature] {
        subscriptionManager.entitlements.compactMap { entitlement in
            switch entitlement {
            case .networkProtection:
                return .vpn
            case .dataBrokerProtection:
                return .personalInformationRemoval
            case .identityTheftRestoration:
                return .identityTheftRestoration
            default:
                return nil
            }
        }
    }
}
```

### VPN Integration
```swift
// ✅ CORRECT - VPN entitlement integration
final class VPNManager: ObservableObject {
    private let subscriptionManager: SubscriptionManager
    
    func enableVPN() async {
        guard subscriptionManager.hasEntitlement(for: .networkProtection) else {
            await showSubscriptionPrompt()
            return
        }
        
        // Enable VPN functionality
        await startVPNConnection()
    }
}
```

### Personal Information Removal (PIR)
```swift
// ✅ CORRECT - PIR implementation with freemium support
final class PIRManager: ObservableObject {
    private let subscriptionManager: SubscriptionManager
    
    var isFreemiumEligible: Bool {
        // Check feature flag and eligibility
        FeatureFlags.shared.isEnabled(.freemiumPIR) &&
        !subscriptionManager.isUserSubscribed &&
        isUSUser
    }
    
    func performScan() async {
        if subscriptionManager.hasEntitlement(for: .dataBrokerProtection) {
            await performFullScan()
        } else if isFreemiumEligible {
            await performLimitedScan()
        } else {
            await showSubscriptionPrompt()
        }
    }
}
```

## Purchase Flow Implementation

### Free Trial Support
```swift
// ✅ CORRECT - Free trial implementation
final class SubscriptionPurchaseViewModel: ObservableObject {
    @Published var isTrialEligible = false
    @Published var trialPeriod: String = ""
    
    func checkTrialEligibility() async {
        guard FeatureFlags.shared.isEnabled(.privacyProFreeTrial) else {
            isTrialEligible = false
            return
        }
        
        // Check server-side eligibility
        let eligible = await subscriptionManager.checkFreshFreeTrialEligibility()
        await MainActor.run {
            isTrialEligible = eligible
            if let product = subscriptionManager.currentProduct,
               let offer = product.introductoryOffer {
                trialPeriod = offer.localizedPeriod
            }
        }
    }
}
```

### Platform-Specific Purchase
```swift
// ✅ CORRECT - Platform-aware purchase flow
final class PurchaseFlowCoordinator {
    private let subscriptionManager: SubscriptionManager
    
    func initiatePurchase() async {
        #if os(iOS)
        // iOS always uses App Store
        await purchaseViaAppStore()
        #elseif os(macOS)
        if Bundle.main.isMacAppStore {
            await purchaseViaAppStore()
        } else {
            // Direct download build
            if isUSUser {
                await purchaseViaStripe()
            } else {
                await redirectToiOSApp()
            }
        }
        #endif
    }
}
```

## Cross-Platform Activation

### URL Handling
```swift
// ✅ CORRECT - Subscription URL handling
final class SubscriptionURLHandler {
    func handleSubscriptionURL(_ url: URL) {
        guard url.scheme == "duckduckgo",
              url.host == "subscription" else { return }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        
        if let token = components?.queryItems?.first(where: { $0.name == "token" })?.value {
            Task {
                await subscriptionManager.activateSubscription(with: token)
            }
        }
    }
}
```

### Authentication Bridge
```swift
// ✅ CORRECT - V1 to V2 authentication migration
final class AuthenticationManager {
    func migrateToV2() async {
        let bridge = SubscriptionAuthV1toV2Bridge()
        
        if let v1Token = await bridge.extractV1Token() {
            await subscriptionManager.migrateFromV1(token: v1Token)
        }
    }
}
```

## Testing Patterns

### Mock Subscription Manager
```swift
// ✅ CORRECT - Mock for testing
final class MockSubscriptionManager: SubscriptionManager {
    var mockEntitlements: [SubscriptionEntitlement] = []
    var mockSubscriptionStatus: Bool = false
    
    override var isUserSubscribed: Bool {
        mockSubscriptionStatus
    }
    
    override var entitlements: [SubscriptionEntitlement] {
        mockEntitlements
    }
    
    override func hasEntitlement(for feature: SubscriptionFeature) -> Bool {
        mockEntitlements.contains(where: { $0.feature == feature })
    }
}
```

### Test Subscription States
```swift
// ✅ CORRECT - Test different subscription states
final class SubscriptionViewModelTests: XCTestCase {
    private var viewModel: SubscriptionViewModel!
    private var mockManager: MockSubscriptionManager!
    
    func testSubscribedUser() {
        // Given
        mockManager.mockSubscriptionStatus = true
        mockManager.mockEntitlements = [.networkProtection, .dataBrokerProtection]
        
        // When
        viewModel.checkSubscriptionStatus()
        
        // Then
        XCTAssertTrue(viewModel.isSubscribed)
        XCTAssertTrue(viewModel.hasVPNAccess)
        XCTAssertTrue(viewModel.hasPIRAccess)
    }
    
    func testFreeTrialEligibility() async {
        // Given
        FeatureFlags.shared.enable(.privacyProFreeTrial)
        mockManager.mockTrialEligibility = true
        
        // When
        await viewModel.checkTrialEligibility()
        
        // Then
        XCTAssertTrue(viewModel.isTrialEligible)
    }
}
```

## Feature Flags and Configuration

### Subscription Feature Flags
```swift
// ✅ CORRECT - Feature flag usage
enum SubscriptionFeatureFlag: String, CaseIterable {
    case privacyProFreeTrial = "privacyProFreeTrial"
    case iosStripeSubscriptions = "iosStripeSubscriptions"
    case freemiumPIR = "DBPSubfeature.freemium"
    
    var isEnabled: Bool {
        FeatureFlags.shared.isEnabled(self)
    }
}
```

### Environment Configuration
```swift
// ✅ CORRECT - Environment-based configuration
extension SubscriptionEnvironment {
    static var `default`: SubscriptionEnvironment {
        #if os(iOS)
        // iOS always uses App Store
        return .appStore
        #elseif os(macOS)
        if Bundle.main.isMacAppStore {
            return .appStore
        } else {
            return FeatureFlags.shared.isEnabled(.iosStripeSubscriptions) ? .stripe : .appStore
        }
        #endif
    }
}
```

## Analytics and Tracking

### Subscription Pixels
```swift
// ✅ CORRECT - Analytics implementation
final class SubscriptionAnalytics {
    func trackPurchaseFlow(origin: SubscriptionFunnelOrigin) {
        PixelKit.fire(
            pixel: .subscriptionPurchaseFlowStarted,
            parameters: [
                "origin": origin.rawValue,
                "platform": currentPlatform.rawValue
            ]
        )
    }
    
    func trackTrialEligibility(eligible: Bool) {
        PixelKit.fire(
            pixel: .subscriptionTrialEligibilityCheck,
            parameters: [
                "eligible": eligible.description
            ]
        )
    }
}
```

## Important Implementation Notes

### Security Considerations
- Store authentication tokens in Keychain only
- Use HTTPS for all subscription API calls
- Validate receipts server-side
- Implement proper token refresh logic

### Performance Optimization
- Cache subscription status locally
- Use background queues for API calls
- Implement offline capability for cached states
- Minimize UI blocking operations

### User Experience
- Provide clear trial information
- Handle purchase failures gracefully
- Support subscription restoration
- Maintain consistent UI across platforms

### Common Pitfalls to Avoid
- Don't hardcode subscription URLs
- Don't bypass entitlement checks
- Don't duplicate subscription logic across platforms
- Don't ignore V1 to V2 migration paths
- Don't forget to handle cross-platform activation 