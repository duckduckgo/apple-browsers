Remove the `$flag` feature flag from the $platform app in apple-browsers. The flag was $decision: keep the code path taken when the flag is $kept_path and delete the other path.

1. Search the codebase for `$flag`, ignoring case. The flag may appear in more casings and spellings than expected.
2. Remove the `$flag` case from `$feature_flag_file`, including every `switch` over it. Note which subfeature it maps to.
3. Remove that subfeature's case from `PrivacyFeature.swift` in BrowserServicesKit only if nothing else uses it.
4. At every call site, replace the flag check with the behaviour of the kept path. Delete branches, properties, parameters, mocks and doc comments that become dead.
5. Update the tests: remove stubs and overrides for the flag, and delete tests that only cover the deleted path. The remaining tests must cover the now-constant behaviour.
6. Do not edit the bundled privacy configuration JSON. It mirrors the remote configuration, which is managed server-side.
7. Build, run the affected unit tests and lint the changed files.
8. Title the PR `$platform: Remove $flag feature flag`. Describe the change in one line: the flag was $decision and its conditional code is removed. Put no links or Asana content in the code, commits or PR.
