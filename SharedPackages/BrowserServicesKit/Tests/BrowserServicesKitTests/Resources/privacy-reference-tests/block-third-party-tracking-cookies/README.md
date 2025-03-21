# Third Party Cookies Bocking Tests

Privacy Feature: https://app.asana.com/0/1198207348643509/1199093921854081/f

## Goals

This set of tests verifies implementation of third party tracker cookie blocking. In particular it focuses on verifying that:

- `cookie` and `set-cookie` headers are being removed from requests to known trackers
- multiple `cookie` headers are handled
- remote config exceptions are taken into account
- `document.cookie` disallows setting / reading cookies in tracking contexts

## Structure

Files in the folder:
- `config_reference.json` - reference remote configuration file
- `tracker_radar_reference.json` - reference blocklist file

Test suite specific fields:

- `siteURL` - string - currently loaded website's URL (as seen in the URL bar)
- `frameURL` - string - URL of an iframe in which the feature is operating (optional - if not set assume main frame context)
- `requestURL` - string - URL to a request being made
- `requestHeaders` - array of `{name: string, value:string}` objects - input array of request headers (with `cookie` headers)
- `responseHeaders` - array of `{name: string, value:string}` objects - input array of response headers (with `set-cookie` headers)
- `expectCookieHeadersRemoved` - boolean - if all `cookie` headers are expected to be filtered out for this request
- `expectSetCookieHeadersRemoved` - boolean - if all `set-cookie` headers are expected to be filtered out for this response
- `setDocumentCookie` - string - value that should be assigned to `document.cookie` to test if cookie will be stored
- `expectDocumentCookieSet` - boolean - if cookie set via `document.cookie` is supposed to be stored

## Pseudo-code implementation

```
for $testSet in test.json
  loadReferenceConfig('config_reference.json')
  loadReferenceBlocklist('tracker_radar_reference.json')

  for $test in $testSet
    if $test.exceptPlatforms includes 'current-platform'
        skip

    if ("expectCookieHeadersRemoved" in $test) {
      $outputHeaders = requestBlockTracking3pCookies(
        siteURL = $test.siteURL
        frameURL = $test.frameURL
        headers = $test.requestHeaders
      )
      
      if ($test.expectCookieHeadersRemoved) {
        expect(outputHeaders.countHeaders('cookie') === 0)
      } else {
        expect(outputHeaders.countHeaders('cookie') > 0)
      }
    } else if ("expectSetCookieHeadersRemoved" in $test) {
      $outputHeaders = responseBlockTracking3pCookies(
        siteURL = $test.siteURL
        frameURL = $test.frameURL
        headers = $test.responseHeaders
      )
      
      if ($test.expectSetCookieHeadersRemoved) {
        expect(outputHeaders.countHeaders('set-cookie') === 0)
      } else {
        expect(outputHeaders.countHeaders('set-cookie') > 0)
      }
    } else if ("expectDocumentCookieSet" in $test) {
      // testing JS API
      $page = createPage(
        siteURL = $test.siteURL,
        frameURL = $test.frameURL
      )

      $page.eval('document.cookie = ' + $test.setDocumentCookie)
      
      if (expectDocumentCookieSet) {
          expect($page.getCookieString() === $test.setDocumentCookie)
      } else {
          expect($page.getCookieString() === '')
      }
    }
```

## Platform exceptions

- web extension is missing a CNAME check when determining if domain is a tracker
