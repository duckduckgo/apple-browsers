# AMP Protections Tests

Privacy Feature: https://app.asana.com/0/1198207348643509/1201460259279674/f

## Goals

This set of tests verifies the implementation of AMP protections. In particular it focuses on verifying that:

- The original URL is able to be extracted from a google.* URL
- A URL is able to be identified as an AMP URL based on keywords in the URL

## Structure

There are multiple sets of tests in `tests.json`.

Test suite specific fields:

- ampURL - string - URL that needs to be rewritten
- expectURL - string - The expected URL to be returned (if string is empty native implementation should return nil)
- expectAmpDetected - bool - if ampURL is expected to be a valid AMP URL

## Pseudo-code implementation

```
for $testSet in test.json
  loadRemoteConfig($testSet.referenceConfig)

  for $test in $testSet
    $cleanURL = AMPExtractor.extractCleanURL($ampURL)

    expect($cleanURL === $test.expectURL)

    OR

    $isAmpUrl = AMPExtractor.isAmpUrl($ampUrl)
    expect($isAmpUrl === $test.expectAmpDetected)
```