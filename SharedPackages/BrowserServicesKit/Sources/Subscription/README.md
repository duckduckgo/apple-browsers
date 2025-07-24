# Privacy Pro Subscription

The `Subscription` module in `BrowserServicesKit` provides the core subscription infrastructure shared between iOS and macOS DuckDuckGo applications. It handles authentication, purchase flows, entitlement management, and API communication for Privacy Pro features.

## Table of Contents
- [Overview](#overview)
- [Core Responsibilities](#core-responsibilities)
- [Quick Start](#quick-start)
- [Authentication](#authentication)
  - [Token Management](#token-management)
  - [Token Retrieval](#token-retrieval)
  - [Cache Policies](#cache-policies)
- [Entitlements](#entitlements)
  - [Subscription Features](#subscription-features)
  - [User Entitlements](#user-entitlements)
- [Best Practices](#best-practices)
- [Error Handling](#error-handling)
- [Additional Resources](#additional-resources)

## Overview

Privacy Pro Subscription is a subscription service that provides enhanced privacy features for DuckDuckGo users. This module manages the entire subscription lifecycle, from initial purchase through authentication and entitlement verification.

The `SubscriptionManagerV2` protocol and the `DefaultSubscriptionManagerV2` implementation serve as the framework's entry point, handling all business logic.

Most of the functionalities are documented in the code. Please check `protocol SubscriptionManagerV2`

> **Note**: This documentation covers Subscription V2 (using Auth V2). V1 is deprecated and will be removed. [Track removal progress](https://app.asana.com/1/137249556945/project/1209882303470922/task/1210741763117598).

## Core Responsibilities

- **Purchase Management**: Handle new subscriptions, restore existing ones, and process cancellations
- **Entitlement Verification**: Manage and verify user access to Privacy Pro features
- **Authentication**: Manage the complete lifecycle of subscription authentication tokens
- **API Communication**: Handle all subscription-related API interactions

## Authentication

### User login state

The user login state can be checked via the `var isUserAuthenticated: Bool` from the `SubscriptionAuthenticationStateProvider` protocol.

### Token Management

The Subscription framework is the sole authority for handling and storing authentication tokens (`TokenContainer`). Key points:

- **Token Lifetime**: Each token is valid for 4 hours
- **Automatic Refresh**: The framework handles token refresh on-demand
- **Storage**: Tokens are securely stored and managed internally
- **Access Control**: Only the Subscription framework can directly manipulate token storage

For details about the authentication architecture, see the [Networking/Auth README](./../Networking/Auth/README.md).

### Token Retrieval

Retrieve authentication tokens using the following method:

```swift
func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer
```

### Cache Policies

Choose the appropriate cache policy based on your use case:

| Policy | Description | Use Case |
|--------|-------------|----------|
| `.local` | Returns token from local storage | Debugging or when offline access is acceptable |
| `.localValid` | Returns local token, refreshes if expired | **Default for most features (VPN, PIR, etc.)** |
| `.localForceRefresh` | Forces a token refresh | When you need the latest authentication state |
| `.createIfNeeded` | Like `.localValid`, but creates new token if none exists | Initial authentication flows |

**Example:**

```swift
// Most common usage for external features
let tokenContainer = try await subscription.getTokenContainer(policy: .localValid)
let accessToken = tokenContainer.accessToken
```

## Entitlements & Features

The framework can check if a feature is available in the subscription and if the same feature is active for the user

### Subscription Features

**What features the subscription includes** - The features available in the subscription plan.

```swift
func isFeatureIncludedInSubscription(_ feature: Entitlement.ProductName) async throws -> Bool
```

**Use cases:**
- Settings UI to show available features
- Screens showing what's included

**Example:**
```swift
let includesVPN = try await subscription.isFeatureIncludedInSubscription(.networkProtection)
// Use this to show/hide VPN in settings
```

### User Entitlements

**What the user can actually use** - The features the user is authorised to access based on their subscription status.

```swift
func isFeatureEnabled(_ feature: Entitlement.ProductName) async throws -> Bool
```

**Use cases:**
- Feature gates (ALWAYS use this for feature access)
- Enabling/disabling functionality
- Access control checks

**Example:**
```swift
// Always check user entitlements before enabling features
let canUseDataBrokerProtection = try await subscriptionManager.isFeatureEnabled(.dataBrokerProtection)

if canUseDataBrokerProtection {
    // Enable the feature
}
```

### Entitlement Change Notifications

Listen for entitlement changes to update your UI dynamically:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleEntitlementsChange),
    name: .entitlementsDidChange,
    object: nil
)

@objc private func handleEntitlementsChange() {
    // Refresh UI or feature availability
}
```

## Best Practices

1. **Always Use User Entitlements for Feature Access**
   ```swift
   // ✅ Correct - Check user entitlements
   if try await subscriptionManager.isFeatureEnabled(.networkProtection) {
       enableVPN()
   }
   
   // ❌ Wrong - Don't use subscription features for access control
   if try await subscription.isFeatureIncludedInSubscription(.networkProtection) {
       enableVPN()
   }
   ```

2. **Handle Errors Gracefully**
   - Never interpret errors as lack of entitlements
   - Implement retry logic for transient failures
   - Provide appropriate user feedback

3. **Use Appropriate Cache Policies**
   - Use `.localValid` for most scenarios
   - Avoid `.localForceRefresh` unless necessary (reduces server load)
   - Use `.createIfNeeded` only for initial setup flows

4. **Listen for Changes**
   - Subscribe to `.entitlementsDidChange` notifications
   - Update UI and feature availability dynamically

## Error Handling

Both entitlement check methods can throw errors. Proper error handling is crucial:

```swift
do {
    let hasAccess = try await subscriptionManager.isFeatureEnabled(.networkProtection)
    if hasAccess {
        // Enable feature
    } else {
        // Do not enable feature
    }
} catch {
    // Handle error - DO NOT assume no access
    // Log error, retry, or show appropriate message
    print("Failed to check entitlements: \(error)")
    // Consider showing a retry option or degraded experience
}
```

## Additional Resources

- **AOR**: [Apple Privacy Pro Accounts AOR](https://app.asana.com/1/137249556945/project/1209882303470922/list/1209882470267442)
- **Authentication Details**: [Networking/Auth README](./../Networking/Auth/README.md)
