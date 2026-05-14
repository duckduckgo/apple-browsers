//
//  ExperimentCohortsManager.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public typealias CohortID = String
public typealias SubfeatureID = String
public typealias ParentFeatureID = String
public typealias Experiments = [String: ExperimentData]

public struct ExperimentSubfeature {
    let parentID: ParentFeatureID
    let subfeatureID: SubfeatureID
    let cohorts: [PrivacyConfigurationData.Cohort]
}

public struct ExperimentData: Codable, Equatable {
    public let parentID: ParentFeatureID
    public let cohortID: CohortID
    public let enrollmentDate: Date

    public init(parentID: ParentFeatureID, cohortID: CohortID, enrollmentDate: Date) {
        self.parentID = parentID
        self.cohortID = cohortID
        self.enrollmentDate = enrollmentDate
    }
}

public protocol ExperimentCohortsManaging {
    /// Retrieves all the experiments a user is enrolled in
    var experiments: Experiments? { get }

    /// Resolves the cohort for a given experiment subfeature.
    ///
    /// This method determines whether the user is currently assigned to a valid cohort
    /// for the specified experiment. If the assigned cohort is valid (i.e., it matches
    /// one of the experiment's defined cohorts), the method returns the assigned cohort.
    /// Otherwise, the invalid cohort is removed, and a new cohort is assigned if
    /// `allowCohortAssignment` is `true`.
    ///
    /// - Parameters:
    ///   - experiment: The `ExperimentSubfeature` representing the experiment and its associated cohorts.
    ///   - allowCohortAssignment: A Boolean value indicating whether cohort assignment is allowed
    ///     if the user is not already assigned to a valid cohort.
    ///
    /// - Returns: The valid `CohortID` assigned to the user for the experiment, or `nil`
    ///   if no valid cohort exists and `allowCohortAssignment` is `false`.
    ///
    /// - Behavior:
    ///   1. Retrieves the currently assigned cohort for the experiment using the `subfeatureID`.
    ///   2. Validates if the assigned cohort exists within the experiment's cohort list:
    ///      - If valid, the assigned cohort is returned.
    ///      - If invalid, the cohort is removed from storage.
    ///   3. If cohort assignment is enabled (`allowCohortAssignment` is `true`), a new cohort
    ///      is assigned based on the experiment's cohort weights and saved in storage.
    ///      - Cohort assignment is probabilistic, determined by the cohort weights.
    ///
    func resolveCohort(for experiment: ExperimentSubfeature, allowCohortAssignment: Bool) -> CohortID?
}

public class ExperimentCohortsManager: ExperimentCohortsManaging {

    private var store: ExperimentsDataStoring
    private let randomizer: (Range<Double>) -> Double
    private let queue = DispatchQueue(label: "com.ExperimentCohortsManager.queue")
    private let fireCohortAssigned: (_ subfeatureID: SubfeatureID, _ experiment: ExperimentData) -> Void

    public var experiments: Experiments? {
        get {
            queue.sync {
                store.experiments
            }
        }
    }

    public init(store: ExperimentsDataStoring = ExperimentsDataStore(), randomizer: @escaping (Range<Double>) -> Double = Double.random(in:),
                fireCohortAssigned: @escaping (_ subfeatureID: SubfeatureID, _ experiment: ExperimentData) -> Void) {
        self.store = store
        self.randomizer = randomizer
        self.fireCohortAssigned = fireCohortAssigned
    }

    public func resolveCohort(for experiment: ExperimentSubfeature, allowCohortAssignment: Bool) -> CohortID? {
        queue.sync {
            let assignedCohort = cohort(for: experiment.subfeatureID)
            if experiment.cohorts.contains(where: { $0.name == assignedCohort }) {
                return assignedCohort
            }
            removeCohort(from: experiment.subfeatureID)
            return allowCohortAssignment ? assignCohort(to: experiment) : nil
        }
    }
}

// MARK: Helper functions
extension ExperimentCohortsManager {

    private func assignCohort(to subfeature: ExperimentSubfeature) -> CohortID? {
        let cohorts = subfeature.cohorts
        let totalWeight = cohorts.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return nil }

        let randomValue = randomizer(0..<Double(totalWeight))
        var cumulativeWeight = 0.0

        for cohort in cohorts {
            cumulativeWeight += Double(cohort.weight)
            if randomValue < cumulativeWeight {
                saveCohort(cohort.name, in: subfeature.subfeatureID, parentID: subfeature.parentID)
                fireCohortAssigned(subfeature.subfeatureID, ExperimentData(parentID: subfeature.parentID, cohortID: cohort.name, enrollmentDate: Date()))
                return cohort.name
            }
        }
        return nil
    }

    func cohort(for subfeatureID: SubfeatureID) -> CohortID? {
        guard let experiments = store.experiments else { return nil }
        return experiments[subfeatureID]?.cohortID
    }

    private func enrollmentDate(for subfeatureID: SubfeatureID) -> Date? {
        guard let experiments = store.experiments else { return nil }
        return experiments[subfeatureID]?.enrollmentDate
    }

    private func removeCohort(from subfeatureID: SubfeatureID) {
        guard var experiments = store.experiments else { return }
        experiments.removeValue(forKey: subfeatureID)
        store.experiments = experiments
    }

    private func saveCohort(_ cohort: CohortID, in experimentID: SubfeatureID, parentID: ParentFeatureID) {
        var experiments = store.experiments ?? Experiments()
        let experimentData = ExperimentData(parentID: parentID, cohortID: cohort, enrollmentDate: Date())
        experiments[experimentID] = experimentData
        store.experiments = experiments
    }
}
