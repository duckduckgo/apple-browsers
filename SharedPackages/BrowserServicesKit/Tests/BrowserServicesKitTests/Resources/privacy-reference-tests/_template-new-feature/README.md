# Feature Name Tests

Privacy Feature: <https://app.asana.com/ link>

## Goals

This set of tests verifies implementation of …. In particular it focuses on verifying that:

- …

## Structure

Test suite specific fields:

- `featureName` - string - name of the privacy feature as defined in the config
- …
- `expectFeatureEnabled` - bool - if feature is expected to be disabled or not

## Pseudo-code implementation

```
for $testSet in test.json
  loadReferenceConfig('config_reference.json')

  for $test in $testSet
    if $test.exceptPlatforms includes 'current-platform'
        skip

    $enabled = isFeatureEnabled(
        feature=$test.featureName,
    )

    expect($enabled === $test.expectFeatureEnabled)
```

## Platform exceptions

- Explanations for any platform exceptions (`exceptPlatforms`)