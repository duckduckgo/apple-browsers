# Privacy Pro Subscription

## Overview

[AOR: Apple Privacy Pro Accounts](https://app.asana.com/1/137249556945/project/1209882303470922/list/1209882470267442)

The `Subscription` module in `BrowserServicesKit` provides the core subscription infrastructure shared between iOS and macOS DuckDuckGo applications. It handles authentication, purchase flows, entitlement management, and API communication for Privacy Pro features.

Its main responsibilities are:
- Purchase, restore and remove the Subscription
- Provide the subscription and user entitlements
- Manage the Subscription authentication tokens lifecycle. For details about the authentication, refer to [the Networking/Auth README](./../Networking/Auth/README.md)

**Note**: This framework contains Subscription V1, that uses Auth V1, and Subscription V2 that uses Auth V2. The documentation is only about the V2 version of the code. V1 will be removed [soon](https://app.asana.com/1/137249556945/project/1209882303470922/task/1210741763117598).

## How to use it

Generally, any external component...

### Authentication, Getting an authentication token, checking the auth state

General concepts:
- The Subscription framework is the only entity authorised to handle and store the `TokenContainer`
- A token last 4h and is the Subscription framework responsibility to, on demand, keep it up to date
- For details about the `TokenContainer` refer to [the Networking/Auth README](./../Networking/Auth/README.md)

How to get a token:
 ```
func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer
 ```

The policy options:
```
/// The token container from the local storage
case local
/// The token container from the local storage, refreshed if needed
case localValid
/// A refreshed token
case localForceRefresh
/// Like `.localValid`,  if doesn't exist create a new one
case createIfNeeded
```

Generally, any feature external to the Subscription, like VPN or PIR, should use `localValid` to assure the token is always refreshed.

The access token is part of the `TokenContainer`

### Checking for entitlements

There are 2 types of entitlements.
Both functions can throw errors, it's important not to interpret an error as the absence of entitlements.

1. **Subscription entitlements**: What the Subscription is capable of

`func isFeatureIncludedInSubscription(_ feature: Entitlement.ProductName) async throws -> Bool`

Used mostly by the Settings UI 

2. **User entitlements**: What the user is authorised to use

`func isFeatureEnabled(_ feature: Entitlement.ProductName) async throws -> Bool`

Privacy pro features always need to check if the user is allowed to use the feature by checking the user entitlement
When User entitlements change the `.entitlementsDidChange` notification is fired.

