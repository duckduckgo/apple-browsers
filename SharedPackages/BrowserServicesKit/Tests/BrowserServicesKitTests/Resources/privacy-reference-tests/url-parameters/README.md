# URL Parameters Tests

Privacy Feature: https://app.asana.com/0/1198207348643509/1201469937577208/f

## Goals

This set of tests verifies the implementation of URL parameter stripping. In particular it focuses on verifying that:

- Tracking parameters identified in the config are able to be removed
- Non-tracking parameters are preserved in the URL

## Structure

There are multiple sets of tests in `tests.json`.

Test suite specific fields:

- testURL - string - URL that needs to be rewritten
- expectURL - string - The expected URL to be returned (if string is empty native implementation should return nil)

## Pseudo-code implementation

```
for $testSet in test.json
  loadRemoteConfig($testSet.referenceConfig)

  for $test in $testSet
    $cleanURL = LinkCleaner.removeTrackingParameters($testURL)

    expect($cleanURL === $test.expectURL)
```
