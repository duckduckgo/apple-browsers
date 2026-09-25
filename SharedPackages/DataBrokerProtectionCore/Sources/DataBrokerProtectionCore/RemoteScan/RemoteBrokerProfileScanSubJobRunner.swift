//
//  RemoteBrokerProfileScanSubJobRunner.swift
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

import Foundation
import os.log

/// POC scan runner that delegates the scan to the remote scan server instead of the hidden webview.
///
/// Submits one scan per broker/profile-query, polls until it reaches a terminal status, and returns
/// the matches as `[ExtractedProfile]`. Everything above the runner (`BrokerProfileScanSubJob`:
/// history events, opt-out scheduling, removal detection, run dates) is unchanged.
///
/// The overall deadline is the sub-job's `scanJobTimeout`; this runner only checks
/// `shouldRunNextStep` between polls for cancellation.
public final class RemoteBrokerProfileScanSubJobRunner: BrokerProfileScanSubJobWebRunning {

    enum Constants {
        static let actionID = "remoteScan"
    }

    public typealias Sleeper = (TimeInterval) async throws -> Void

    private let service: RemoteScanServiceProviding
    private let context: SubJobContextProviding
    private let pollInterval: TimeInterval
    private let sleep: Sleeper

    public init(service: RemoteScanServiceProviding,
                context: SubJobContextProviding,
                pollInterval: TimeInterval,
                sleep: @escaping Sleeper = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.service = service
        self.context = context
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    public func scan(showWebView: Bool,
                     shouldRunNextStep: @escaping () -> Bool) async throws -> [ExtractedProfile] {
        // `showWebView` is irrelevant here: there is no webview to show.
        let brokerId = Self.brokerId(for: context.dataBroker)
        let request = RemoteScanRequest(brokerId: brokerId,
                                        profile: RemoteScanProfile(profileQuery: context.profileQuery))

        guard shouldRunNextStep() else {
            throw DataBrokerProtectionError.cancelled
        }

        let submission = try await service.submit(request)
        Logger.dataBrokerProtection.log("🌐 [RemoteScan] Submitted scan \(submission.scanId, privacy: .public) for \(brokerId, privacy: .public)")

        while true {
            guard shouldRunNextStep() else {
                throw DataBrokerProtectionError.cancelled
            }

            let status = try await service.status(scanId: submission.scanId)
            switch status.status {
            case .completed:
                let matches = status.matches ?? []
                Logger.dataBrokerProtection.log("🌐 [RemoteScan] Scan \(submission.scanId, privacy: .public) completed with \(matches.count, privacy: .public) match(es)")
                return matches
            case .failed:
                let message = status.error?.message ?? "Remote scan failed"
                Logger.dataBrokerProtection.error("🌐 [RemoteScan] Scan \(submission.scanId, privacy: .public) failed: \(message, privacy: .public)")
                throw DataBrokerProtectionError.actionFailed(actionID: Constants.actionID, message: message)
            case .queued, .running:
                try await sleep(pollInterval)
            }
        }
    }

    /// The broker's JSON file name, which is how the server identifies broker definitions.
    static func brokerId(for dataBroker: DataBroker) -> String {
        "\(dataBroker.url).json"
    }
}
