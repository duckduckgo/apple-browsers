# Click To Load Tests

Privacy Feature: https://app.asana.com/0/1198207348643509/1199651947726592/f

## Goals

This set of tests verifies the Click to Load feature:

- Blocks/redirects requests when Click to Load is enabled for a tab.
- Ignores those requests when:
  - Click to Load isn't enabled for a tab.
  - The user clicked to load the content.
  - The content is first-party.
  - The Click to Load rule action isn't supported.

These tests do not aim to verify the placeholders, or other UI aspects of the feature.

## Structure

Files:

- `tds_reference.json` - Block list to be used when running the Click to Load tests.
- `config_reference.json` - Configuration to be used when running the Click to Load tests.
- `surrogates_reference.txt` - Surrogate script configuration to be used when running the Click to Load tests.
- `tests.json` - The Click to Load tests.

Test case fields:

- `siteUrl` - string - The currently loaded website's URL (as seen in the URL bar).
- `requestUrl` - string - The URL of the request being made.
- `userUnblockedRuleActions` - string[] - Array of Click to Load rule action that the user has unblocked for the page.
- `expectedOutcome` - "block", "redirect" or "ignore" - how request is expected to be handled ('redirect' means that surrogate was loaded instead of the original request).

## Pseudo-code implementation

```
loadReferenceConfig('config_reference.json')
loadReferenceBlocklist(tds_reference.json')

// Find the list of supported Click to Load rule actions.
$supportedRuleActions = []
if $config.features.clickToLoad.state == enabled:
  for $entity, $entity_settings in $config.features.clickToLoad.settings:
     if $entity_settings.state == enabled:
       for $ruleAction in $entity_settings.ruleActions:
          $supportedRuleActions.push($ruleAction)

for $testSet in test.json
  for $test in $testSet
    if $test.exceptPlatforms includes 'current-platform'
      skip

    // Prevent user unblocked content from being blocked.
    $actions = $supportedRuleActions.copy()
    for $action in $test.userUnblockedRuleActions:
      $actions.remove($action)

    // Prevent first-party blocking.
    $entity = findParentEntity($test.siteUrl)
    if $config.features.clickToLoad.settings[$entity]:
        for $action in $config.features.clickToLoad.settings[$entity].ruleActions:
           $actions.remove($action)

    // Prevent blocking Click to Load content if feature is disabled for tab.
    if !checkFeatureEnabled($test.siteUrl, "clickToLoad"):
      $actions = []

    // Check the expected matching outcome is correct for the test request.
    $result = findMatch($test.siteUrl, $test.requestUrl, $actions)
    expect($action).toBe($test.expectedOutcome)
```
