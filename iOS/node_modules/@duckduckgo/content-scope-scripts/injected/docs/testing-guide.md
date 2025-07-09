# Testing Guide

## Overview

Depending on what you are changing, you may need to run the build processes locally, or individual tests. The following all run within GitHub Actions when you create a pull request, but you can run them locally as well.

## Quick Test Command

If you want to get a good feeling for whether a PR or CI run will pass/fail, you can run the `test` command which chains most of the following together:

```shell
# run this if you want some confidence that your PR will pass
npm test
```

## Individual Test Commands

### ESLint

See root-level package for lint commands

### TypeScript

See root-level package for TypeScript commands

### Unit Tests (Jasmine)

Everything for unit-testing is located in the `unit-test` folder. Jasmine configuration is in `unit-test/jasmine.json`.

```shell
npm run test-unit
```

### Feature Integration Tests (Playwright)

Everything within `integration-test` is integration tests controlled by Playwright.

```shell
npm run test-int
```

**Important**: When writing integration tests, follow the [testing best practices](../docs/test-pages-guide.md#testing-best-practices) outlined in the Test Pages Guide. These guidelines cover avoiding custom state in spec files, using platform configuration, and preferring config-driven testing approaches.

**Preferred Testing Approach**: The [Test Pages Guide](../docs/test-pages-guide.md) describes the most preferred type of testing for the `/injected` directory. Test pages are the preferred approach where possible because they are **sharable with platforms** - the same test pages can be used by Android, Apple, Windows, and browser extension teams, ensuring consistent functionality validation across all platforms.

### Feature Build Process

To produce all artefacts that are used by platforms, just run the `npm run build` command. This will create platform specific code within the `build` folder (that is not checked in).

```shell
npm run build
```

## Test Builds for Ship Review

Test builds are created with a GitHub workflow. The assets for Content Scope Scripts will be created on demand if they are absent (which they will be, if you're pointing to a branch of CSS).

1. Commit any changes to CSS and push a branch to the remote
2. Make sure you commit the submodule reference update in the Windows PR
3. Continue with "Build an installer for ship review / test"

## Debugging

### Adding Breakpoints

If you drop a `debugger;` line in the scripts and open DevTools window, the DevTools will breakpoint and navigate to that exact line in code when the debug point has been hit.

### Verifying CSS is Loaded

Open DevTools, go to the Console tab and enter `navigator.duckduckgo`. If it's defined, then Content Scope Scripts is running.
