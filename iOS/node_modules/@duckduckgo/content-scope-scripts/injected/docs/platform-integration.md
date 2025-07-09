# Platform Integration Guide

## Overview

The [injected/entry-points/](https://github.com/duckduckgo/content-scope-scripts/tree/main/injected/entry-points) directory handles platform specific differences and is glue code into calling the contentScopeFeatures API.

## Browser Compatibility

The following is a guideline for when using native JavaScript syntax or built-in global DOM objects. Testing is always advised, but code authors might be unable to replicate the code on the correct application environments (due to hardware or an updated local environment).

### Minimum Supported Engines

#### iOS

- **Safari 14** (minimum)
- **Minimum support**: iOS 14 - [Review supported device and iOS versions](https://support.apple.com/en-us/102662)
- **Engine**: WKWebView should behave like Safari 14 as this is the native engine

#### macOS

- **Safari 14** (minimum)
- **Minimum support**: Catalina (potentially Safari 14 is native engine in non-updated device)
- **Engine**: WKWebView should behave like Safari 14

#### Android

- **Android 23** (minimum) - [Product feedback request: Android - min supported version](https://app.asana.com/1/137249556945/project/908478224964033/task/1209367367171662?focus=true)
- **Chrome 80+** (minimum)
- **Reference**: See [pixel dashboard](https://app.asana.com/1/137249556945/project/908478224964033/task/1209367367171662?focus=true)

#### Windows

- **Edge-based** behavior expected
- **Minimum**: Chrome 83 (if client has disabled all updates)
- **Reference**: [Windows Browser: Minimum specs](https://app.asana.com/1/137249556945/project/908478224964033/task/1209367367171662?focus=true)

#### Extensions

- **Chrome**: Version 96+ - [Chrome manifest reference](https://github.com/duckduckgo/duckduckgo-privacy-extension/blob/249d8d6ebe38b9b8265ba311909c8971c422122c/browsers/chrome/manifest.json#L6)
- **Firefox**: Version 91+ - [Firefox manifest reference](https://github.com/duckduckgo/duckduckgo-privacy-extension/blob/249d8d6ebe38b9b8265ba311909c8971c422122c/browsers/firefox/manifest.json#L6)

## Platform-Specific Implementation Details

### Firefox

The code is loaded as a standard extension content script.

### Apple, Windows, and Android

The code is a UserScript that has some string replacements for properties and loads in as the page scope.

> **Note**: Currently we don't implement the update calls as it's only required by cookie protections which we don't implement.

### All Other Browsers

The code is stringified, base64 encoded and injected in as a self deleting `<script>` tag.

In the built output you will see these dramatic differences in the bundled code which is created into: `/build`

## App-Specific Integration Replacements

The following placeholders are replaced during the build process:

- **`$CONTENT_SCOPE$`** - Raw remote config object
- **`$USER_UNPROTECTED_DOMAINS$`** - An array of user allowlisted domains
- **`$USER_PREFERENCES$`** - An object containing:
    - `platform`: `{ name: '<ios | macos | extension | android>' }`
    - `debug`: boolean
    - `globalPrivacyControlValue`: boolean
    - `sessionKey`: `<CSRNG UUID 4 string>` (used for fingerprinting) - this should regenerate on browser close or every 24 hours
    - `features`: `[<string feature names>]`

## Adding a New Platform

### 1. Create Platform Entry Point

For a new platform, add a new inject file to [injected/entry-points/](https://github.com/duckduckgo/content-scope-scripts/tree/main/injected/entry-points).

This file contains platform-specific implementation details for the Content Scope Features API. There's a strong chance you'll want to copy `apple.js` as a starting point.

> **Note**: Apple currently doesn't implement the `update` method used for Cookies as it's not implementing cookie protections yet. It's likely the platform will struggle to track blocked frames anyway.

### 2. Build Process

Ensure the `build/` directory contains the relevant platform file after running the build process.

### 3. Platform Integration (All but Extension)

In your platform code:

1. **Include as submodule**: Include the content-scope-scripts repo as a submodule
2. **Load the build file**: Load `build/{platform}/inject.js` into all webpages
3. **Inject configuration**: This should inject the variables required to configure the JS API
4. **Frame coverage**: This should be injected into all frames and windows

### 4. Configuration Injection

Inject the generated file into the page context of the website whilst replacing the placeholders with the relevant data:

- **`$CONTENT_SCOPE$`** - Raw remote config object
- **`$USER_UNPROTECTED_DOMAINS$`** - Array of user allowlisted domains
- **`$USER_PREFERENCES$`** - Platform configuration object (see macOS integration for details)

These should be passed into `processConfig` to make the data match the extension format.

### 5. Platform-Specific Integration Tasks

- [iOS: Content scope scripts integration](https://app.asana.com/1/137249556945/project/1201614831475344/task/1201631403895846)
- [Windows Browser: content scope scripts integration](https://app.asana.com/1/137249556945/project/1201614831475344/task/1201631403895850)
- [Android: Content scope scripts integration](https://app.asana.com/1/137249556945/project/1201614831475344/task/1201631403895848)

## Implementation Verification

Check that relevant Privacy Features are working as expected:

- **GPC (DOM signal)**: [Global Privacy Control Implementation Guidelines](https://app.asana.com/1/137249556945/project/1198207348643509/task/1200195761608650?focus=true)
- **Referrer trimming**: [Referrer Header Trimming Implementation Guidelines](https://app.asana.com/1/137249556945/project/1198207348643509/task/1200339587157290?focus=true)
- **Fingerprint protection**: [Fingerprint Protection Implementation Guidelines](https://app.asana.com/1/137249556945/project/1198207348643509/task/1200511341201907?focus=true)
- **Cookie protection**:
    - [Block Third Party Tracking Cookies Implementation Guidelines](https://app.asana.com/1/137249556945/project/1198207348643509/task/1200539099112751?focus=true)
    - [Expire First Party Script Cookies Implementation Guidelines](https://app.asana.com/1/137249556945/project/1198207348643509/task/1200364574828671?focus=true)
