# BrowserServicesKit Subscription Module

## Overview
The Subscription module in BrowserServicesKit provides the core subscription infrastructure shared between iOS and macOS DuckDuckGo applications. It handles authentication, purchase flows, entitlement management, and API communication for premium features.

## Table of Contents
- [Architecture](#architecture)
- [Premium Features](#premium-features)
- [Integration Guide](#integration-guide)
- [Security Considerations](#security-considerations)
- [Testing](#testing)
- [Platform Differences](#platform-differences)

## Architecture

### Core Managers

#### SubscriptionManager
Central subscription state management:
- **SubscriptionManager** - Legacy V1 implementation
- **SubscriptionManagerV2** - Current V2 implementation with enhanced features
- **SubscriptionAuthV1toV2Bridge** - Migration support between versions
- Handles authentication state
- Manages entitlements
- Coordinates with platform-specific implementations

#### StorePurchaseManager
App Store integration:
- **StorePurchaseManager** - Legacy purchase handling
- **StorePurchaseManagerV2** - Current StoreKit 2 implementation
- **ProductFetching** - Product catalog retrieval
- **SubscriptionProduct** - Product model with pricing
- Manages in-app purchases
- Handles receipt validation

#### AccountManager
User account management:
- Authentication token handling
- Account state persistence
- Token refresh logic
- Secure credential storage

### API Services

#### Core Services
- **SubscriptionAPIService** - Main API client
- **SubscriptionEndpointService** - V1 endpoints
- **SubscriptionEndpointServiceV2** - V2 endpoints with enhanced features
- **AuthEndpointService** - Authentication endpoints

#### Models
- **PrivacyProSubscription** - Subscription data model
- **Entitlement** - Feature entitlement model
- **SubscriptionOptions** - Available subscription tiers
- **SubscriptionOptionsV2** - Enhanced subscription options

### Storage

#### V1 Storage (Legacy)
- **AccountKeychainStorage** - Account data in keychain
- **SubscriptionTokenKeychainStorage** - Token storage
- Platform-specific keychain integration

#### V2 Storage (Current)
- **SubscriptionTokenKeychainStorageV2** - Enhanced token storage
- **SubscriptionTokenKeychainStorage+LegacyAuthTokenStoring** - Migration support
- Improved security and reliability

### Purchase Flows

#### App Store Flows
- **AppStorePurchaseFlow** - Legacy purchase flow
- **AppStorePurchaseFlowV2** - StoreKit 2 purchase flow
- **AppStoreRestoreFlow** - Legacy restoration
- **AppStoreRestoreFlowV2** - StoreKit 2 restoration
- **AppStoreAccountManagementFlow** - Subscription management

#### Stripe Flows
- **StripePurchaseFlow** - Web-based purchases
- **StripePurchaseFlowV2** - Enhanced Stripe integration
- External purchase activation

### Product Features
- **SubscriptionProduct** - Product model with localized pricing and trial info
- **SubscriptionProductIntroductoryOffer** - Free trial period configuration
- **isEligibleForFreeTrial** - Real-time trial eligibility checking
- **isFreeTrialProduct** - Identifies products with trial offers
- **checkFreshFreeTrialEligibility()** - Server-side eligibility verification
- **refreshFreeTrialEligibility()** - Updates cached eligibility status

### Cookie Management
- **SubscriptionCookieManager** - Legacy cookie handling
- **SubscriptionCookieManagerV2** - Current implementation
- **HTTPCookieStore** - Cookie storage interface
- Synchronizes authentication across web views

### Feature Management

#### Feature Flags
- **SubscriptionFeatureFlags** - Feature toggle management
- **FeatureFlaggerMapping** - Remote configuration
- A/B testing support

#### Feature Mapping
- **SubscriptionFeatureMappingCache** - V1 feature cache
- **SubscriptionFeatureMappingCacheV2** - V2 enhanced caching
- **SubscriptionFeatureV2** - Feature definitions
- Maps entitlements to features

### User Scripts
- **SubscriptionUserScript** - JavaScript bridge
- Web page integration
- Secure communication channel
- Feature detection in web content

## Premium Features

### Supported Entitlements
1. **Network Protection (VPN)**
   - Secure VPN service
   - Device-wide protection
   - Multiple server locations

2. **Personal Information Removal**
   - Data broker scanning
   - Automated removal requests
   - Progress tracking
   - Freemium tier available (limited scanning)

3. **Identity Theft Restoration**
   - Identity monitoring
   - Restoration services
   - Expert assistance

4. **AI Chat**
   - Premium AI features
   - Enhanced capabilities

## Integration Guide

### Platform & Purchase Method Overview

#### iOS
- **Purchase Method**: App Store only
- **Geographic Availability**: US and international territories
- **Cross-Platform**: Can activate Stripe-purchased subscriptions from other platforms

#### macOS App Store Build
- **Purchase Method**: App Store only  
- **Geographic Availability**: US and international territories
- **Cross-Platform**: Can activate Stripe-purchased subscriptions

#### macOS Direct Download Build
- **US Users**: Stripe purchases
- **Non-US Users**: Redirected to iOS app for App Store purchase
- **Cross-Platform**: Primary platform for Stripe purchases

### iOS Integration
```swift
// Initialize subscription manager (App Store only)
let subscriptionManager = SubscriptionManagerV2(
    storePurchaseManager: storePurchaseManager,
    accountManager: accountManager,
    subscriptionEndpointService: endpointService
)

// Check subscription status
let isSubscribed = subscriptionManager.isUserSubscribed
let entitlements = subscriptionManager.entitlements
```

### macOS Integration
```swift
// Configure subscription environment (supports both App Store and Stripe)
SubscriptionEnvironment.default.configure()

// Handle subscription URLs (important for Stripe activation)
subscriptionManager.handleSubscriptionURL(url)

// Check purchase platform
if subscriptionManager.currentEnvironment.purchasePlatform == .stripe {
    // Handle Stripe-specific logic
} else {
    // Handle App Store logic
}
```

### Common Tasks

#### Checking Entitlements
```swift
if subscriptionManager.hasEntitlement(for: .networkProtection) {
    // Enable VPN features
}
```

#### Purchase Flow
```swift
let flow = AppStorePurchaseFlowV2(subscriptionManager: manager)
flow.purchase(productId: "monthly_subscription") { result in
    // Handle purchase result
}
```

#### Restoration
```swift
let restoreFlow = AppStoreRestoreFlowV2(subscriptionManager: manager)
restoreFlow.restoreSubscription { result in
    // Handle restoration result
}
```

## Security Considerations

### Token Management
- Tokens stored in platform keychain
- Automatic refresh before expiration
- Secure token exchange protocol

### API Communication
- Certificate pinning
- End-to-end encryption for sensitive data
- Rate limiting and retry logic

### Privacy
- No tracking of subscription usage
- Minimal data collection
- Anonymous analytics only

## Testing

### Mock Implementations
Available in `SubscriptionTestingUtilities`:
- `SubscriptionManagerMock`
- `StorePurchaseManagerMock`
- `MockSubscriptionUserScriptHandler`

### Test Scenarios
- Purchase flow testing
- Restoration testing
- Token expiration handling
- Network error scenarios

## Error Handling

### Common Errors
- Network connectivity issues
- Invalid purchase receipts
- Expired tokens
- Server validation failures

### Recovery Strategies
- Automatic token refresh
- Receipt revalidation
- Offline entitlement caching
- Graceful degradation

## Platform Differences

### iOS Specific
- **Purchase Method**: App Store only (StoreKit)
- **Integration**: UIKit-based subscription UI
- **Keychain**: iOS keychain for secure storage
- **Testing**: App Store sandbox environment
- **Cross-Platform**: Can activate Stripe purchases from other platforms

### macOS Specific
- **Purchase Method**: App Store (StoreKit) or Stripe depending on build
- **Integration**: AppKit with some SwiftUI components
- **System Extensions**: VPN and network protection require elevated privileges
- **Menu Bar**: Subscription status in menu bar
- **Build Variants**: 
  - App Store build: StoreKit purchases only
  - Direct download build: Stripe (US) or iOS redirect (non-US)

## Free Trials

### Overview
BrowserServicesKit provides comprehensive free trial support:
- App Store introductory offers with automatic conversion
- Eligibility tracking per Apple ID (one free trial per Apple ID)
- Automatic trial status updates via StoreKit
- Platform-agnostic trial logic with UI handled by client apps

### Implementation
- **SubscriptionProduct.isEligibleForFreeTrial** - Current eligibility status
- **SubscriptionProduct.checkFreshFreeTrialEligibility()** - Real-time eligibility check
- **SubscriptionProduct.refreshFreeTrialEligibility()** - Updates stored status
- **SubscriptionProductIntroductoryOffer** - Trial period configuration

### Trial Flow
1. Product fetched with trial offer details
2. Eligibility checked against Apple ID history (no previous free trial)
3. Trial pricing displayed in UI
4. Purchase initiated with trial terms
5. Automatic conversion after trial period

Note: Users can have had previous paid subscriptions and still be eligible for a free trial, as long as they haven't used a free trial before.

## Freemium Features

### Personal Information Removal (PIR)
The subscription module supports a freemium tier for PIR:
- Limited functionality for non-subscribers
- Scanning capabilities without removal
- Upgrade prompts integrated
- Feature flag controlled: `DBPSubfeature.freemium`
- **Geographic Restriction**: US-only (follows Stripe availability)

### Integration Points
- Platform-specific implementations handle UI
- Core logic remains in BrowserServicesKit
- Entitlement checks differentiate tiers
- Analytics track freemium usage
- Region detection for eligibility

## Purchase Platform Details

### App Store (StoreKit)
- **Availability**: iOS (all regions), macOS App Store build (all regions)
- **Payment Methods**: Credit cards, Apple Pay, Apple ID balance
- **Free Trials**: Via App Store introductory offers
- **Receipt Validation**: Apple-provided receipts
- **International**: Supports multiple currencies and regions

### Stripe
- **Availability**: macOS Direct Download build (US only)
- **Payment Methods**: Credit cards, some regional payment methods
- **Free Trials**: Limited Stripe trial configuration (US only)
- **Receipt Validation**: Stripe webhook validation
- **International**: Currently US-focused, non-US users redirected to iOS

### Cross-Platform Subscription Sync
- Stripe purchases can be activated on iOS/macOS App Store builds
- App Store purchases can be activated on macOS Direct Download builds
- Unified entitlement system across all platforms
- Account-based subscription management

## Future Enhancements
- Additional payment methods (PayPal, local payment providers)
- Enhanced offline support with longer entitlement caching
- Improved synchronization with better conflict resolution
- New premium features based on user feedback
- Expanded freemium offerings to more features and regions
- Better error recovery mechanisms
- Enhanced analytics while maintaining privacy

## Related Documentation
- [iOS Subscription Implementation](../../../../iOS/DuckDuckGo/Subscription/SUBSCRIPTION.md)
- [macOS Subscription Implementation](../../../../macOS/DuckDuckGo/Subscription/SUBSCRIPTION.md)
- [BrowserServicesKit Overview](../CLAUDE.md)