---
alwaysApply: false
title: "A/B/N Experiment Framework"
description: "A/B/N experiment framework for DuckDuckGo browser including remote configuration, client-side implementation, cohort management, metrics tracking, and experiment lifecycle management"
keywords: ["A/B testing", "experiments", "feature flags", "remote configuration", "cohorts", "metrics", "PrivacyFeature", "PixelExperimentKit", "conversion windows", "enrollment"]
---

# A/B/N Experiment Framework

## Overview

The DuckDuckGo browser includes a comprehensive A/B/N experiment framework that enables data-driven feature testing across iOS and macOS platforms. This framework allows you to safely experiment with new ideas while maintaining control groups and measuring impact.

**Reference**: Video of knowledge sharing session: ✓ A/B/N Experiment Framework

## What is A/B/N Testing?

An **A/B/N test** is a method of experimenting with multiple variants of a feature (A, B, ... N) to determine which performs better. It's like traditional A/B testing but scaled up to support more than two groups.

### Use Cases

You can use this framework to explore:
- **UI/UX variations**: Whether blue buttons outperform green buttons
- **Content experiments**: If showing pictures of cats 🐱 or dogs 🐶 boosts user retention
- **Feature comparisons**: Different implementations of the same functionality
- **Performance optimization**: Testing various algorithms or approaches

### When to Use A/B/N Testing

✅ **Use for**:
- Comparing user behavior between two or more feature variants
- Validating hypotheses before rolling out changes to all users
- Safely experimenting with new ideas while maintaining control groups
- Measurable, impactful decisions with clear success metrics

❌ **Don't use for**:
- Simple bug fixes or obvious improvements
- Changes without measurable impact
- Features that can't be easily reversed

⚠️ **Note**: Not every change needs a test—reserve it for measurable, impactful decisions. This is typically decided in collaboration with ODRIs and Data Science.

## Framework Architecture

### Remote Configuration System

A/B/N experiments are supported via **remote configuration** on both macOS and iOS:

- **Sub-features** are used for experiments
- **Parent features** group related experiments
- **Cohorts** define the different variants
- **Weights** control user distribution
- **Targets** allow locale-based segmentation

## Configuration Setup

### 1. Privacy Config Structure

Experiments are defined in the Privacy Configuration with this structure:

```json
"amazingMacroFeature": {
  "state": "enabled",
  "features": {
    "petsPictures": {
      "state": "enabled",
      "description": "This feature shows users pictures of cute pets",
      "targets": [
        { "localeLanguage": "en", "localeCountry": "US" },
        { "localeLanguage": "fr", "localeCountry": "CA" }
      ],
      "cohorts": [
        { "name": "cats", "weight": 1 },
        { "name": "dogs", "weight": 1 }
      ]
    }
  }
}
```

### Configuration Elements

#### **State Options**
- `enabled`: Visible to all users
- `internal`: Visible only to internal users  
- `disabled`: Hidden from all users

#### **Description**
Explains the experiment's purpose for team reference.

#### **Targets** (Optional)
Specify user segments based on locale:
```json
"targets": [
  { "localeLanguage": "en", "localeCountry": "US" },
  { "localeLanguage": "fr", "localeCountry": "CA" }
]
```

#### **Cohorts**
Define experiment variants:
- `name`: Cohort identifier (e.g., "cats", "dogs")
- `weight`: Probability of assignment (normally 1 or 0)

## Client Implementation

### Step 1: Add Feature to PrivacyFeature (BSK)

#### Check for Existing Features

```swift
// In PrivacyFeature enum, check if parent feature exists
public enum PrivacyFeature: String, CaseIterable {
    case amazingMacroFeature
    // ... other features
}

// Add sub-feature to existing enum or create new one
public enum AmazingMacroFeatureSubfeatures: String, CaseIterable {
    case petsPictures
    // ... other sub-features
}
```

#### Add New Features

If the parent feature doesn't exist:
1. Add it to the `PrivacyFeature` enum
2. Create a new sub-features enum
3. Add your sub-feature to the enum

### Step 2: Define Feature Flag

Add your experiment to the local `FeatureFlag` enum:

```swift
public enum FeatureFlag: String, CaseIterable {
    case debugMenu
    case sslCertificatesBypass
    case maliciousSiteProtection
    // ... existing flags
    case petsPictures

    public var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        switch self {
        case .petsPictures:
            return PetsPicturesCohort.self
        default:
            return nil
        }
    }

    public enum PetsPicturesCohort: String, FeatureFlagCohortDescribing {
        case cats
        case dogs
    }

    public var source: FeatureFlagSource {
        switch self {
        // ... other cases
        case .petsPictures:
            return .remoteReleasable(.subfeature(AmazingMacroFeatureSubfeatures.petsPictures))
        }
    }

    public var supportsLocalOverriding: Bool {
        switch self {
        // ... other cases
        case .petsPictures: 
            return true
        }
    }
}
```

#### Key Properties

**`cohortType`**: Links to experiment cohorts enum
- Must conform to `String, FeatureFlagCohortDescribing`
- Defines available variants (cats, dogs)

**`source`**: Defines feature flag toggle location
- `.disabled`: Feature is off
- `.internalOnly`: Internal users only
- `.remoteDevelopment`: Development testing
- `.remoteReleasable`: Production experiments

**`supportsLocalOverriding`**: Enables debug menu overrides
- `true`: Internal users can override cohort assignment
- `false`: No local overrides allowed

### Step 3: Implement Cohort Decision Logic

Request cohort assignment when needed:

```swift
// ✅ CORRECT: Request cohort only when decision is needed
guard let petsCohort = Application.appDelegate.featureFlagger.resolveCohort(for: .petsPictures) as? FeatureFlag.PetsPicturesCohort else { 
    return 
}

switch petsCohort {
case .cats:
    showCatPics()
case .dogs:
    showDogPics()
}
```

⚠️ **Important**: Only request the cohort at the moment it's needed! This ensures accurate assignment and avoids data dilution.

### Step 4: Handle Dynamic Cohort Changes

For features that need to respond to runtime cohort changes:

```swift
private func subscribeToPetsExperimentFeatureFlagChanges() {
    guard let overridesHandler = Application.appDelegate.featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
        return
    }

    overridesHandler.experimentFlagDidChangePublisher
        .filter { $0.0 == .petsPictures }
        .sink { (_, cohort) in
            guard let newCohort = FeatureFlag.PetsPicturesCohort.cohort(for: cohort) else { return }
            switch newCohort {
            case .cats:
                // IMMEDIATELY SHOW A CUTE CAT
            case .dogs:
                // IMMEDIATELY SHOW A CUTE DOG
            }
        }
        .store(in: &cancellables)
}
```

## Metrics and Analytics

### Default Retention Metrics

The framework automatically tracks core engagement metrics without additional configuration:

#### 1. Enrollment Pixel

Tracks when users join experiments:

```
Pixel Name: experiment_enroll_{experimentName}_{cohortName}
Parameters:
- enrollmentDate: Date in ET (YYYY-MM-DD format)
```

#### 2. Search Activity Pixels

Monitors search behavior post-enrollment:

```
Pixel Name: experiment_metrics_{experimentName}_{cohortName}
Parameters:
- metric: "search"
- conversionWindowDays: Time frame (e.g., "1", "5-7")
- value: Number of searches performed
- enrollmentDate: Enrollment date (YYYY-MM-DD)
```

**Predefined Tracking Windows**:
- **Value 1**: Conversion windows [1, 2, 3, 4, 5, 6, 7, 5-7]
- **Values 4, 6, 11, 21, 30**: Conversion windows [5-7, 8-15]

#### 3. App Usage Pixels

Tracks app engagement (launches, foregrounds, etc.):

```
Pixel Name: experiment_metrics_{experimentName}_{cohortName}
Parameters:
- metric: "app_use"  
- conversionWindowDays: Time frame (e.g., "0", "1", "5-7")
- value: Number of app usage events
- enrollmentDate: Enrollment date (YYYY-MM-DD)
```

**Predefined Tracking Windows**:
- **Value 1**: Conversion windows [0, 1, 2, 3, 4, 5, 6, 7, 5-7]
- **Values 4, 6, 11, 21, 30**: Conversion windows [5-7, 8-15]

### Custom Metrics

Track experiment-specific behaviors using `PixelExperimentKit`:

#### Import Required Framework

```swift
import PixelExperimentKit
```

#### Fire Custom Metric Pixels

```swift
// Method 1: Direct pixel firing
func fireExperimentPixel(
    for subfeatureID: SubfeatureID,
    metric: String,
    conversionWindowDays: ConversionWindow,
    value: String
)

// Method 2: Threshold-based pixel firing
func fireExperimentPixelIfThresholdReached(
    for subfeatureID: SubfeatureID,
    metric: String,
    conversionWindowDays: ConversionWindow,
    threshold: NumberOfCalls
)
```

#### Example: Button Click Tracking

```swift
// Track immediate button clicks
PixelKit.fireExperimentPixel(
    for: "petsPictures",
    metric: "adopt_button_clicks",
    conversionWindowDays: 1...1,
    value: "1"
)

// Track threshold-based clicks (fires after 5 clicks)
PixelKit.fireExperimentPixelIfThresholdReached(
    for: "petsPictures",
    metric: "button_clicks",
    conversionWindowDays: 1...7,
    threshold: 5
)
```

#### Custom Metric Examples

```swift
// Form completion tracking
PixelKit.fireExperimentPixel(
    for: "petsPictures",
    metric: "form_completed",
    conversionWindowDays: 1...1,
    value: "true"
)

// Feature adoption tracking
PixelKit.fireExperimentPixel(
    for: "petsPictures", 
    metric: "set_as_default",
    conversionWindowDays: 1...7,
    value: "true"
)

// Error tracking
PixelKit.fireExperimentPixel(
    for: "petsPictures",
    metric: "error_occurred",
    conversionWindowDays: 1...1,
    value: "network_timeout"
)
```

## Experiment Management

### Stop Accepting New Users to a Cohort

To prevent new enrollments while maintaining existing users:

```json
"cohorts": [
  { "name": "cats", "weight": 0 },  // No new users
  { "name": "dogs", "weight": 1 }   // All new users go here
]
```

**Behavior**:
- **Existing users**: Remain in their assigned cohorts
- **New users**: Only assigned to cohorts with weight > 0
- **No enrollment**: Set all weights to 0

### Remove Users from a Cohort

To completely remove a cohort and reassign users:

```json
// Before: Two cohorts
"cohorts": [
  { "name": "cats", "weight": 1 },
  { "name": "dogs", "weight": 1 }
]

// After: Cats cohort removed
"cohorts": [
  { "name": "dogs", "weight": 1 }
]
```

**Behavior**:
- **Existing users**: Automatically reassigned to remaining cohorts
- **New users**: Assigned to available cohorts
- **No cohorts**: No users enrolled if all cohorts removed

### Stop an Experiment

Complete cleanup requires both code and configuration changes:

#### 1. Clean Up Code

```swift
// ❌ Remove experiment-specific logic
// switch petsCohort {
// case .cats:
//     showCatPics()
// case .dogs:
//     showDogPics()
// }

// ✅ Implement final chosen behavior
showDogPics() // Or whatever was determined to be the winner
```

#### 2. Update Configuration

```json
// Remove cohorts or entire sub-feature
"amazingMacroFeature": {
  "state": "enabled",
  "features": {
    // "petsPictures": { ... } // Remove entire sub-feature
  }
}
```

⚠️ **Critical**: Always remove code before removing configuration to prevent runtime errors.

## Development and Testing

### Feature Flag Sources for Development

Control experiment access during development:

#### Internal-Only Testing

```swift
public var source: FeatureFlagSource {
    switch self {
    case .petsPictures:
        // Only internal users see this experiment
        return .internalOnly(.subfeature(AmazingMacroFeatureSubfeatures.petsPictures))
    }
}
```

#### Development Random Assignment

```swift
public var source: FeatureFlagSource {
    switch self {
    case .petsPictures:
        // Internal users get random assignment based on remote config
        return .remoteDevelopment(.subfeature(AmazingMacroFeatureSubfeatures.petsPictures))
    }
}
```

#### Production Release

```swift
public var source: FeatureFlagSource {
    switch self {
    case .petsPictures:
        // All users participate based on remote config
        return .remoteReleasable(.subfeature(AmazingMacroFeatureSubfeatures.petsPictures))
    }
}
```

### Local Overrides for Testing

Enable debug menu overrides for internal testing:

```swift
public var supportsLocalOverriding: Bool {
    switch self {
    case .petsPictures:
        return true  // Enables debug menu cohort selection
    }
}
```

**Usage**:
1. Open debug menu in internal builds
2. Navigate to "Feature Flag Overrides"
3. Select specific cohort for testing
4. App immediately reflects cohort change

## Best Practices

### ✅ DO

```swift
// Request cohort only when needed
guard let cohort = featureFlagger.resolveCohort(for: .petsPictures) as? FeatureFlag.PetsPicturesCohort else { return }

// Use meaningful cohort names
public enum PetsPicturesCohort: String, FeatureFlagCohortDescribing {
    case cats           // Clear, descriptive names
    case dogs
}

// Track relevant custom metrics
PixelKit.fireExperimentPixel(
    for: "petsPictures",
    metric: "adoption_success",
    conversionWindowDays: 1...7,
    value: "true"
)

// Clean up after experiments
// Remove cohort logic and implement winning variant
```

### ❌ DON'T

```swift
// Don't request cohorts unnecessarily
let cohort = featureFlagger.resolveCohort(for: .petsPictures) // ❌ Called too early

// Don't use unclear cohort names  
public enum TestCohort: String {
    case a              // ❌ Unclear what this represents
    case b
}

// Don't forget to clean up
// Leaving experiment code after completion ❌

// Don't remove config before code
// Can cause runtime crashes ❌
```

### 🔒 Security and Privacy

```swift
// Don't log sensitive cohort information
Logger.debug("User assigned to cohort: \(cohort)") // ❌ Potential privacy issue

// Use privacy-safe logging
Logger.debug("Experiment cohort assigned") // ✅ Safe

// Don't store cohort assignments locally
UserDefaults.standard.set(cohort.rawValue, forKey: "cohort") // ❌ Privacy risk
```

## Troubleshooting

### Common Issues

#### Cohort Assignment Not Working
```swift
// Check feature flag setup
guard let cohort = featureFlagger.resolveCohort(for: .petsPictures) else {
    Logger.error("Failed to resolve cohort for petsPictures")
    return
}
```

#### Metrics Not Appearing
```swift
// Verify PixelExperimentKit import
import PixelExperimentKit

// Check subfeature ID matches config
PixelKit.fireExperimentPixel(
    for: "petsPictures", // Must match config exactly
    metric: "test_metric",
    conversionWindowDays: 1...1,
    value: "1"
)
```

#### Debug Menu Not Showing Experiment
```swift
public var supportsLocalOverriding: Bool {
    switch self {
    case .petsPictures:
        return true  // Must be true for debug menu
    }
}
```

### Validation Checklist

- [ ] Privacy config includes correct cohort names and weights
- [ ] FeatureFlag enum properly configured with cohort type
- [ ] Feature flag source matches intended audience
- [ ] Custom metrics fire at appropriate times
- [ ] Local overrides work in debug builds
- [ ] Experiment cleanup plan documented

---

This A/B/N experiment framework provides a robust, scalable solution for data-driven feature development in the DuckDuckGo browser, enabling safe experimentation while maintaining user privacy and providing comprehensive analytics. 