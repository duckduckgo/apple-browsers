# Privacy Pro Subscription

## Overview

The `Subscription` module in `BrowserServicesKit` provides the core subscription infrastructure shared between iOS and macOS DuckDuckGo applications. It handles authentication, purchase flows, entitlement management, and API communication for premium features.

Its main responsibilities are:
- Purchase, restore and remove the Subscription
- Provide the subscription and user entitlements
- Managing and providing valid the subscription authentication tokens, including creating and refreshing the `TokenContainer`.
- Provide the `TokenContainer` to the main app when needed from other


**Note**: This framework contains Subscription V1, that uses Auth V1, and Subscription V2 that uses Auth V2. The documentation is only about the V2 version of the code. V1 will be removed [soon](https://app.asana.com/1/137249556945/project/1209882303470922/task/1210741763117598).

## How to use it

## 
