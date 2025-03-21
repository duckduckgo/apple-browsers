# Expire First Party JavaScript Cookies

Privacy Feature: https://app.asana.com/0/1198207348643509/1200040513378697/f

## Goals

This set of tests verifies implementation of expiring first party cookies set by scripts. In particular it focuses on verifying that:

- cookie policy from the configuration file is correctly extracted and applied,
- exceptions from the config are respected,
- reduced expiry time is correctly calculated and applied.

## Structure

Test suite specific fields:

- `siteURL` - string - currently loaded website's URL (as seen in the URL bar)
- `scriptURL` - string - URL of the script setting the cookie
- `setDocumentCookie` - string - cookie creation string, as assigned to `document.cookie`
- `expectCookieSet` - boolean - if cookie is expected to be created/stored
- `expectExpiryToBe` - number - expected expiry date in seconds from when the cookie was set ("-1" if session cookie is expected)

## Pseudo-code implementation

```
for $testSet in test.json
  loadReferenceConfig('config_reference.json')
  loadReferenceBlocklist('tracker_radar_reference.json')

  for $test in $testSet
    if $test.exceptPlatforms includes 'current-platform'
        skip

    $page = createPage(
        siteURL = $test.siteURL,
    )

    $page.evalAs('document.cookie = ' + $test.setDocumentCookie, $test.scriptURL)

    if ($test.expectCookieSet) {
        cookie = $page.getCookies()[0]

        if ($test.expectExpiryToBe === -1) {
            expect(cookie.isSessionCookie()).toBe(true)
        } else {
            expect(cookie.isSessionCookie()).toBe(false)
            expect(cookie.expiresInSeconds()).toBe($test.expectExpiryToBe)
        }
    } else {
        expect($page.getCookies().length).toBe(0)
    }
```

## Platform exceptions

N/A
