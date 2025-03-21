# Fingerprinting Protection Tests

Privacy Feature: https://app.asana.com/0/1198207348643509/1199583771657237/f

## Goals

This set of tests verifies implementation of fingerprinting protections. In particular it focuses on verifying that:

- exceptions from configuration file are respected,
- values of properties are modified correctly.

## Structure

Test suite specific files:

- `init.js` - set of API mocks that should be loaded into the page before protections are initialized. This allows us to normalize default/unprotected values.

Test suite specific fields:

- `siteURL` - string - currently loaded website's URL (as seen in the URL bar) 
- `property` - string - JavaScript code extracting value of given property/API. Note that in some cases this code is async, please wait for returned promise to resolve.
- `expectPropertyValue` - string - expected value of the property

## Pseudo-code implementation

```
$page.injectOnLoad('init.js')
$page.injectOnLoad('C-S-S')

for $testSet in test.json
  loadReferenceConfig('config_reference.json')

    for $test in $testSet.tests
        if $test.exceptPlatforms includes 'current-platform'
            skip

        $page = createPage(
            siteURL = $test.siteURL,
        )

        $value = $page.eval($test.property)

        if ($value instanceof Promise)
            $value = await $value

        expect($value.toString()).toBe($test.expectPropertyValue)
```

## Platform exceptions

- "ports are ignored when matching rules" disabled for web extensions ([bug report](https://app.asana.com/0/892838074342800/1201806214352982/f))
- Subdomains of CNAME entries are so far matched for Chrome MV3 ([bug report](https://app.asana.com/0/1200940319964997/1202246325586612/f))
- Webkit based platforms don't support Battery API, `navigator.keyboard` and `navigator.webkitTemporaryStorage`.
