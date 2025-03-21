# Storage Clearing (Fire Button & Fireproofing)

Privacy Feature: https://app.asana.com/0/0/1201277458549583/f

## Goals

This set of tests verifies implementation of fire button and fireproofing. In particular it focuses on verifying that:

- cookies are cleared for non-fireproofed sites,
- cookies are NOT cleared for fireproofed sites,
- some duckduckgo.com setting cookies are not cleared.

## Structure

Test suite specific fields:

- `fireproofedSites` - array of strings - list of sites that user fireproofed
- `cookieDomain` - string - domain on which cookie is set
- `cookieName` - string - name of the cookie being set
- `expectCookieRemoved` - bool - if cookie is expected to be cleared or not after fire button is clicked

## Pseudo-code implementation

```
for $testSet in test.json

  for $site in $testSet.fireproofedSites
    fireproof($site)

  for $test in $testSet
    if $test.exceptPlatforms includes 'current-platform'
        skip

    createCookie(
        domain = $test.cookieDomain,
        name = $test.cookieName
        value = "123"
    )

    fireButton()

    $cookie = getCookie(
        domain = $test.cookieDomain,
        name = $test.cookieName
    )

    expect($cookie === null).toBe($test.expectCookieRemoved)
```
