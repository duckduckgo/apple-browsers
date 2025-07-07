# iOS Subscription Features

## Overview
The iOS subscription implementation provides access to premium features including VPN, Personal Information Removal, and Identity Theft Restoration services. This module handles subscription purchase, restoration, and management within the iOS app.

**Purchase Methods**: 
- **App Store**: Default purchase method (all regions)
- **Stripe**: Available when `iosStripeSubscriptions` feature flag is enabled

## Features Included
- **VPN (Network Protection)**: Secure VPN service
- **Personal Information Removal (PIR)**: Data broker scanning and removal
- **Identity Theft Restoration (ITR)**: Identity protection services
- **AI Chat**: Premium AI assistant features

## Architecture

### Core Components

#### View Models
- **SubscriptionFlowViewModel** - Main subscription flow orchestration
- **SubscriptionSettingsViewModel** - Subscription management UI
- **SubscriptionRestoreViewModel** - Subscription restoration handling
- **SubscriptionEmailViewModel** - Email-based subscription activation
- **SubscriptionPIRViewModel** - Personal Information Removal features
- **SubscriptionITPViewModel** - Identity Theft Protection features

#### Views
- **SubscriptionContainerView** - Main subscription UI container
- **SubscriptionFlowView** - Purchase flow interface
- **SubscriptionSettingsView** - Settings and management
- **SubscriptionRestoreView** - Restoration interface
- **SubscriptionAIChatView** - AI Chat subscription features
- **PurchaseInProgressView** - Purchase status indicator

#### Navigation
- **SubscriptionNavigationCoordinator** - Handles subscription-related navigation
- **SubscriptionURLNavigationHandler** - URL scheme handling for subscriptions

### Integration with BrowserServicesKit

The iOS app uses the shared [Subscription module from BrowserServicesKit](../../../SharedPackages/BrowserServicesKit/Sources/Subscription/SUBSCRIPTION.md) for:
- Core subscription management logic
- Authentication and token handling
- API communication
- Purchase flow orchestration
- Cookie management

### User Scripts
- **SubscriptionPagesUserScript** - JavaScript bridge for subscription web pages
- **IdentityTheftRestorationPagesUserScript** - ITR-specific web page handling
- **SubscriptionPagesUseSubscriptionFeature** - Feature detection and enablement

### Platform-Specific Features

#### Headless WebView
- **AsyncHeadlessWebView** - Background web operations
- **HeadlessWebViewCoordinator** - WebView lifecycle management
- Used for secure authentication flows

#### Privacy Pro Data Reporting
- **PrivacyProDataReporting** - Analytics and reporting
- **DefaultMetadataCollector** - Metadata collection for diagnostics
- **VPNMetadataCollector** - VPN-specific metrics

#### Free Trials
- **SubscriptionFreeTrialsHelper** - Trial eligibility and management
- Feature flag controlled: `privacyProFreeTrial`
- Supports introductory offers from App Store
- Trial eligibility checked per product
- Automatic trial status updates after purchase/restore

### Configuration
- **SubscriptionEnvironment+Default** - Dynamic platform selection based on feature flags
- **SubscriptionFeatureFlagMapping** - Feature flag integration
- **DataBrokerProtectionSettings+Environment** - PIR environment setup
- **VPNSettings+Environment** - VPN configuration

### Feature Flags
- **iosStripeSubscriptions** - Enables Stripe purchases on iOS (replaces App Store as default)
- **privacyProFreeTrial** - Enables free trial offers
- **DBPSubfeature.freemium** - Enables freemium PIR features (US only)

### Assets
Located in `Subscription.xcassets/`:
- Subscription-related icons and images
- Platform-specific imagery (Apple, Windows, Google Play)
- Feature illustrations

## Purchase Flow

**iOS supports both App Store and Stripe purchases**. Platform selection is automatic based on remote feature flag.

1. User initiates subscription from settings or promotional screen
2. Platform determined by `SubscriptionEnvironment.default` based on feature flag
3. `SubscriptionFlowViewModel` presents appropriate purchase options
4. Free trial eligibility checked if feature flag enabled
5. Purchase flow via App Store or Stripe depending on configuration
6. Authentication handled by `SubscriptionManager`
7. Entitlements synchronized via API
8. Features enabled based on subscription status

### Free Trial Flow
- Trial availability determined by:
  - Feature flag: `privacyProFreeTrial`
  - App Store introductory offer eligibility
  - No previous free trial usage (can have had previous subscriptions)
- Trial period defined by App Store product configuration
- Automatic conversion to paid subscription after trial

## Restoration Flow

1. User selects "Restore Purchase"
2. `SubscriptionRestoreViewModel` initiates restoration
3. App Store receipt validation
4. Server-side entitlement verification
5. Local state updated

## External Activation

iOS supports subscription activation from multiple sources:
- **Cross-platform purchases**: Users who purchased via Stripe on other platforms can activate on iOS
- **Email-based activation**: Subscription activated via email links
- **Web-based purchases**: Cross-platform subscription management
- **Account restoration**: Syncing subscriptions across devices

Note: iOS now supports both App Store and Stripe purchases natively, plus activation of subscriptions purchased on other platforms.

## Pixel Events
- **AuthV2PixelHandler** - Authentication-related analytics
- **SubscriptionCookieManageEventPixelMapping** - Cookie management events

## Key Integrations

### VPN Integration
- Coordinates with VPN module for Network Protection
- Handles VPN entitlement checks
- Manages VPN configuration based on subscription

### Data Broker Protection
- Enables PIR features when subscribed
- Manages scan scheduling
- Handles removal requests

### Identity Theft Restoration
- Provides access to ITR services
- Manages ITR web interface
- Handles secure communication

## Development Guidelines

### Adding New Features
1. Update entitlement checks in `SubscriptionManager`
2. Add UI components in appropriate Views directory
3. Update `SubscriptionFlowViewModel` if needed
4. Add pixel events for analytics

### Testing
- Unit tests in `iOS/DuckDuckGoTests/Subscription/`
- Mock subscription states for development
- Test purchase and restoration flows

### Important Files
- `Subscription.swift` - Core subscription definitions
- `SubscriptionURLNavigationHandler.swift` - URL scheme handling
- `DefaultSubscriptionManager+AccountManagerKeychainAccessDelegate.swift` - Keychain integration

## Common Issues & Solutions

### Purchase Issues
- **"Cannot connect to iTunes Store"**: Check network connectivity and App Store status
- **Restoration fails**: Ensure user is signed into same Apple ID used for purchase
- **Stripe activation fails**: Verify feature flag is enabled and authentication token is valid

### Development Tips
- Use sandbox environment for testing purchases
- Test with multiple Apple IDs for trial eligibility
- Monitor console logs for detailed error messages
- Check keychain access for token storage issues

## Related Documentation
- [BrowserServicesKit Subscription](../../../SharedPackages/BrowserServicesKit/Sources/Subscription/SUBSCRIPTION.md)
- [Main iOS Documentation](../CLAUDE.md)