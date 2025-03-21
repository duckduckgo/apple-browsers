# Tracker Blocking Related Tests

This folder contains tests for the following features:

- Tracker blocking - https://app.asana.com/0/1198207348643509/1199103718890844
- CNAME cloaking - https://app.asana.com/0/1198207348643509/1199093921854069
- Tracker allowlist feature in the  Privacy Configuration - https://app.asana.com/0/1198207348643509/1199981227466169
- Surrogates - https://app.asana.com/0/1198207348643509/1199093921854088/f

## Structure

### Tracker blocking, CNAME cloaking and surrogates

Files in the folder:
- `domain_matching_tests.json` - tests for tracker blocking, CNAME cloaking and surrogates
- `tracker_radar_reference.json` - reference blocklist file that should be used with `domain_matching_tests.json` tests
- `surrogates.txt` - reference surrogates file that should be used with `domain_matching_tests.json` tests

Test suite specific fields:
- `siteURL` - URL - page where request in question is made
- `requestURL` - URL - request in question
- `requestType` - mostly "image" or "script", but can be any of https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest/ResourceType - type of the resource being fetched
- `expectAction` - one of: null (don't block, not on a blocklist), ignore (don't block, exception), block, redirect (when should be replaced with a surrogate) - expected action that client should take
- `expectRedirect` - string - only if action is "redirect". This should contain url of the surrogate (base64'ed version of the correct surrogate file)
- `expectExpression` - string - only if action is "redirect". This should contain the expression to validate if the surrogate was correctly injected.

#### ⚠️ Note ⚠️

For tests with `expectAction == redirect` to be valid you need to assert either `expectRedirect` and/or `expectExpression` (at least one). The reason we have two different fields is because some platforms (like macOS/iOS) cannot assert against `expectRedirect`.

#### Platform exceptions

- "ports are ignored when matching rules" disabled for Apple platform ([bug report](https://app.asana.com/0/1163321984198618/1201849181617632/f))

### Privacy config allowlist

Files in the folder:
- `tracker_allowlist_matching_tests.json` - test for tracker allowlist feature - ⚠️ those tests don't follow the format used by other tests ⚠️
- `tracker_allowlist_tds_references.json` - reference blocklist file that should be used with `tracker_allowlist_matching_tests.json` tests
- `tracker_allowlist_references.json` - reference privacy config file that should be used with `tracker_allowlist_matching_tests.json` tests

Test suite specific fields:
- `site` - URL - page where request in question is made
- `request` - URL - request in question
- `isAllowlisted` - bool - if request is expected to be allowlisted or not

## Platform exceptions

- android-browser: Blocks when CNAME is same-entity. https://app.asana.com/0/414730916066338/1203532296782616/f
- ios-browser: Exceptions for options2 trackers caused by inability to construct rules from current tds as the last ignore rule invalidates all previous rules. https://app.asana.com/0/1203790657351911/1204149290597759/f; One exception for tracker.test is because Apple platforms are not going to receive any trackers with default action block and options - it is again due to inability to construct rules with the current algorithm. We will follow up in https://app.asana.com/0/1200443608678338/1204431436175798/f; Some exceptions for tests that use request types other than image or stylesheet. Scoped to be fixed: https://app.asana.com/0/0/1204643428963159/f
