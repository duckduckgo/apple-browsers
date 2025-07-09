# Content Scope Features API Reference

Each platform calls into the API exposed by [content-scope-features.js](../src/content-scope-features.js) where the relevant JavaScript file is included from `features/`. This file loads the relevant platform enabled features. The platform itself should adhere to the features lifecycle when implementing.

## Global API: `contentScopeFeatures`

The exposed API is a global called `contentScopeFeatures` and has three methods:

### `load()`

Calls the load method on all the features

### `init(arguments)`

Calls the init method on all the features. This should be passed the arguments object which has the following keys:

- **`platform`** - An object with:
    - `name` - A string of 'android', 'ios', 'macos' or 'extension'
- **`debug`** - `true` if debugging should be enabled
- **`globalPrivacyControlValue`** - `false` if the user has disabled GPC
- **`sessionKey`** - A unique session based key
- **`cookie`** - TODO
- **`site`** - An object with:
    - `isBroken` - `true` if remote config has an exception
    - `allowlisted` - `true` if the user has disabled protections
    - `domain` - The hostname of the site in the URL bar
    - `enabledFeatures` - An array of features to enable

### `urlChanged()`

Called when the top frame URL is changed (for Single Page Apps). Also ensures that path changes for config 'conditional matching' are applied.

### `update()`

Calls the update method on all the features
