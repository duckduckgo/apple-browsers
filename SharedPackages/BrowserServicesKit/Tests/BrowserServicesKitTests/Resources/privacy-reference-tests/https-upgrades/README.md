# HTTPS Upgrades

Privacy Feature: https://app.asana.com/0/1198207348643509/1199103718890894/f

## Goals

This set of tests verifies implementation of HTTPS upgrading (Smarter Encryption). In particular it focuses on verifying that:

- domains from the main bloom filter are upgraded,
- domains from the main allowlist are not upgraded,
- domains from the negative bloom filter are not upgraded,
- domains from the negative allowlist are upgraded,
- domains allowlisted in the remote config are not upgraded,
- local urls (localhost and friends) are not upgraded.

## Structure

Files in the folder:
- `config_reference.json` - reference remote config with https exceptions
- `https_bloomfilter_reference.json` and `https_bloomfilter_reference.bin` - the main bloom filter in two formats with hostnames that should be upgraded
- `https_allowlist_reference.json` - allowlist to the main bloom filter with hostnames that should not be upgraded
- `https_bloomfilter_spec_reference.json` - specification of the `.bin` bloom filter
- `https_negative_allowlist_reference.json` - inverse/negative boom filter with hostnames that should not be upgraded
- `https_negative_bloomfilter_reference.json` - allowlist to the negative bloom filter with hostnames that should be upgraded
 - `https_upgrade_hostnames.txt` - plaintext list of domains that should be upgraded
 - `https_dont_upgrade_hostnames.txt` - plaintext list of domains that should not be upgraded

Test suite specific fields:

- `siteURL` - string - currently loaded website's URL (as seen in the URL bar)
- `requestURL` - string - request in question
- `requestType` - mostly "image" or "main_frame" (navigational request), but can be any of https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest/ResourceType - type of the resource being fetched
- `expectURL` - string - expected url after it was upgraded (or not)

## Pseudo-code implementation

```
for $testSet in test.json
  loadReferenceConfig('config_reference.json')
  loadHTTPSBloomFilters(
      bloomFilter = 'https_bloomfilter_reference.json',
      allowlist = 'https_allowlist_reference.json',
      negativeBloomFilter = 'https_negative_bloomfilter_reference.json',
      negativeAllowlist = 'https_negative_bloomfilter_reference'
  )

  for $test in $testSet
    if $test.exceptPlatforms includes 'current-platform'
        skip

    $upgradedRequestURL = upgradeToHTTPS(
        siteURL = $test.siteURL,
        requestURL = $test.requestURL,
        requestType = $test.requestType,
        expectURL = $test.expectURL
    )

    expect($upgradedRequestURL === $test.expectURL)
```

## Bloom filter sources

Main bloom filter was built based on this list:

firsttest.com
secondtest.com
secure.thirdtest.com
s.fourthtest.com
fifth-test.com
a.b.c.d.e.sixthtest.com

And negative bloom filter was built based on this list:

negativetest.com
s.secondnegative.com
thirdnegative.com

## Platform exceptions

- Android, Windows, iOS and macOS don't support negative bloom filter because it's only needed for platforms where Smarter Encryption API is available
- Android, iOS and macOS don't support updating subrequests because of WebView limitations (request can be cancelled, but not modified)
- Windows don't support updating websocket subrequests because of WebView limitations (request can be cancelled, but not modified)
