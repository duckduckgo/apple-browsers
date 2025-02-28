//
//  FeatureFlagger.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// This protocol defines a common interface for feature flags managed by FeatureFlagger.
///
/// It should be implemented by the feature flag type in client apps.
///
public protocol FeatureFlagDescribing: CaseIterable {

    /// Returns a string representation of the flag, suitable for persisting the flag state to disk.
    var rawValue: String { get }

    var defaultValue: Bool { get }

    /// Return `true` here if a flag can be locally overridden.
    ///
    /// Local overriding mechanism requires passing `FeatureFlagOverriding` instance to
    /// the `FeatureFlagger`. Then it will handle all feature flags that return `true` for
    /// this property.
    ///
    /// > Note: Local feature flag overriding is gated by the internal user flag and has no effect
    ///   as long as internal user flag is off.
    var supportsLocalOverriding: Bool { get }

    /// Defines the source of the feature flag, which corresponds to
    /// where the final flag value should come from.
    ///
    /// Example client implementation:
    ///
    /// ```
    /// public enum FeatureFlag: FeatureFlagDescribing {
    ///    case sync
    ///    case autofill
    ///    case cookieConsent
    ///    case duckPlayer
    ///
    ///    var source: FeatureFlagSource {
    ///        case .sync:
    ///            return .disabled
    ///        case .cookieConsent:
    ///            return .internalOnly()
    ///        case .credentialsAutofill:
    ///            return .remoteDevelopment(.subfeature(AutofillSubfeature.credentialsAutofill))
    ///        case .duckPlayer:
    ///            return .remoteReleasable(.feature(.duckPlayer))
    ///    }
    /// }
    /// ```
    var source: FeatureFlagSource { get }

    /// Defines the type of cohort associated with the feature flag, if any.
    ///
    /// This property allows feature flags to define and associate with specific cohorts,
    /// which are groups of users categorized for experimentation or feature rollouts.
    ///
    /// - Returns: A type conforming to `FeatureFlagCohortDescribing`, or `nil` if no cohort is associated
    ///   with the feature flag.
    ///
    /// ### Example:
    /// For a feature flag with cohorts like "control" and "treatment":
    ///
    /// ```
    /// public enum ExampleFeatureFlag: FeatureFlagDescribing {
    ///     case experimentalFeature
    ///
    ///     var cohortType: (any FeatureFlagCohortDescribing.Type)? {
    ///         return ExampleCohort.self
    ///     }
    ///
    ///     public enum ExampleCohort: String, FeatureFlagCohortDescribing {
    ///         case control
    ///         case treatment
    ///     }
    /// }
    /// ```
    ///
    /// If `cohortType` is `nil`, the feature flag does not have associated cohorts.
    var cohortType: (any FeatureFlagCohortDescribing.Type)? { get }
}

/// A protocol that defines a set of cohorts for feature flags.
///
/// Cohorts represent groups of users categorized for A/B testing. Each cohort has a unique identifier (`CohortID`).
///
/// Types conforming to `FeatureFlagCohortDescribing` must be an `enum`, conform to
/// `CaseIterable`, and use a `RawValue` of type `CohortID` (typically a `String`).
///
/// ## Usage
///
/// To define cohorts for a feature flag, create an `enum` conforming to `FeatureFlagCohortDescribing`:
///
/// ```swift
/// public enum ExampleCohort: String, FeatureFlagCohortDescribing {
///     case control
///     case treatment
/// }
/// ```
///
/// These cohorts can then be associated with feature flags to segment users into different
/// groups for experimentation:
///
/// ```swift
/// public enum ExampleFeatureFlag: FeatureFlagDescribing {
///     case newUI
///
///     var cohortType: (any FeatureFlagCohortDescribing.Type)? {
///         return ExampleCohort.self
///     }
/// }
/// ```
///
/// ## Provided Utility Methods
///
/// - `cohort(for rawValue: CohortID) -> Self?`: Retrieves the cohort instance from its raw value.
/// - `cohorts: [Self]`: Returns an array of all defined cohorts.
public protocol FeatureFlagCohortDescribing: CaseIterable, RawRepresentable where RawValue == CohortID {}

/// A protocol for retrieving the current experiment cohort for feature flags if one has already been assigned.
protocol CurrentExperimentCohortProviding {
    func assignedCohort<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> (any FeatureFlagCohortDescribing)?
}

public extension FeatureFlagCohortDescribing {
    static func cohort(for rawValue: CohortID) -> Self? {
        return Self.allCases.first { $0.rawValue == rawValue }
    }
    static var cohorts: [Self] {
        return Array(Self.allCases)
    }
}

public enum FeatureFlagSource {
    /// Completely disabled in all configurations
    case disabled

    /// Completely enabled in all configurations
    case enabled

    /// Enabled for internal users only. Cannot be toggled remotely
    case internalOnly((any FeatureFlagCohortDescribing)? = nil)

    /// Toggled remotely using PrivacyConfiguration but only for internal users. Otherwise, disabled.
    case remoteDevelopment(PrivacyConfigFeatureLevel)

    /// Toggled remotely using PrivacyConfiguration for all users
    case remoteReleasable(PrivacyConfigFeatureLevel)
}

public enum PrivacyConfigFeatureLevel {
    /// Corresponds to a given top-level privacy config feature
    case feature(PrivacyFeature)

    /// Corresponds to a given subfeature of a privacy config feature
    case subfeature(any PrivacySubfeature)
}

public protocol FeatureFlagger: AnyObject {
    var internalUserDecider: InternalUserDecider { get }

    /// Local feature flag overriding mechanism.
    ///
    /// This property is optional and if kept as `nil`, local overrides
    /// are not in use. Local overrides are only ever considered if a user
    /// is internal user.
    var localOverrides: FeatureFlagLocalOverriding? { get }

    /// Called from app features to determine whether a given feature is enabled.
    ///
    /// Feature Flag's `source` is checked to determine if the flag should be toggled.
    /// If feature flagger provides overrides mechanism (`localOverrides` is not `nil`)
    /// and the user is internal, local overrides is checked first and if present,
    /// returned as flag value.
    ///
    /// > Note: Setting `allowOverride` to `false` skips checking local overrides. This can be used
    ///   when the non-overridden feature flag value is required.
    ///
    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool

    /// Retrieves the cohort for a feature flag if the feature is enabled.
    ///
    /// This method determines the source of the feature flag and evaluates its eligibility based on
    /// the user's internal status and the privacy configuration. It supports different sources, such as
    /// disabled features, internal-only features, and remotely toggled features.
    ///
    /// - Parameter featureFlag: A feature flag conforming to `FeatureFlagDescribing`.
    ///
    /// - Returns: The `CohortID` associated with the feature flag, or `nil` if the feature is disabled or
    ///   does not meet the eligibility criteria.
    ///
    /// - Behavior:
    ///   - For `.disabled`: Returns `nil`.
    ///   - For `.internalOnly`: Returns the cohort if the user is an internal user.
    ///   - For `.remoteDevelopment` and `.remoteReleasable`:
    ///     - If the feature is a subfeature, resolves its cohort using `resolveCohort(_ subfeature:)`.
    ///     - Returns `nil` if the user is not eligible.
    ///
    /// > Note: Setting `allowOverride` to `false` skips checking local overrides. This can be used
    ///   when the non-overridden feature flag value is required.

    /// Retrieves or attempts to assign a cohort for a feature flag if the feature is enabled.
    ///
    /// This method checks whether the feature flag is active based on its source configuration.
    /// If the flag is enabled and supports cohorts, it returns the assigned cohort if one exists.
    /// Otherwise, it attempts to resolve and assign the appropriate cohort from the available options.
    ///
    /// If local overrides are enabled (`allowOverride = true`) and the user is internal, the overridden
    /// cohort is returned before any other logic is applied.
    ///
    /// ## Behavior:
    /// - **For `.disabled` flags**: Returns `nil`.
    /// - **For `.internalOnly` flags**: Returns the predefined cohort if the user is an internal user.
    /// - **For `.remoteDevelopment` and `.remoteReleasable` flags**:
    ///   - If the feature is a subfeature, resolves its cohort using `resolveCohort(_ subfeature:)`.
    ///   - If no cohort is assigned yet, attempts to assign one from the available cohorts.
    ///
    /// > **Note**: If `allowOverride` is `false`, local overrides are ignored.
    ///
    /// ## Example:
    /// ```swift
    /// if let cohort = featureFlagger.resolveCohort(for: .newUI) as? ExampleCohort {
    ///     switch cohort {
    ///     case .treatment:
    ///         print("treatment")
    ///     case .control:
    ///         print("control")
    ///     }
    /// }
    /// ```
    ///
    /// In this example, `ExampleCohort` is the cohort type associated with the `.newUI` feature flag.
    /// The switch statement handles the assigned cohort values accordingly.
    ///
    /// - Parameter featureFlag: The feature flag for which to retrieve or assign a cohort.
    /// - Parameter allowOverride: Whether local overrides should be considered.
    /// - Returns: The assigned `FeatureFlagCohortDescribing` instance if the feature is enabled, or `nil` otherwise.
    func resolveCohort<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)?

    /// Retrieves all active experiments currently assigned to the user.
    ///
    /// This method iterates over the experiments stored in the `ExperimentManager` and checks their state
    /// against the current `PrivacyConfiguration`. If an experiment's state is enabled or disabled due to
    /// a target mismatch, and its assigned cohort matches the resolved cohort, it is considered active.
    ///
    /// - Returns: A dictionary of active experiments where the key is the experiment's subfeature ID,
    ///   and the value is the associated `ExperimentData`.
    ///
    /// - Behavior:
    ///   1. Fetches all enrolled experiments from the `ExperimentManager`.
    ///   2. For each experiment:
    ///      - Retrieves its state from the `PrivacyConfiguration`.
    ///      - Validates its assigned cohort using `resolveCohort` in the `ExperimentManager`.
    ///   3. If the experiment passes validation, it is added to the result dictionary.
    ///
    var allActiveExperiments: Experiments { get }
}

public extension FeatureFlagger {
    /// Called from app features to determine whether a given feature is enabled.
    ///
    /// Feature Flag's `source` is checked to determine if the flag should be toggled.
    /// If feature flagger provides overrides mechanism (`localOverrides` is not `nil`)
    /// and the user is internal, local overrides is checked first and if present,
    /// returned as flag value.
    ///
    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> Bool {
        isFeatureOn(for: featureFlag, allowOverride: true)
    }

    /// Called from app features to determine the cohort for a given feature, if enabled.
    ///
    /// Feature Flag's `source` is checked to determine if the flag is enabled. If the feature
    /// flagger provides an overrides mechanism (`localOverrides` is not `nil`) and the user
    /// is internal, local overrides are checked first and, if present, returned as the cohort.
    ///
    func resolveCohort<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> (any FeatureFlagCohortDescribing)? {
        resolveCohort(for: featureFlag, allowOverride: true)
    }
}

public class DefaultFeatureFlagger: FeatureFlagger {

    public let internalUserDecider: InternalUserDecider
    public let privacyConfigManager: PrivacyConfigurationManaging
    private let experimentManager: ExperimentCohortsManaging?
    public let localOverrides: FeatureFlagLocalOverriding?

    public init(
        internalUserDecider: InternalUserDecider,
        privacyConfigManager: PrivacyConfigurationManaging,
        experimentManager: ExperimentCohortsManaging?
    ) {
        self.internalUserDecider = internalUserDecider
        self.privacyConfigManager = privacyConfigManager
        self.experimentManager = experimentManager
        self.localOverrides = nil
    }

    public init<Flag: FeatureFlagDescribing>(
        internalUserDecider: InternalUserDecider,
        privacyConfigManager: PrivacyConfigurationManaging,
        localOverrides: FeatureFlagLocalOverriding,
        experimentManager: ExperimentCohortsManaging?,
        for: Flag.Type
    ) {
        self.internalUserDecider = internalUserDecider
        self.privacyConfigManager = privacyConfigManager
        self.localOverrides = localOverrides
        self.experimentManager = experimentManager
        localOverrides.featureFlagger = self

        // Clear all overrides if not an internal user
        if !internalUserDecider.isInternalUser {
            localOverrides.clearAllOverrides(for: Flag.self)
        }
    }

    public func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        if allowOverride, internalUserDecider.isInternalUser, let localOverride = localOverrides?.override(for: featureFlag) {
            return localOverride
        }
        switch featureFlag.source {
        case .disabled:
            return false
        case .enabled:
            return true
        case .internalOnly:
            return internalUserDecider.isInternalUser
        case .remoteDevelopment(let featureType):
            guard internalUserDecider.isInternalUser else {
                return false
            }
            return isEnabled(featureType, defaultValue: featureFlag.defaultValue)
        case .remoteReleasable(let featureType):
            return isEnabled(featureType, defaultValue: featureFlag.defaultValue)
        }
    }

    public var allActiveExperiments: Experiments {
        guard let enrolledExperiments = experimentManager?.experiments else { return [:] }
        var activeExperiments = [String: ExperimentData]()
        let config = privacyConfigManager.privacyConfig

        for (subfeatureID, experimentData) in enrolledExperiments {
            let state = config.stateFor(subfeatureID: subfeatureID, parentFeatureID: experimentData.parentID)
            guard state == .enabled || state == .disabled(.targetDoesNotMatch) else { continue }
            let cohorts = config.cohorts(subfeatureID: subfeatureID, parentFeatureID: experimentData.parentID) ?? []
            let experimentSubfeature = ExperimentSubfeature(parentID: experimentData.parentID, subfeatureID: subfeatureID, cohorts: cohorts)

            if experimentManager?.resolveCohort(for: experimentSubfeature, allowCohortAssignment: false) == experimentData.cohortID {
                activeExperiments[subfeatureID] = experimentData
            }
        }
        return activeExperiments
    }

    public func resolveCohort<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? {
        // Check for local overrides
        if allowOverride, internalUserDecider.isInternalUser, let localOverride = localOverrides?.experimentOverride(for: featureFlag) {
            return featureFlag.cohortType?.cohorts.first { $0.rawValue == localOverride }
        }

        // Handle feature cohort sources
        return handleCohortResolutionBasedOnSources(for: featureFlag, allowCohortAssignment: true)
    }

    private func handleCohortResolutionBasedOnSources<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowCohortAssignment: Bool) -> (any FeatureFlagCohortDescribing)? {
        // Handle feature cohort sources
        switch featureFlag.source {
        case .disabled:
            return nil
        case .internalOnly(let cohort):
            return cohort
        case .remoteReleasable(let featureType),
                .remoteDevelopment(let featureType) where internalUserDecider.isInternalUser:
            if case .subfeature(let subfeature) = featureType {
                if let resolvedCohortID = resolveCohort(subfeature, allowCohortAssignment: allowCohortAssignment) {
                    return featureFlag.cohortType?.cohort(for: resolvedCohortID)
                }
            }
            return nil
        default:
            return nil
        }
    }

    private func resolveCohort(_ subfeature: any PrivacySubfeature, allowCohortAssignment: Bool = true) -> CohortID? {
        let config = privacyConfigManager.privacyConfig
        let featureState = config.stateFor(subfeature)
        let cohorts = config.cohorts(for: subfeature)
        let experiment = ExperimentSubfeature(parentID: subfeature.parent.rawValue, subfeatureID: subfeature.rawValue, cohorts: cohorts ?? [])
        switch featureState {
        case .enabled:
            return experimentManager?.resolveCohort(for: experiment, allowCohortAssignment: allowCohortAssignment)
        case .disabled(.targetDoesNotMatch):
            return experimentManager?.resolveCohort(for: experiment, allowCohortAssignment: false)
        default:
            return nil
        }
    }

    private func isEnabled(_ featureType: PrivacyConfigFeatureLevel, defaultValue: Bool) -> Bool {
        switch featureType {
        case .feature(let feature):
            return privacyConfigManager.privacyConfig.isEnabled(featureKey: feature, defaultValue: defaultValue)
        case .subfeature(let subfeature):
            return privacyConfigManager.privacyConfig.isSubfeatureEnabled(subfeature, defaultValue: defaultValue)
        }
    }
}

extension DefaultFeatureFlagger: CurrentExperimentCohortProviding {
    func assignedCohort<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> (any FeatureFlagCohortDescribing)? {
        return handleCohortResolutionBasedOnSources(for: featureFlag, allowCohortAssignment: false)
    }
}
