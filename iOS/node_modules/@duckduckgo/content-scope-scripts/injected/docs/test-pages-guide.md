# Test Pages Guide

## Overview

The test-pages system is a comprehensive testing framework for Content Scope Scripts that validates feature functionality across different platforms (Android, Apple, Windows, and browser extensions). These test pages are shared by clients and can be run both in browsers and in CI environments.

## Architecture

### Directory Structure

```
injected/integration-test/test-pages/
├── index.html                    # Main entry point
├── blank.html                    # Minimal page for extension testing
├── shared/                       # Shared utilities and styles
│   ├── utils.js                  # Test framework utilities
│   ├── style.css                 # Common styling
│   └── ...
├── {feature-name}/               # Feature-specific test directories
│   ├── index.html                # Feature test index
│   ├── pages/                    # Individual test pages
│   │   └── {test-name}.html      # Test page implementations
│   ├── config/                   # Feature configurations
│   │   └── {config-name}.json    # JSON configuration files
│   └── scripts/                  # Additional test scripts (optional)
└── ...
```

### Key Components

#### 1. Test Pages (`pages/*.html`)

Individual HTML pages that implement specific test scenarios. Each page:

- Loads the Content Scope Scripts
- Defines test cases using the `test()` function
- Validates expected outcomes against actual results
- Renders results in a standardized format

#### 2. Configuration Files (`config/*.json`)

JSON files that define feature configurations for testing:

- Feature states (enabled/disabled)
- Settings and parameters
- Conditional logic and exceptions
- Platform-specific configurations

#### 3. Shared Utilities (`shared/utils.js`)

Provides the testing framework:

- `test(name, testFunction)` - Define test cases
- `renderResults()` - Execute tests and display results
- Result collection and validation
- Automation support for CI environments

## How It Works

### Test Execution Flow

1. **Page Loading**: Test pages are loaded with Content Scope Scripts injected
2. **Configuration Application**: Feature configurations are applied based on the test scenario
3. **Test Execution**: Individual test cases run and validate expected outcomes
4. **Result Collection**: Results are collected and displayed in a standardized format
5. **Validation**: CI systems validate that all tests pass across different platforms

### Example Test Page

```html
<!DOCTYPE html>
<html>
    <head>
        <title>Conditional Matching Test</title>
        <link rel="stylesheet" href="../../shared/style.css" />
    </head>
    <body>
        <script src="../../shared/utils.js"></script>

        <script>
            test('Conditional matching', async () => {
                const results = [
                    {
                        name: 'APIs changing, expecting to always match',
                        result: navigator.hardwareConcurrency,
                        expected: 222,
                    },
                ];

                // Test logic here...

                return results;
            });

            renderResults();
        </script>
    </body>
</html>
```

### Example Configuration

```json
{
    "readme": "This config tests conditional matching of experiments",
    "version": 1,
    "features": {
        "apiManipulation": {
            "state": "enabled",
            "settings": {
                "apiChanges": {
                    "Navigator.prototype.hardwareConcurrency": {
                        "type": "descriptor",
                        "getterValue": {
                            "type": "number",
                            "value": 222
                        }
                    }
                },
                "conditionalChanges": [
                    {
                        "condition": {
                            "urlPattern": "/test/*"
                        },
                        "patchSettings": [
                            {
                                "op": "replace",
                                "path": "/apiChanges/Navigator.prototype.hardwareConcurrency/getterValue/value",
                                "value": 333
                            }
                        ]
                    }
                ]
            }
        }
    }
}
```

**Tip**: The `apiManipulation` feature is particularly useful for testing config conditions because it modifies browser APIs in predictable ways. You can use it to validate that conditional logic, URL patterns, and other config conditions are being applied correctly by checking if the expected API values are returned.

## Platform Integration

### Cross-Platform Testing

The test pages are designed to work across multiple platforms:

- **Browser Extensions**: Tests run in extension context with injected content scripts
- **Android**: Tests run in WebView with platform-specific messaging
- **Apple**: Tests run in WKWebView with WebKit-specific implementations
- **Windows**: Tests run with Windows-specific global polyfills

### Platform-Specific Handling

The test framework automatically handles platform differences through the `ResultsCollector` class, which applies appropriate setup and polyfills for each platform during test execution.

## Running Tests

### Local Development

1. **Start the test server**:

    ```bash
    npm run serve
    ```

2. **Access test pages**:
    - Navigate to `http://localhost:3220/` for the main index
    - Browse to specific test categories and pages

### CI Integration

Tests are ran in CI environments:

```javascript
// Example CI test
test('Test infra', async ({ page }, testInfo) => {
    await testPage(
        page,
        testInfo,
        '/infra/pages/conditional-matching.html',
        './integration-test/test-pages/infra/config/conditional-matching.json',
    );
});
```

See [pages.spec.js](../integration-test/pages.spec.js) for complete CI test examples.

## Testing Best Practices

When writing integration tests, follow these important guidelines:

### 1. Avoid Custom State in Spec Files

It's unadvisable to add custom state for tests directly in `.spec.js` files as it makes validation difficult and reduces test reliability. If custom state is absolutely required, ensure this is clearly explained in the corresponding test HTML file with detailed comments about what state is being set and why it's necessary.

### 2. Platform Configuration

The `Platform` parameter can be passed to test functions to simulate different platform environments. This is demonstrated in the min-supported-version tests in [pages.spec.js](../integration-test/pages.spec.js):

- `minSupportedVersion (string)`: Uses `{ version: '1.5.0' }`
- `minSupportedVersion (int)`: Uses `{ version: 99 }`

This is needed when testing features that have platform-specific behavior or version requirements. The platform object allows testing how features behave under different version constraints without modifying the core test infrastructure.

### 3. Config-Driven Testing

Where possible, prefer purely config-driven testing to validate features. This approach:

- Makes tests more maintainable and readable
- Reduces coupling between test logic and implementation details
- Allows for easier test data management and updates
- Provides better separation of concerns between test setup and validation

For detailed testing guidelines and examples, see the [IMPORTANT TESTING GUIDELINES section](../integration-test/pages.spec.js#L7) in the pages.spec.js file.

## Interactive and Automation Modes

### Interactive Mode

- When the test page is loaded **without** `?automation=true` in the URL, a **"Run Tests" button** appears at the top of the page.
- This allows a human tester or a platform test harness to decide when to start the tests, rather than running them immediately on page load.
- Clicking the button will execute all defined tests and display the results.

### Automation Mode

- When the test page is loaded **with** `?automation=true` in the URL, tests will run automatically as soon as the Content Scope Scripts are initialized.
- This is used for CI and automated testing environments.
- Tests wait for Content Scope Scripts initialization
- Results are collected programmatically
- Standardized result format for validation

## Result Reporting and Visual Validation

- After the tests finish, the results are assigned to `window.results` as a standardized object.
- The results are also rendered as an HTML table on the page, with pass/fail indicators for each test case.
- This visual output can be used by visual testing tools (such as Maestro) to validate that the test run is complete and that all tests have passed.
- The test suite status is also displayed at the top of the page, showing "pass" or "fail" for the overall run.

## Result Format

Tests return results in a standardized format:

```javascript
{
    "Test Name": [
        {
            "name": "Specific test case",
            "result": "actual value",
            "expected": "expected value"
        }
    ]
}
```

Results are displayed in HTML tables with pass/fail indicators and can be collected programmatically for CI validation.

## Best Practices

### Creating Index Pages

When creating a new feature directory in the test pages system, it's best practice to include an `index.html` file that serves as a navigation hub for that feature's tests. This provides several benefits:

1. **Easy Navigation**: Developers can quickly browse available tests without digging through subdirectories
2. **Clear Organization**: Each feature directory has a consistent entry point
3. **Documentation**: The index page can include descriptions of what the feature tests cover
4. **Maintainability**: Makes it easier for new team members to understand the test structure

#### Index Page Template

```html
<!DOCTYPE html>
<html>
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width" />
        <title>Feature Name</title>
    </head>
    <body>
        <p><a href="../index.html">[Home]</a></p>

        <p>Feature Name</p>
        <ul>
            <li><a href="./pages/test-page-1.html">Test Page 1</a></li>
            <li><a href="./pages/test-page-2.html">Test Page 2</a></li>
        </ul>
    </body>
</html>
```

#### Key Elements

- **Navigation Link**: Always include a link back to the parent index page
- **Feature Title**: Clear heading indicating what feature is being tested
- **Test Links**: Organized list of all test pages in the `pages/` subdirectory
- **Consistent Structure**: Follow the same pattern as existing feature directories

### Writing Test Pages

1. **Use descriptive test names** that clearly indicate what is being tested
2. **Include multiple test cases** to cover different scenarios and edge cases
3. **Use realistic test data** that mimics real-world usage
4. **Include proper cleanup** for tests that modify state

### Writing Configurations

1. **Document the purpose** in the `readme` field
2. **Use semantic feature names** that match the codebase
3. **Include platform-specific configurations** when needed
4. **Keep configurations focused** on specific test scenarios

### Platform Compatibility

1. **Test across all platforms** to ensure consistency
2. **Handle platform-specific APIs** appropriately
3. **Use platform-agnostic test logic** when possible
4. **Validate messaging interfaces** work correctly
5. **Test fallback behaviors** for unsupported features

## Integration with Privacy Test Pages

The test pages are hosted at [https://privacy-test-pages.site/](https://privacy-test-pages.site/) and used by DuckDuckGo clients, platform teams, CI systems, and external developers to ensure consistent functionality across all platforms.
