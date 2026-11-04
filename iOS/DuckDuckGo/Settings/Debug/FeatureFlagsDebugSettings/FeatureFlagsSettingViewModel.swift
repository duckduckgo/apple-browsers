//
//  FeatureFlagsSettingViewModel.swift
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

import Foundation
import Combine
import PrivacyConfig
import Core
import ContentScopeScripts
import FeatureFlags_iOS

@MainActor
class FeatureFlagsSettingViewModel: ObservableObject {

    enum StateFilter: String, CaseIterable {
        case all = "All"
        case enabled = "Enabled"
        case disabled = "Disabled"
    }

    private var cancellables = Set<AnyCancellable>()
    private let options = IOSDebugOptions.shared
    private let featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger

    @Published var featureFlags: [FeatureFlag] = []
    @Published var experiments: [FeatureFlag] = []
    @Published var searchText: String = ""
    @Published var stateFilter: StateFilter = .all

    var filteredFeatureFlags: [FeatureFlag] {
        var flags = featureFlags
        if !searchText.isEmpty {
            flags = flags.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
        }
        switch stateFilter {
        case .all:
            return flags
        case .enabled:
            return flags.filter { isFeatureEnabled($0) }
        case .disabled:
            return flags.filter { !isFeatureEnabled($0) }
        }
    }

    init() {
        self.isInternalUser = featureFlagger.internalUserDecider.isInternalUser
        self.featureFlags = FeatureFlag.allCases.filter { $0.supportsLocalOverriding && $0.cohortType == nil }.sorted(by: { $0.rawValue < $1.rawValue })
        self.experiments = FeatureFlag.allCases.filter { $0.supportsLocalOverriding && $0.cohortType != nil }.sorted(by: { $0.rawValue < $1.rawValue })
        options.objectWillChange.sink { [weak self] in
            guard let self else { return }
            if isInternalUser != options.isInternalUser {
                isInternalUser = options.isInternalUser
            }
            objectWillChange.send()
        }.store(in: &cancellables)
    }

    @Published var isInternalUser: Bool {
        didSet {
            options.setInternalUser(isInternalUser)
        }
    }

    func isFeatureEnabled(_ flag: FeatureFlag) -> Bool {
        return featureFlagger.isFeatureOn(for: flag)
    }

    func toggleFeatureFlag(_ flag: FeatureFlag, enabled: Bool) {
        do { try options.featureFlags.setEnabled(enabled, for: flag) } catch { options.report(error) }
    }

    func getCohorts(for experiment: any FeatureFlagDescribing) -> [String] {
        return experiment.cohortType?.cohorts.map { $0.rawValue } ?? []
    }

    func setExperimentCohort(for experiment: any FeatureFlagDescribing, cohort: String) {
        do { try options.featureFlags.setCohort(cohort, for: experiment) } catch { options.report(error) }
    }

    func getCurrentCohort(for experiment: any FeatureFlagDescribing) -> String? {
        return featureFlagger.localOverrides?.experimentOverride(for: experiment) ?? defaultExperimentCohort(for: experiment)
    }

    func resetOverride(for flag: any FeatureFlagDescribing) {
        do { try options.featureFlags.reset(flag) } catch { options.report(error) }
    }

    func resetAllOverrides() {
        do { try options.featureFlags.resetAll() } catch { options.report(error) }
    }

    func requiresRelaunch(_ flag: FeatureFlag) -> Bool {
        options.featureFlags.activation(for: flag) == "nextLaunch"
    }

    func defaultValue(for flag: any FeatureFlagDescribing) -> Bool {
        return featureFlagger.isFeatureOn(for: flag, allowOverride: false)
    }

    func defaultExperimentCohort(for flag: any FeatureFlagDescribing) -> CohortID? {
        return featureFlagger.assignedCohort(for: flag, allowOverride: false)?.rawValue
    }
}
