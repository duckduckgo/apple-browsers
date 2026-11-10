//
//  DataBrokerProtectionDebugJobs.swift
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

public extension BrokerStoring {

    /// Saves broker JSON from the debug server, replacing the stored broker with the same URL whatever its version.
    /// A remote update only replaces it again once remote config has a newer version.
    func replaceBroker(json: Data) throws -> DataBroker {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let resource = BrokerResource(broker: try decoder.decode(DataBroker.self, from: json), rawJSON: json)

        if let savedId = try vault.fetchBroker(with: resource.broker.url)?.id {
            try vault.update(resource, with: savedId)
            try handleBrokerVersionUpdate(brokerId: savedId)
        } else {
            try upsertBroker(resource)
        }
        return try vault.fetchBroker(with: resource.broker.url) ?? resource.broker
    }
}

public enum DataBrokerProtectionDebugJobs {

    /// Runs one broker's scan for one profile query in a visible window, outside the regular queue.
    public static func runScan(_ brokerProfileQueryData: BrokerProfileQueryData,
                               dependencies: BrokerProfileJobDependencyProviding) async throws -> Bool {
        try await BrokerProfileScanSubJob(dependencies: dependencies).runScan(brokerProfileQueryData: brokerProfileQueryData,
                                                                              showWebView: true,
                                                                              isManual: true,
                                                                              shouldRunNextStep: { !Task.isCancelled })
    }
}
