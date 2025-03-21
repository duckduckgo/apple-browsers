# Contributing guidelines

When adding new tests please follow the format and naming convention specified below. Once the new set is ready, please open a PR, make sure that all automatic checks pass and assign it to one of the DRIs of [Privacy Reference Test's AoR](https://app.asana.com/0/1200606622205980/list).

# Template

To make it easier to start we prepared a template for new tests - [/_template-new-feature/](/_template-new-feature). It will help you follow the conventions listed below.

# File structure

Each privacy feature should have its own top level folder e.g. `/privacy-reference-tests/privacy-configuration/`.
Within each folder following files are expected:

- `README.md` - explaining what feature is being tested, how, and describing all non-standard fields used in the `tests.json`
- `tests.json` - test metadata file (see next section). If needed there can be multiple of those following the `*_tests.json` naming convention.
- `*_reference.*` - optional reference files (e.g. tracker blocklists, feature configurations, surrogates) required to perform the test

# tests.json

The expected outline of the file is as follows:

```js
{
    "setName": { // id of a given set of tests
        "name": "", // name of the set
        "desc": "", // description of the set
        "tests": [
            {
                "name": "", // name of the particular test
                // test set specific fields go in here
                "expectSomething": "result" // field that is meant to verify the result should be prefixed with "expect"
                "exceptPlatforms": [] // platforms on which given test should be skipped (see "exceptPlatforms" section)
            }
        ]
    },
    "anotherSet": {
      //…
    }
}
```

Each `tests.json` file can contain multiple sets of tests. All fields should follow the camelCase format. `tests.json` is expected to be a valid JSON file (e.g. field names have to be in double quotes).

## Custom fields

Your tests will require some custom fields to set the stage for the test e.g. `"siteURL"`, `"scriptURL"`, `"requestType"` and a field that's responsible for validating the result e.g. `"expectAction": "block"`, `"expectFeatureEnabled": false`.

## exceptPlatforms

If test should be skipped on some platforms, e.g. because of the known limitations of the platform, please specify excepted platforms via `exceptPlatforms` field. Possible options are:

- "web-extension" & "web-extension-mv3" - our [Chrome/Firefox/Edge/Brave extension](https://github.com/duckduckgo/duckduckgo-privacy-extension)
- "safari-extension" - our [Safari extension](https://github.com/duckduckgo/privacy-essentials-safari)
- "ios-browser" - our [iOS application](https://github.com/duckduckgo/iOS)
- "android-browser" - our [Android application](https://github.com/duckduckgo/Android)
- "macos-browser" - our macOS browser
- "windows-browser" - our Windows browser
