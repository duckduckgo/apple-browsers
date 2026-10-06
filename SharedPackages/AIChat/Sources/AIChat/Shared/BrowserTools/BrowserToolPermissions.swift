//
//  BrowserToolPermissions.swift
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
import Persistence

/// A stored decision for an `ask` tool. `ask` is the absence of one.
public enum BrowserToolPermissionState: String, Equatable, Sendable {
    case ask
    case allow
    case deny
}

/// The `choice` values the permission prompt offers, and the only ones native accepts back.
public enum BrowserToolPermissionChoice: String, Equatable, Sendable {
    case allowOnce
    case alwaysAllow
    case neverAllow
}

@MainActor
public protocol BrowserToolPermissionStoring: AnyObject {
    func state(forToolNamed name: String) -> BrowserToolPermissionState

    /// `.ask` forgets the tool's decision.
    func setState(_ state: BrowserToolPermissionState, forToolNamed name: String)

    var storedDecisions: [String: BrowserToolPermissionState] { get }
    func clearAll()
}

public extension BrowserToolPermissionStoring {

    /// An `auto` tool is always allowed; only `ask` tools have a stored decision.
    func effectiveState(for tool: any BrowserTool) -> BrowserToolPermissionState {
        tool.permissionMode == .auto ? .allow : state(forToolNamed: tool.name)
    }
}

enum BrowserToolPermissionStorageKey: String, StorageKeyDescribing {
    // Dot-free on purpose: dots break UserDefaults KVO, and `StorageKey` asserts on them.
    case decisions = "ai-chat_browser-tool-permissions"
}

public struct BrowserToolPermissionStorageKeys: StoringKeys {
    public let decisions = StorageKey<[String: String]>(BrowserToolPermissionStorageKey.decisions)
    public init() {}
}

/// `[toolName: "allow" | "deny"]` under one key, the layout Windows persists.
@MainActor
public final class BrowserToolPermissionStore: BrowserToolPermissionStoring {

    private let storage: any KeyedStoring<BrowserToolPermissionStorageKeys>

    public init(storage: any KeyedStoring<BrowserToolPermissionStorageKeys>) {
        self.storage = storage
    }

    public func state(forToolNamed name: String) -> BrowserToolPermissionState {
        Self.parse(decisions[name])
    }

    public func setState(_ state: BrowserToolPermissionState, forToolNamed name: String) {
        var decisions = decisions
        switch state {
        case .ask: decisions.removeValue(forKey: name)
        case .allow, .deny: decisions[name] = state.rawValue
        }
        self.decisions = decisions
    }

    public var storedDecisions: [String: BrowserToolPermissionState] {
        decisions.reduce(into: [:]) { result, entry in
            let state = Self.parse(entry.value)
            if state != .ask { result[entry.key] = state }
        }
    }

    public func clearAll() {
        storage.decisions = nil
    }

    private var decisions: [String: String] {
        get { storage.decisions ?? [:] }
        set { storage.decisions = newValue.isEmpty ? nil : newValue }
    }

    /// Anything unrecognised reads as `ask`, so a bad value can only ever cause an extra prompt.
    private static func parse(_ value: String?) -> BrowserToolPermissionState {
        switch value {
        case BrowserToolPermissionState.allow.rawValue: .allow
        case BrowserToolPermissionState.deny.rawValue: .deny
        default: .ask
        }
    }
}

/// The permission prompt every `ask` tool poses: one required `choice`.
public enum BrowserToolPermissionElicitation {

    public static let choiceSchema: JSONValue = [
        "type": "object",
        "properties": [
            "choice": [
                "type": "string",
                "enum": ["allowOnce", "alwaysAllow", "neverAllow"]
            ]
        ],
        "required": ["choice"]
    ]
}
