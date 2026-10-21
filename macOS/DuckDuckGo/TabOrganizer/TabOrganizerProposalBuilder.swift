//
//  TabOrganizerProposalBuilder.swift
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

/// Turns a model response into groups of real tabs: drops unknown or repeated tab numbers,
/// merges topics that differ only in case, and collects whatever the model left out.
enum TabOrganizerProposalBuilder {

    static let maxTopicGroups = 6
    static let otherGroupName = "Other"
    static let everythingElseGroupName = "Everything else"

    static func proposal(from response: TopicResponse, tabs: [TabSnapshot]) -> TabOrganizerProposal {
        var assigned = Set<String>()
        var keys: [String] = []
        var names: [String: String] = [:]
        var members: [String: [String]] = [:]

        for label in response.labels {
            let topic = label.topic.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !topic.isEmpty, let tabID = tabID(for: label.tabNumber, in: tabs), assigned.insert(tabID).inserted else { continue }
            let key = topic.lowercased()
            if members[key] == nil {
                keys.append(key)
                names[key] = topic
            }
            members[key, default: []].append(tabID)
        }

        var groups = keys
            .map { ProposedGroup(name: names[$0] ?? $0, tabIDs: members[$0] ?? [], action: .keep) }
            .sorted { $0.tabIDs.count > $1.tabIDs.count }

        var other = tabs.map(\.id).filter { !assigned.contains($0) }
        if groups.count > maxTopicGroups {
            other = groups[(maxTopicGroups - 1)...].flatMap(\.tabIDs) + other
            groups = Array(groups.prefix(maxTopicGroups - 1))
        }
        if !other.isEmpty {
            groups.append(ProposedGroup(name: otherGroupName, tabIDs: other, action: .keep))
        }
        return TabOrganizerProposal(groups: groups)
    }

    static func proposal(from response: InstructionResponse, tabs: [TabSnapshot]) -> TabOrganizerProposal {
        var matching: [String] = []
        for number in response.matchingTabNumbers {
            if let tabID = tabID(for: number, in: tabs), !matching.contains(tabID) {
                matching.append(tabID)
            }
        }
        let others = tabs.map(\.id).filter { !matching.contains($0) }
        let name = response.name.trimmingCharacters(in: .whitespacesAndNewlines)

        let groups = [
            ProposedGroup(name: name.isEmpty ? "Matching tabs" : name, tabIDs: matching, action: response.actionForMatching),
            ProposedGroup(name: everythingElseGroupName, tabIDs: others, action: response.actionForOthers)
        ]
        return TabOrganizerProposal(groups: groups.filter { !$0.tabIDs.isEmpty })
    }

    private static func tabID(for number: Int, in tabs: [TabSnapshot]) -> String? {
        tabs.indices.contains(number - 1) ? tabs[number - 1].id : nil
    }
}
