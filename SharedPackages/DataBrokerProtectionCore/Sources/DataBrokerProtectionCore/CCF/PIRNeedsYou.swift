//
//  PIRNeedsYou.swift
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

#if os(macOS) && DEBUG
import Foundation

/// A row in the dashboard's Needs you section: a broker's held scan, or its records waiting to be removed.
public struct DBPUINeedsYouItem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case optOut
        case scan
    }

    public enum State: String, Codable, Sendable {
        /// Held until the user starts it.
        case waiting
        case running
        case needsYou
    }

    public let id: String
    public let brokerName: String
    public let brokerUrl: String
    public let kind: Kind
    public let recordCount: Int
    public let state: State
}

public struct DBPUINeedsYouList: Codable, Equatable, Sendable {
    public let items: [DBPUINeedsYouItem]

    public init(items: [DBPUINeedsYouItem]) {
        self.items = items
    }
}

public extension PIRAssistItemID {
    /// The opaque id the dashboard sends back to open an item.
    var needsYouID: String {
        extractedProfileId.map { "optOut-\(brokerId)-\(profileQueryId)-\($0)" } ?? "scan-\(brokerId)-\(profileQueryId)"
    }

    init?(needsYouID: String) {
        let parts = needsYouID.split(separator: "-")
        let numbers = parts.dropFirst().compactMap { Int64($0) }
        guard numbers.count == parts.count - 1 else { return nil }
        switch (parts.first, numbers.count) {
        case ("optOut", 3): self.init(brokerId: numbers[0], profileQueryId: numbers[1], extractedProfileId: numbers[2])
        case ("scan", 2): self.init(brokerId: numbers[0], profileQueryId: numbers[1], extractedProfileId: nil)
        default: return nil
        }
    }
}

public enum PIRNeedsYou {
    /// A running job the user may need to see, which isn't necessarily still held (an email confirmation, say).
    public struct RunningItem: Equatable, Sendable {
        public let id: PIRAssistItemID
        public let brokerName: String
        public let brokerURL: String
        public let state: PIRAssistCenter.State

        public init(id: PIRAssistItemID, brokerName: String, brokerURL: String, state: PIRAssistCenter.State) {
            self.id = id
            self.brokerName = brokerName
            self.brokerURL = brokerURL
            self.state = state
        }
    }

    /// One row per broker and kind. Opening a row opens its running job, or starts its first held one.
    public static func items(pending: [PIRAssistedOptOut], running: [RunningItem]) -> [DBPUINeedsYouItem] {
        var rows: [(key: String, items: [PIRAssistedOptOut])] = []
        for item in pending {
            let key = item.brokerURL + (item.extractedProfileId == nil ? "#scan" : "#optOut")
            if let index = rows.firstIndex(where: { $0.key == key }) {
                rows[index].items.append(item)
            } else {
                rows.append((key, [item]))
            }
        }
        let runningByID = Dictionary(running.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var covered = Set<PIRAssistItemID>()
        var result: [DBPUINeedsYouItem] = rows.compactMap { row in
            guard let first = row.items.first else { return nil }
            let ids = row.items.map(PIRAssistItemID.init)
            covered.formUnion(ids)
            let active = ids.first { runningByID[$0]?.state == .needsYou } ?? ids.first { runningByID[$0] != nil }
            let state: DBPUINeedsYouItem.State = active.flatMap { runningByID[$0] }.map { $0.state == .needsYou ? .needsYou : .running } ?? .waiting
            return DBPUINeedsYouItem(id: (active ?? ids[0]).needsYouID, brokerName: first.brokerName, brokerUrl: bareDomain(first.brokerURL),
                                     kind: first.extractedProfileId == nil ? .scan : .optOut,
                                     recordCount: first.extractedProfileId == nil ? 0 : row.items.count, state: state)
        }
        for item in running where item.state == .needsYou && !covered.contains(item.id) {
            result.append(DBPUINeedsYouItem(id: item.id.needsYouID, brokerName: item.brokerName, brokerUrl: bareDomain(item.brokerURL),
                                            kind: item.id.extractedProfileId == nil ? .scan : .optOut,
                                            recordCount: item.id.extractedProfileId == nil ? 0 : 1, state: .needsYou))
        }
        return result
    }

    static func bareDomain(_ url: String) -> String {
        let absoluteURL = url.contains("://") ? url : "https://\(url)"
        guard let host = URL(string: absoluteURL)?.host?.lowercased() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
#endif
