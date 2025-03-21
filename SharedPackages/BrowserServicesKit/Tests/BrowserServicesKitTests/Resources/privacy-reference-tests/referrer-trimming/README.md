# Referrer Trimming Tests

Privacy Feature: https://app.asana.com/0/1198207348643509/1199093921854084/f

## Goals

This set of tests verifies implementation of referrer trimming protection. In particular it focuses on verifying that:

- referrer is modified (trimmed) correctly in various scenarios,
- that both header (`Referer`) and the API (`document.referrer`) are modified and
- that excluded domains (via remote config or turning off protections by the user) are taken into account.

## Structure

Test suite specific fields:

- `navigatingFromURL` - string - navigation initiator URL
- `navigatingToURL` - string - navigation destination URL
- `referrerValue` - string - value of the referrer (both header and JS API)
- `expectReferrerHeaderValue` - expected value of the "Referer" header after it was processed
- `siteURL` - string - currently loaded website's URL (as seen in the URL bar)
- `frameURL` - string - URL of an iframe in which the feature is operating (optional - if not set assume main frame context)
- `requestURL` - string - URL to a request being made
- `requestType` - mostly "script" or "main_frame" (navigational request), but can be any of https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest/ResourceType - type of the resource being fetched
- `expectReferrerAPIValue` - expected value of JS API (`document.referrer`) after it was processed

## Pseudo-code implementation

```
loadReferenceConfig('config_reference.json')
loadReferenceBlocklist('tracker_radar_reference.json')
  
for $testSet in test.json

  for $test in $testSet
    if $test.exceptPlatforms includes 'current-platform'
        skip

    if ("navigatingFromURL" in $test) {
      // testing navigations
      $modifiedReferrer = trimHeaders(
        navigatingFrom = $test.navigatingFromURL,
        navigatingTo = $test.navigatingToURL,
        headers = ["Referer" => $test.referrerValue]
      )
      
      expect($modifiedReferrer === $test.expectReferrerHeaderValue)
    } else if ("requestURL" in $test) {
      // testing subrequests
      $modifiedReferrer = trimHeaders(
        siteURL = $test.siteURL,
        requestURL = $test.requestURL,
        requestType = $test.requestType,
        headers = ["Referer" => $test.referrerValue]
      )
      
      expect($modifiedReferrer === $test.expectReferrerHeaderValue)
    } else if ("expectReferrerAPIValue" in $test) {
      // testing JS API
      $modifiedReferrer = documentReferrerValue(
        siteURL = $test.siteURL,
        frameURL = $test.frameURL,
        initialValue = $test.referrerValue
      )
      
      expect($modifiedReferrer === $test.expectReferrerAPIValue)
    }
```
