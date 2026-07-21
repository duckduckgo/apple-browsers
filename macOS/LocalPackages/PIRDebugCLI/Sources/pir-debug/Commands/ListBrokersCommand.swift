//
//  ListBrokersCommand.swift
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

import AppKit
import ArgumentParser
import DataBrokerProtectionCore
import Foundation

struct ListBrokersCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "list-brokers",
        abstract: "Resolve the rules source and print a name/url/version/steps summary as JSON.")

    @OptionGroup var rules: RulesSourceOptions
    @OptionGroup var out: OutputOptions

    struct BrokerSummary: Encodable {
        let name: String
        let url: String
        let version: String
        let optOutUrl: String
        let parent: String?
        let stepTypes: [String]
        let performsOptOutWithinParent: Bool
    }

    func execute() async -> Int32 {
        do {
            let provider = try rules.makeProvider()
            Log.info("Fetching brokers…")
            let brokers = try await provider.fetchBrokers()
            let summaries = brokers
                .sorted { $0.name < $1.name }
                .map { broker in
                    BrokerSummary(name: broker.name,
                                  url: broker.url,
                                  version: broker.version,
                                  optOutUrl: broker.optOutUrl,
                                  parent: broker.parent,
                                  stepTypes: broker.steps.map { $0.type.rawValue },
                                  performsOptOutWithinParent: broker.performsOptOutWithinParent())
                }
            try out.resultWriter.write(summaries)
            return CLIExit.success
        } catch let error as CLIUsageError {
            Log.error(error.message)
            return CLIExit.usageError
        } catch {
            Log.error(error.localizedDescription)
            return CLIExit.usageError
        }
    }
}
