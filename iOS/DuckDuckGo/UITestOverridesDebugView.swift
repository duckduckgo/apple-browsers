//
//  UITestOverridesDebugView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import SwiftUI
import Core
import PrivacyConfig

/// Debug view for verifying UI test overrides are applied correctly.
/// Is used in Maestro tests to assert that feature flags, config rollouts,
/// and experiments have been overridden as expected.
struct UITestOverridesDebugView: View {

    private let testFeatureFlag: FeatureFlag = .uiTestFeatureFlag
    private let testExperiment: FeatureFlag = .uiTestExperiment

    private let featureFlagger: FeatureFlagger
    private let privacyConfig: PrivacyConfiguration

    init(
        featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
        privacyConfig: PrivacyConfiguration = ContentBlocking.shared.privacyConfigurationManager.privacyConfig
    ) {
        self.featureFlagger = featureFlagger
        self.privacyConfig = privacyConfig
    }

    var body: some View {
        List {
            Section("Feature Flag (FeatureFlagger)") {
                featureFlagRow
            }

            Section("Experiment Cohort (FeatureFlagger)") {
                experimentRow
            }

            Section("Usage") {
                usageInfoRow
            }
        }
        .navigationTitle("UI Test Overrides")
    }

    // MARK: - Feature Flag Row

    private var featureFlagRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flag: \(testFeatureFlag.rawValue)")
                .font(.headline)

            Text("Maestro: -ff.\(testFeatureFlag.rawValue) true")
                .font(.caption)
                .foregroundColor(.gray)

            HStack {
                Text("Status:")
                Text(featureFlagStatus)
                    .fontWeight(.bold)
                    .foregroundColor(featureFlagger.isFeatureOn(testFeatureFlag) ? .green : .red)
                    .accessibilityIdentifier("ui-test-override-ff-value")
            }
        }
        .padding(.vertical, 4)
    }

    private var featureFlagStatus: String {
        featureFlagger.isFeatureOn(testFeatureFlag) ? "ENABLED" : "DISABLED"
    }

    // MARK: - Experiment Row (via FeatureFlagger)

    private var experimentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Experiment: \(testExperiment.rawValue)")
                .font(.headline)

            Text("Maestro: -experiment.uiTestExperiment control|treatment")
                .font(.caption)
                .foregroundColor(.gray)

            HStack {
                Text("Cohort:")
                Text(experimentCohortStatus)
                    .fontWeight(.bold)
                    .foregroundColor(experimentCohort != nil ? .green : .orange)
                    .accessibilityIdentifier("ui-test-override-experiment-value")
            }
        }
        .padding(.vertical, 4)
    }

    private var experimentCohort: (any FeatureFlagCohortDescribing)? {
        featureFlagger.resolveCohort(for: testExperiment)
    }

    private var experimentCohortStatus: String {
        experimentCohort?.rawValue ?? "NOT SET"
    }

    // MARK: - Usage Info Row

    private var usageInfoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Maestro Launch Arguments:")
                .font(.headline)

            Group {
                Text("Feature Flag:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("-ff.<flagRawValue> true/false")
                    .font(.caption)
                    .foregroundColor(.gray)

                Text("Config Rollout:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("-config.rollout.<parent>.<subfeature> true/false")
                    .font(.caption)
                    .foregroundColor(.gray)

                Text("Experiment:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("-experiment.<flagRawValue> <cohortId>")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationView {
        UITestOverridesDebugView()
    }
}
