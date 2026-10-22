//
//  TabOrganizerModels.swift
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

/// What the organizer knows about one tab. Content fields are filled only when requested.
struct TabSnapshot: Equatable {
    let id: String
    let title: String
    let host: String
    let path: String
    let isPinned: Bool
    let isCurrent: Bool
    let lastSelectedAt: Date?
    var pageType: String?
    var excerpt: String?
    /// The tab group the tab is in, if any.
    var groupName: String?
}

enum TabOrganizerRequest: Equatable {
    case groupByTopic
    case instruction(String)
}

enum TabGroupAction: String, CaseIterable, Codable {
    case keep
    case close
    case moveToNewWindow
    case bookmark
    case addToFavorites
    case createTabGroup
    case ungroup
    /// Only from "rename X to Y"; the new name is in `ProposedGroup.newName`.
    case rename

    /// What the action pickers offer; Rename only makes sense with a new name.
    static let choices: [TabGroupAction] = [.createTabGroup, .keep, .close, .moveToNewWindow, .bookmark, .addToFavorites, .ungroup]
}

struct ProposedGroup: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var tabIDs: [String]
    var action: TabGroupAction
    var newName: String?
}

struct TabOrganizerProposal: Equatable {
    var groups: [ProposedGroup]
    /// Set for requests like "a bookmark folder for each group": on top of existing results only the action changes.
    var actionForEachGroup: TabGroupAction?
}

enum TabOrganizerError: Error {
    case noTabs
    case modelUnavailable(String)
}

protocol TabOrganizing {
    func organize(_ tabs: [TabSnapshot], request: TabOrganizerRequest) async throws -> TabOrganizerProposal
}

// MARK: - AI response contract

/// Every backend returns one of these. Tab numbers are 1-based positions in the list sent to the model.
struct TopicResponse: Codable {
    struct Label: Codable {
        let tabNumber: Int
        let topic: String
    }
    let labels: [Label]
}

struct InstructionResponse: Codable {
    let name: String
    let matchingTabNumbers: [Int]
    let actionForMatching: TabGroupAction
    let actionForOthers: TabGroupAction
    /// Set when the request asks to split the matching tabs, e.g. "breed" for "separate dogs by breed".
    var groupBy: String?
    /// "A bookmark folder for each group", "close every group": the action applies per group, not to one match.
    var forEachGroup = false
    var groupEdit: GroupEdit = .none
    var newName: String?

    enum GroupEdit: String, Codable {
        case none, merge, moveInto, ungroup, rename
    }
}
