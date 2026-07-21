//
//  BrokerSelectionOptions.swift
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

import ArgumentParser
import DataBrokerProtectionCore
import Foundation

/// Selects one or more brokers from a resolved rules source by name or domain.
struct BrokerSelectionOptions: ParsableArguments {

    @Option(name: .long, help: "Broker name or domain to run.")
    var broker: String?

    @Flag(name: .long, help: "Run every broker in the source (required when no --broker is given).")
    var all = false

    /// Filters `brokers` per the selection. Throws ``CLIUsageError`` when nothing matches or when
    /// neither a selector nor `--all` was supplied.
    func select(from brokers: [DataBroker]) throws -> [DataBroker] {
        if let broker {
            let needle = broker.lowercased()
            let exact = brokers.filter { $0.name.lowercased() == needle || $0.url.lowercased() == needle }
            if !exact.isEmpty { return exact }
            let partial = brokers.filter { $0.name.lowercased().contains(needle) || $0.url.lowercased().contains(needle) }
            guard !partial.isEmpty else {
                throw CLIUsageError("No broker matches '\(broker)' in the rules source.")
            }
            return partial
        }
        if all {
            guard !brokers.isEmpty else {
                throw CLIUsageError("The rules source contains no brokers.")
            }
            return brokers
        }
        throw CLIUsageError("Select a broker with --broker <name-or-domain>, or pass --all.")
    }
}
