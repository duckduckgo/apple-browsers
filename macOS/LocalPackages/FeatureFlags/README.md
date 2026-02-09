# FeatureFlags

This package contains all feature flags for our macOS app targets.

The convenience of having feature flags in a module is that we can quickly add this module
to new targets to get the `FeatureFlag` logic with minimum effort.

## Feature Flag Sources

`FeatureFlagSource` supports the following source types:

- `enabled`: Always enabled for all users. Not remotely toggleable.
- `disabled`: Always disabled for all users.
- `internalOnly`: Enabled only for internal users.
- `remoteDevelopment`: Remotely controlled, but only for internal users.
- `remoteReleasable`: Remotely controlled for all users.
