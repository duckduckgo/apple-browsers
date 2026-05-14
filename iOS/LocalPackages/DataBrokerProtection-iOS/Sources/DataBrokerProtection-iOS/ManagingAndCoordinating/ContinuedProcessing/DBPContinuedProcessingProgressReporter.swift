//
//  DBPContinuedProcessingProgressReporter.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import DataBrokerProtectionCore
import Foundation

/// Tracks the user-visible progress for a continued-processing initial run.
///
/// Progress is modeled as two phase budgets:
/// - scans own the first half of the bar
/// - opt-outs own the second half
///
/// The scan budget is seeded up front from the initial scan plan. The opt-out budget is reserved
/// at the same size, then divided across runnable opt-outs once scans finish.
///
/// Heartbeat consumes the active phase budget one unit at a time. Job completion snaps the phase
/// forward to at least the sum of all completed jobs' allotted units so the reported progress stays
/// monotonic and anchored to real work.
final class DBPContinuedProcessingProgressReporter {
    struct Snapshot {
        let completed: Int64
        let total: Int64
    }

    private enum Phase {
        case scan
        case optOut
    }

    /// Mutable progress state for one half of the continued-processing run.
    ///
    /// This state drives a single phase of the user-visible progress bar:
    /// - `totalUnits` is the current budget assigned to the phase (e.g. `360`)
    /// - `completedUnits` is how much of that budget has been consumed (e.g. `95`)
    /// - `allottedUnitsByID` records how much of the phase budget belongs to each planned job,
    ///   (e.g. `jobA = 120`, `jobB = 120`, `jobC = 120`)
    /// - `completedIDs` records which planned jobs have finished (e.g. `[jobA]`)
    ///
    /// Example:
    /// if a scan phase has 3 jobs and each is allotted 120 units, then:
    /// - heartbeat increments `completedUnits` while work is still in progress
    /// - when one job finishes, its ID is added to `completedIDs`
    /// - progress then snaps forward to at least 120 completed units
    ///
    /// If all 360 units are consumed before the phase completes, heartbeat no longer turns
    /// `360 / 360` into `361 / 360`. Instead it grows both values together:
    /// - `360 / 360` becomes `361 / 361` then `362 / 362`
    /// This keeps the system UI moving
    ///
    /// When the phase completes, progress snaps to the full phase budget.
    /// For example, if the phase is at `245 / 360` when the last remaining job finishes,
    /// `completedUnits` snaps to `360`.
    private struct PhaseProgress<ID: Hashable> {
        var completedUnits: Int64 = 0
        var totalUnits: Int64 = 0
        var allottedUnitsByID: [ID: Int64] = [:]
        var completedIDs = Set<ID>()

        /// Seeds the phase with a uniform allotment per planned job.
        mutating func reset(jobIDs: [ID], allottedUnitsPerJob: Int64) {
            completedUnits = 0
            totalUnits = max(Int64(jobIDs.count) * allottedUnitsPerJob, allottedUnitsPerJob)
            allottedUnitsByID = Dictionary(uniqueKeysWithValues: jobIDs.map { ($0, allottedUnitsPerJob) })
            completedIDs = []
        }

        /// Seeds the phase with explicit per-job allotments while preserving the supplied phase total.
        mutating func reset(totalUnits: Int64, jobIDs: [ID], allottedUnitsPerJob: [Int64]) {
            completedUnits = 0
            self.totalUnits = totalUnits
            allottedUnitsByID = Dictionary(uniqueKeysWithValues: zip(jobIDs, allottedUnitsPerJob))
            completedIDs = []
        }

        /// Reserves a phase budget before the concrete job set is known.
        mutating func reserve(totalUnits: Int64) {
            completedUnits = 0
            self.totalUnits = totalUnits
            allottedUnitsByID = [:]
            completedIDs = []
        }

        /// Advances heartbeat within the existing budget, then grows the phase once the budget is exhausted.
        mutating func advanceHeartbeat() {
            if completedUnits < totalUnits {
                completedUnits += 1
            } else {
                completedUnits += 1
                totalUnits += 1
            }
        }

        /// Marks every planned job complete and snaps completed units to the full phase allotment.
        mutating func markAllCompleted() {
            completedIDs = Set(allottedUnitsByID.keys)
            completedUnits = max(completedUnits, totalUnits)
        }

        /// Marks one job complete and snaps completed units to the sum of all completed job allotments.
        mutating func markCompleted(_ id: ID) {
            guard allottedUnitsByID[id] != nil else { return }
            let inserted = completedIDs.insert(id).inserted
            guard inserted else { return }
            completedUnits = max(completedUnits, completedIDs.reduce(0) { total, id in
                total + (allottedUnitsByID[id] ?? 0)
            })
        }
    }

    // MARK: - Phase State

    private var phase: Phase?

    // MARK: - Phase Budgets

    private var scanProgress = PhaseProgress<DBPContinuedProcessingPlans.ScanJobID>()
    private var optOutProgress = PhaseProgress<DBPContinuedProcessingPlans.OptOutJobID>()
    /// Holds the pre-reserved second-half budget before runnable opt-outs are known.
    private var reservedOptOutUnits: Int64 = 0

    // MARK: - Run Setup

    /// Seeds the scan-phase budget from the initial plan and reserves an equally sized opt-out budget.
    ///
    /// The budget per scan job is derived from the expected scan duration and heartbeat interval.
    /// For example, if `scanJobTimeout` is 180s and `heartbeatInterval` is 1.5s, each scan job
    /// gets `120` budget units. A plan with 3 scans starts at `3 × 120 = 360` scan units plus
    /// an equal `360` reserved for opt-outs, totaling `720` units split 50/50.
    func startInitialRun(plan: DBPContinuedProcessingPlans.InitialScanPlan,
                         scanJobTimeout: TimeInterval,
                         heartbeatInterval: TimeInterval) {
        let scanBudgetUnitsPerJob = max(Int64(scanJobTimeout / heartbeatInterval), 1)
        phase = .scan
        scanProgress.reset(jobIDs: plan.scanJobIDs, allottedUnitsPerJob: scanBudgetUnitsPerJob)
        // Reserve a fixed second half up front so the total budget stays a 50/50 scan/opt-out split.
        reservedOptOutUnits = scanProgress.totalUnits
        optOutProgress.reserve(totalUnits: scanProgress.totalUnits)
    }

    /// Divides the reserved opt-out budget across the runnable opt-out plan.
    func enterOptOutPhase(plan: DBPContinuedProcessingPlans.OptOutPlan) {
        phase = .optOut
        let allottedUnitsPerJob = distribute(totalUnits: reservedOptOutUnits, acrossItemCount: plan.optOutJobIDs.count)
        optOutProgress.reset(totalUnits: reservedOptOutUnits, jobIDs: plan.optOutJobIDs, allottedUnitsPerJob: allottedUnitsPerJob)
    }

    // MARK: - Progress Updates

    /// Advances the active phase by one heartbeat tick.
    func advanceHeartbeat() {
        switch phase {
        case .scan: scanProgress.advanceHeartbeat()
        case .optOut: optOutProgress.advanceHeartbeat()
        case .none: return
        }
    }

    /// Snaps the scan phase to its full allotted budget.
    func completeScanPhase() {
        scanProgress.markAllCompleted()
    }

    /// Snaps the opt-out phase to its full allotted budget.
    func completeOptOutPhase() {
        optOutProgress.markAllCompleted()
    }

    /// Marks both phases as complete so the overall progress reaches 100%.
    func completeAll() {
        completeScanPhase()
        completeOptOutPhase()
    }

    /// Marks a scan job complete and snaps scan progress up to the sum of completed scan allotments.
    func recordCompletedScan(_ id: DBPContinuedProcessingPlans.ScanJobID) {
        scanProgress.markCompleted(id)
    }

    /// Marks an opt-out job complete and snaps opt-out progress up to the sum of completed opt-out allotments.
    func recordCompletedOptOut(_ id: DBPContinuedProcessingPlans.OptOutJobID) {
        optOutProgress.markCompleted(id)
    }

    // MARK: - Reporting

    /// Returns the current combined progress snapshot for scans and opt-outs.
    func snapshot() -> Snapshot {
        Snapshot(completed: scanProgress.completedUnits + optOutProgress.completedUnits,
                 total: max(scanProgress.totalUnits + optOutProgress.totalUnits, 1))
    }

    /// Builds the scan-phase subtitle shown by the system task UI.
    var scanSubtitle: String {
        uniqueScanBrokerCount > 0 ? "Scanning \(completedScanBrokerCount) of \(uniqueScanBrokerCount) brokers" : "Scanning brokers"
    }

    /// Builds the opt-out-phase subtitle shown by the system task UI.
    var optOutSubtitle: String {
        "Submitting opt-out requests"
    }

    // MARK: - Helpers

    /// Evenly distributes a phase budget across a fixed number of planned jobs.
    ///
    /// Example:
    /// Distributing `360` units across `3` jobs returns `[120, 120, 120]`.
    /// Distributing `362` units across `3` jobs returns `[121, 121, 120]`,
    /// with the remainder assigned to the first jobs.
    private func distribute(totalUnits: Int64, acrossItemCount itemCount: Int) -> [Int64] {
        guard itemCount > 0 else { return [] }

        let baseUnits = totalUnits / Int64(itemCount)
        let remainder = totalUnits % Int64(itemCount)

        // Spread any remainder across the first few jobs so the full phase budget is assigned.
        return (0..<itemCount).map { index in
            baseUnits + (Int64(index) < remainder ? 1 : 0)
        }
    }

    /// Counts distinct brokers represented in the planned scan set.
    private var uniqueScanBrokerCount: Int {
        Set(scanProgress.allottedUnitsByID.keys.map(\.brokerId)).count
    }

    /// Counts brokers whose full set of scan jobs has finished.
    private var completedScanBrokerCount: Int {
        let scanIDsGroupedByBroker = Dictionary(grouping: scanProgress.allottedUnitsByID.keys, by: \.brokerId)
        return scanIDsGroupedByBroker
            .values
            .filter { brokerScanIDs in brokerScanIDs.allSatisfy(scanProgress.completedIDs.contains) }
            .count
    }

}
