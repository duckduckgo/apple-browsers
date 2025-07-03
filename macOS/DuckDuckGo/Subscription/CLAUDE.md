# macOS Subscription Features

## Overview
The macOS subscription implementation provides desktop access to premium features including VPN, Personal Information Removal, and Identity Theft Restoration services. This module handles subscription management, activation, and integration with the native macOS experience.

## Distribution & Purchase Methods

| Build Type | Purchase Method | Geographic Availability |
|------------|-----------------|------------------------|
| App Store | App Store (StoreKit) | US and international territories |
| Direct Download | Stripe | US only |
| Direct Download | iOS Redirect | Non-US users |

## Features Included
- **VPN (Network Protection)**: System-wide VPN protection
- **Personal Information Removal (PIR)**: Data broker scanning and removal
  - Full access with subscription
  - Limited Freemium version available (see Freemium PIR below)
- **Identity Theft Restoration (ITR)**: Identity protection services
- **AI Chat**: Premium AI assistant features

## Architecture

### Core Components

#### Coordination
- **SubscriptionNavigationCoordinator** - Manages subscription-related navigation and tab handling
- **SubscriptionRedirectManager** - Handles subscription URL redirects
- **SubscriptionUIHandler** - UI state management for subscription features

#### Configuration
- **SubscriptionManager+StandardConfiguration** - Standard subscription setup
- **SubscriptionEnvironment+Default** - Environment configuration
- **DefaultSubscriptionFeatureAvailability+DefaultInitializer** - Feature availability checks

#### Analytics
- **SubscriptionAttributionPixelHandler** - Attribution tracking
- **AuthV2PixelHandler** - Authentication event tracking
- **SubscriptionCookieManageEventPixelMapping** - Cookie management analytics

### Integration with BrowserServicesKit

The macOS app leverages the shared [Subscription module from BrowserServicesKit](../../../SharedPackages/BrowserServicesKit/Sources/Subscription/SUBSCRIPTION.md) for:
- Core subscription management
- Authentication and token handling
- API communication
- Purchase and restoration flows
- Cookie synchronization

### User Scripts

Located in `Tab/UserScripts/Subscription/`:
- **SubscriptionPagesUseSubscriptionFeature** - Web page subscription integration
- **SubscriptionPagesUseSubscriptionFeatureV2** - Enhanced subscription features
- **IdentityTheftRestorationPagesUserScript** - ITR web interface handling

### Platform-Specific Features

#### System Integration
- Native macOS menu bar integration
- System-level VPN configuration
- Keychain integration for secure storage
- Background agent support for PIR

#### Multi-Window Support
- Subscription UI can open in separate windows
- Coordinated state across windows
- Deep linking support

#### Data Broker Protection Integration
- **DataBrokerProtectionSettings+Environment** - PIR environment setup
- Background scanning capabilities
- System notifications for scan results

#### VPN Integration
- **VPNSettings+Environment** - VPN configuration
- System extension management
- Network protection status in menu bar

### Navigation Flow

The `SubscriptionNavigationCoordinator` handles:
1. Opening subscription management in new tabs
2. Handling subscription-related URLs
3. Managing authentication flows
4. Coordinating between web and native UI

### Subscription Origins

Tracked via `SubscriptionFunnelOrigin`:
- Settings menu
- VPN prompt
- PIR feature discovery
- Promotional banners
- Web-based activation

## Purchase & Activation Flow

### App Store Build Purchase
1. User initiates from settings or feature prompt
2. Native App Store purchase UI presented
3. App Store transaction processed
4. Server validation via BrowserServicesKit
5. Features enabled system-wide

### Direct Download Build Purchase

#### US Users (Stripe)
1. User initiates subscription
2. Stripe web-based purchase flow
3. Payment processed via Stripe
4. Server validation and account creation
5. Features enabled system-wide

#### Non-US Users (Redirect to iOS)
1. User attempts to purchase subscription
2. System detects non-US region
3. User redirected to download iOS app
4. Purchase completed via iOS App Store
5. Subscription activated on macOS via account sync

### Cross-Platform Activation
1. User purchases on web, iOS, or other platform
2. Activation URL handled by `SubscriptionRedirectManager`
3. Authentication token exchanged
4. Entitlements synchronized across platforms
5. macOS-specific features configured

### Restoration
1. Initiated from subscription settings
2. App Store receipt validation
3. Server entitlement check
4. Local state synchronized
5. System extensions updated

## Free Trials

The macOS app supports free trials through:
- App Store introductory offers
- Feature flag controlled availability
- Automatic eligibility checking
- Trial status displayed in subscription UI

### Trial Requirements
- No previous free trial usage (can have had previous subscriptions)
- Valid App Store product with trial offer
- Feature flags enabled

## Freemium PIR (Personal Information Removal)

### Overview
Freemium PIR provides limited Data Broker Protection features to non-subscribers:
- **Limited scanning**: Initial scan to show data exposure
- **USA only**: Available only for US App Store users
- **Upgrade prompts**: Encourages subscription for full removal

### Architecture
- **FreemiumDBPFeature** - Main feature controller
- **FreemiumDBPUserStateManager** - Manages user activation state
- **FreemiumDBPPresenter** - UI presentation logic
- **FreemiumDBPPromotionViewCoordinator** - Promotion flow management

### Eligibility Requirements

| Requirement | Description |
|-------------|-------------|
| Feature Flag | `DBPSubfeature.freemium` must be enabled |
| Subscription Status | Only for non-authenticated users |
| Geographic Region | US only (matches Stripe availability) |
| Purchase Capability | User must be able to purchase subscriptions |

**Region Detection**:
- App Store builds: Check App Store storefront
- Direct Download builds: Check system locale

Note: Freemium PIR follows the same geographic restrictions as Stripe - primarily US-focused.

### User Flow
1. User discovers PIR feature
2. Freemium option presented if eligible
3. Initial scan performed
4. Results shown with upgrade prompts
5. Full removal requires subscription

### Key Components
- **FreemiumDBPScanResultPolling** - Monitors scan progress
- **FreemiumDBPFirstProfileSavedNotifier** - Tracks profile creation
- **NewTabPageFreemiumDBPBannerProvider** - Shows promotional banners
- **DataBrokerProtectionFeatureDisabler** - Handles offboarding

### Offboarding
Users are automatically offboarded if:
- Feature flag is disabled remotely
- User becomes ineligible (e.g., region change)
- Maintains data privacy by removing all stored information

## Feature Integration

### VPN (Network Protection)
- System extension installation
- Menu bar status indicator
- Connection management
- Split tunneling configuration

### Personal Information Removal
- Background agent scheduling
- Scan result notifications
- Removal request management
- Progress tracking

### Identity Theft Restoration
- Secure web view for ITR portal
- Document upload handling
- Case management interface

## Development Guidelines

### Adding Features
1. Update entitlement checks
2. Add menu items if needed
3. Update `SubscriptionNavigationCoordinator` for new flows
4. Implement pixel events

### Testing Subscriptions
- Use sandbox environment
- Test multi-window scenarios
- Verify system extension behavior
- Check notification delivery

### Important Considerations
- System extensions require admin privileges
- Background agents need proper entitlements
- Keychain access requires code signing
- Notarization needed for distribution

## Build-Specific Considerations

### App Store Build
- **Purchase Method**: App Store only
- **Geographic Availability**: US and international territories
- **Free Trials**: Available via App Store introductory offers
- **Sandboxing**: Full App Store sandbox compliance
- **Distribution**: Mac App Store

### Direct Download Build
- **Purchase Method**: Stripe (US) or redirect to iOS (non-US)
- **Geographic Availability**: US for direct purchase, international via iOS redirect
- **Free Trials**: Limited to US users via Stripe configuration
- **System Access**: More privileged access for system extensions
- **Distribution**: Direct download from DuckDuckGo website

## Key Files
- `SubscriptionNavigationCoordinator.swift` - Navigation orchestration
- `SubscriptionUIHandler.swift` - UI state management  
- `SubscriptionManager+StandardConfiguration.swift` - Configuration setup

## Troubleshooting

### Common Issues

#### System Extension Installation
- **Problem**: VPN system extension fails to install
- **Solution**: Ensure user has admin privileges and security settings allow extensions

#### Stripe Purchase Failures
- **Problem**: Stripe checkout doesn't complete
- **Solution**: Check network connectivity and ensure cookies are enabled

#### Cross-Platform Activation
- **Problem**: Subscription purchased elsewhere not recognized
- **Solution**: Use "Restore Purchase" or sign in with same account

### Debug Tips
- Enable verbose logging in Debug builds
- Check Console.app for system extension logs
- Monitor network requests in Web Inspector
- Verify keychain access permissions

## Related Documentation
- [BrowserServicesKit Subscription](../../../SharedPackages/BrowserServicesKit/Sources/Subscription/SUBSCRIPTION.md)
- [Main macOS Documentation](../CLAUDE.md)